library(debrowser)

header <- dashboardHeader(
  title = "DEBrowser Condition Selector"
)
sidebar <- dashboardSidebar(  sidebarMenu(id="DataPrep",
    menuItem("CondSelect", tabName = "CondSelect")
))

body <- dashboardBody(
  tabItems(
    tabItem(tabName="CondSelect",
    condSelectUI("cs"),
    column(12,
           verbatimTextOutput("denum")
    ))
))

ui <- dashboardPage(header, sidebar, body, skin = "blue")

server <- function(input, output, session) {
  load(system.file("extdata", "demo", "demodata.Rda",
                   package = "debrowser"))
  sel <- debrowsercondselectServer("cs", demodata, metadatatable)
  output$denum <- renderPrint({
    head(sel$cc())
  })
}

shinyApp(ui, server)
