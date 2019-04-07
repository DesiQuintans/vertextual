
# Set up packages and internal data ---------------------------------------

library(shiny)
library(tidyr)
library(dplyr)
library(igraph)
library(networkD3)

default_connections <- "Sean > Steven\n^ Connor\n^ Samara\nSean > Majdi\n> Preston\n> Porscha\n> Sean\nMajdi > Madeeha\nPorscha > Erick\n> Marrissa"


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
                               sliderInput("label_size", "Label size", 
                                           min = 8, max = 48, step = 1, value = 24)
                        ),
                        
                        column(width = 6,
                               sliderInput("node_dist", "Node distance", 
                                           min = 0, max = 200, step = 5, value = 75)
                        )
                    ),
                    
                    h3("Edge appearance"),
                    sliderInput("edge_thick", "Line thickness", 
                                min = 1, max = 10, step = 1, value = 2)
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
                    p("You can name connections in any order. Duplicate 
                      connections and self-loops will be automatically removed.")
                )
            )
        ),
        
        mainPanel(width = 9,
                  simpleNetworkOutput("network", height = "800px")
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
    
    # Plot a graph with networkD3
    # http://www.r-graph-gallery.com/87-interactive-network-with-networkd3-package/
    plot_nd3 <- function(lines) {
        
        # Create dataframes for network graph
        edges <- 
            build_graph_df(lines) %>% 
            rename(origin = from, target = to)
        
        nodes <- 
            tibble(label = unique(unlist(edges))) %>% 
            mutate(id = row_number())
        
        g <- graph.data.frame(edges, directed = F, vertices = nodes)
        
        nodes <- 
            nodes %>% 
            # mutate(group = edge.betweenness.community(g)$membership) %>% 
            mutate(group = walktrap.community(g)$membership) %>% 
            as.data.frame()
        
        edges <- 
            edges %>% 
            left_join(select(nodes, origin = label, origin_id = id), by = "origin") %>% 
            left_join(select(nodes, target = label, target_id = id), by = "target") %>% 
            mutate_at(vars(ends_with("_id")), ~ . - 1) %>% 
            as.data.frame()
        
        
        # Draw the graph
        
        par(
            oma = c(0, 0, 0, 2),  # Outer margin in lines of text
            cex.main = 2  # Magnification of title
        )
        
        forceNetwork(
            Links = edges, Nodes = nodes,
            Source = "origin_id", Target = "target_id",
            NodeID = "label", 
            linkWidth = input$edge_thick, linkDistance = input$node_dist,
            Group = "group",
            charge = -(input$node_dist * 15) - 100,
            zoom = TRUE,
            fontSize = input$label_size,
            fontFamily = "sans-serif",
            opacityNoHover = 1,
            opacity = 1
        )
    }
    
    output$network <- 
        renderForceNetwork(plot_nd3(input$user_edges))
}

# Run the application 
shinyApp(ui = ui, server = server)
