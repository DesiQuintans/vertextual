
# Set up packages and internal data ---------------------------------------

library(shiny)
library(dplyr)
library(igraph)

default_connections <- "Daydream > Daydream\nDaydream > Idea\n> Sketch\n> Prototype\n> Test\n> Evaluate\n> Refine\n> Sketch\n^ Polish\n> Refine\n^ Ship it!\n> Daydream"


# Draw the Shiny app ------------------------------------------------------

ui <- 
fluidPage(
    
    p(),
                
    # Hiding this so that I have a more consistent UI
    titlePanel("Vertextual: Build network diagrams and mindmaps with plain text"),
    hr(),
    
    sidebarLayout(
        sidebarPanel(width = 3,
            tabsetPanel(type = "tabs",
                tabPanel("Nodes and edges",
                    br(),
                    textInput("title",
                              "Network title",
                              value = "The software development process"),
                    textAreaInput("user_edges",
                                  "Nodes and edges",
                                  width = "100%",
                                  height = "100%",
                                  rows = 20,
                                  value = default_connections)
                    
                ),
                tabPanel("Appearance",
                    h3("Node appearance"),
                    fluidRow(
                        column(width = 6,
                            sliderInput("vert_size", "Node size",
                                        min = 0, max = 50, step = 1, value = 40),
                            selectInput("vert_shape", "Node shape", 
                                        c("rectangle", "circle", "square", "none"))
                        ),
                        
                        column(width = 6,
                            sliderInput("label_size", "Label size", 
                                        min = 1, max = 5, step = 0.5, value = 1.5),
                            br(),
                            checkboxInput("root_only", 
                                          "Display the shape for the first node only", 
                                          value = TRUE)
                        )
                    ),
                    
                    br(),
                    
                    h3("Edge appearance"),
                    fluidRow(
                        column(width = 6,
                            sliderInput("edge_thick", "Line thickness", 
                                        min = 1, max = 5, step = 0.5, value = 1.5),
                            selectInput("edge_shape", "Line type", 
                                        c("solid", "dashed", "dotted", "none" = "blank"))
                        ),
                        
                        column(width = 6,
                            sliderInput("arrw_thick", "Arrow size",
                                        min = 0, max = 5, step = 0.5, value = 1),
                            sliderInput("edge_curve", "Line curviness",
                                        min = 0, max = 1, step = 0.10, value = 0.1)
                        )
                    )
                ),
                tabPanel("Help",
                    h3("Building networks from text"),
                    p("In Vertextual, you build a network by naming its nodes 
                      and their edges (connections)."),
                    p("The first edge always has to be fully defined as ", 
                      code("Origin > Destination"), "like so:"),
                    pre("Daydream > Idea"),
                    p("Each new edge goes on a new line. You can continue 
                      writing full definitions for the rest of the edges, or 
                      you can reuse the last", code("Destination"), "node as 
                      the new", code("Origin"), "by omitting the", 
                      code("Origin"), "from the new definition:"),
                    
                    pre("Daydream > Idea\n> Sketch\n> Prototype"),
                    p("Is identical to"),
                    pre("Daydream > Idea\nIdea > Sketch\nSketch > Prototype"),
                    
                    p("You can also reuse the last", code("Origin"), "as the 
                      new", code("Origin"), "with the operator", code("^"), ":"),
                    
                    pre("Daydream > Idea\n^ Sketch\n^ Prototype"),
                    p("Is identical to"),
                    pre("Daydream > Idea\nDaydream > Sketch\nDaydream > Prototype"),
                    
                    p("Circular networks can be made by looping back to an 
                    already-existing node. Bi-directional edges and even 
                      self-loops can be made too."),
                    pre("# A bi-directional loop\nPolish > Refine\n> Polish"),
                    pre("# A self-loop\nDaydream > Daydream"),
                    p("You can name connections in any order. Duplicate 
                      connections will be automatically removed.")
                )
            )
        ),
        
        # Show a plot of the generated distribution
        mainPanel(width = 9,
            tabsetPanel(type = "tabs",
                tabPanel("Graph", plotOutput("network", height = "800px")),
                tabPanel("Dataframe", verbatimTextOutput("code"))
            )
        )
    )
)


# Server logic ------------------------------------------------------------

server <- function(input, output) {
    # Turn a dataframe into a tribble function call.
    # https://stackoverflow.com/a/42840914/5578429
    mc_tribble <- function(df, indents = 4) {
        TAB  <- paste(rep.int(" ", indents), collapse = "")  # One indent level
        
        meat <- capture.output(write.csv(df, quote = TRUE, row.names = FALSE))
        meat <- gsub(",", ", ", meat, fixed = TRUE)
        
        obj_name <- paste0("edges", " <- ", "\n")
        fun_call <- paste0(TAB, "tibble::tribble(", "\n")
        col_line <- paste0(TAB, TAB, paste(sprintf("~%s", names(df)), collapse = ", "), ", ", "\n")
        df_lines <- paste0(TAB, TAB, meat[-1], ",\n")
        end_func <- paste0(TAB, ")")
        
        c(obj_name, fun_call, col_line, df_lines, end_func)
    }
    
    # Build a dataframe from the user's text input.
    build_graph_df <- function(lines) {
        suppressWarnings(
            df <-
                # Text input as one column, with one line per row.
                read.delim(text = lines, sep = "\n", header = FALSE, 
                           stringsAsFactors = FALSE) %>% 
                # Split the column into 3 parts.
                tidyr::extract(1, 
                               into = c("from", "action", "to"), 
                               regex = "^(.*?)\\s{0,}(>|\\^)\\s{0,}(.*?)$") %>% 
                # Replace empty cells with NAs for filling
                mutate_at(vars(from, to), ~ ifelse(nchar(.) == 0, NA_character_, .)) %>%
                # These next steps cannot be done in a case_when() because the ^ action 
                # will not be properly applied.
                # 1. First try to fill any empty 'to' fields.
                # 2. Fill > operator (use last destination).
                # 3. Fill ^ operator (use last origin).
                mutate(to   = ifelse(is.na(to), from, to)) %>% 
                mutate(from = ifelse(is.na(from) & action == ">", lag(to), from)) %>% 
                fill(from, .direction = "down") %>% 
                select(from, to) %>% 
                na.omit() %>%
                distinct()
        )
    }
    
    # Plot a graph
    plot_graph <- function(lines) {
        graph <- graph_from_data_frame(build_graph_df(lines))
        graph_layout <- layout_with_kk(graph)
        
        
        # Vertex appearance
        vert_size  <- input$vert_size
        vert_shape <- 
            if(input$root_only == TRUE) {
                c(input$vert_shape, rep("none", length(V(graph)) - 1))
            } else {
                input$vert_shape
            }
        vert_color <- "white"  # "lemonchiffon"
        
        # Vertex labels
        label_font <- "sans"
        label_size <- input$label_size
        
        # Edge appearance
        edge_thick <- input$edge_thick
        arrw_thick <- input$arrw_thick
        edge_curve <- input$edge_curve
        edge_shape <- input$edge_shape
        
        
        par(
            oma = c(0, 0, 0, 2),  # Outer margin in lines of text
            cex.main = 2  # Magnification of title
        )
        
        
        plot(graph, 
             # Vertices
             vertex.size = vert_size,
             vertex.shape = vert_shape,
             vertex.color = vert_color,
             
             # Labels
             vertex.label.family = label_font,
             vertex.label.cex = label_size,
             
             # Edges
             edge.width = edge_thick,
             edge.arrow.size = arrw_thick,
             edge.curved = edge_curve,
             edge.lty = edge_shape,
             
             # Other
             layout = graph_layout,
             rescale = TRUE,
             frame = TRUE,
             main = input$title
        )
    }
    
    output$network <- 
        renderPlot(plot_graph(input$user_edges))
    
    output$code <- 
        renderText(mc_tribble(build_graph_df(input$user_edges)))
}

# Run the application 
shinyApp(ui = ui, server = server)
