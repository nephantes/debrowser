#' debrowserbatcheffect
#'
#' Module to correct batch effect
#'
#' @param id, namespace id
#' @param ldata, loaded data
#' @return main plot
#'
#' @return panel
#' @export
#'
#' @examples
#' \donttest{
#' x <- debrowserbatcheffect("batch")
#' }
#'
debrowserbatcheffect <- function(id, ldata = NULL) {
  if (is.null(ldata)) {
    return(NULL)
  }
  moduleServer(id, function(input, output, session) {
  batchdata <- reactiveValues(count = NULL, meta = NULL)
  observeEvent(input$submitBatchEffect, {
    if (is.null(ldata$count)) {
      return(NULL)
    }
    # B3.32 -- Top-level safety net: any unhandled error inside
    # normalization / batch-correction is surfaced as a friendly toast
    # so the observer (and the page) keeps working. The inner
    # correctCombat / correctHarman calls also tryCatch their own
    # ComBat/Harman failures; this is the belt-and-suspenders layer.
    tryCatch({
      countData <- ldata$count
      withProgress(message = "Normalization",
                   detail = "Normalization", value = NULL, {
        if (input$norm_method != "none") {
          countData <- tryCatch(
            getNormalizedMatrix(ldata$count, method = input$norm_method),
            error = function(e) {
              de_notify_error(paste0(
                "Normalization (", input$norm_method,
                ") failed: ", conditionMessage(e),
                " -- try a different method."
              ))
              NULL
            }
          )
        }
      })
      if (is.null(countData)) return(NULL)

      withProgress(message = "Batch Effect Correction",
                   detail = "Adjusting the Data", value = NULL, {
        if (input$batchmethod == "CombatSeq" | input$batchmethod == "Combat") {
          batchdata$count <- correctCombat(input, countData, ldata$meta,
                                           method = input$batchmethod)
        } else if (input$batchmethod == "Harman") {
          batchdata$count <- correctHarman(input, countData, ldata$meta)
        } else {
          batchdata$count <- countData
        }
      })
      if (is.null(batchdata$count)) {
        return(NULL)
      }
      batchdata$meta <- ldata$meta
    }, error = function(e) {
      de_notify_error(paste0(
        "Batch effect step failed: ", conditionMessage(e),
        " -- adjust your settings and click Submit again."
      ))
    })
  })

  output$batchfields <- renderUI({
    if (!is.null(ldata$meta)) {
      list(conditionalPanel(
        condition = paste0("input['", session$ns("batchmethod"), "']!='none'"),
        selectGroupInfo(ldata$meta, input, session$ns("treatment"), "Treatment"),
        selectGroupInfo(ldata$meta, input, session$ns("batch"), "Batch")
      ))
    }
  })

  batcheffectdata <- reactive({
    ret <- NULL
    if (!is.null(batchdata$count)) {
      ret <- batchdata
    }
    return(ret)
  })

  observe({
    getSampleDetails(output, "uploadSummary", "sampleDetails", ldata)
    getSampleDetails(output, "filteredSummary", "filteredDetails", batcheffectdata())
    getTableDetails(output, session, "beforebatchtable", ldata$count, modal = TRUE)
    debrowserpcaplot("beforeCorrectionPCA", ldata$count, ldata$meta)
    debrowserIQRplot("beforeCorrectionIQR", ldata$count)
    debrowserdensityplot("beforeCorrectionDensity", ldata$count)
    if (!is.null(batcheffectdata()$count) && nrow(batcheffectdata()$count) > 2) {
      withProgress(message = "Drawing the plot", detail = "Preparing!", value = NULL, {
        getTableDetails(output, session, "afterbatchtable", batcheffectdata()$count, modal = TRUE)
        debrowserpcaplot("afterCorrectionPCA", batcheffectdata()$count, batcheffectdata()$meta)
        debrowserIQRplot("afterCorrectionIQR", batcheffectdata()$count)
        debrowserdensityplot("afterCorrectionDensity", batcheffectdata()$count)
      })
    }
  })

  list(BatchEffect = batcheffectdata)
  })
}


#' batchEffectUI
#' Creates a panel to coorect batch effect
#'
#' @param id, namespace id
#' @return panel
#' @examples
#' x <- batchEffectUI("batcheffect")
#'
#' @export
#'
batchEffectUI <- function(id) {
  ns <- NS(id)

  list(
    fluidRow(
      bslib::card(
        bslib::card_header("Batch Effect Correction and Normalization"),
        bslib::layout_columns(
          col_widths = c(5, 2, 5),
          tagList(
            div(
              style = "overflow: scroll",
              tableOutput(ns("uploadSummary")),
              DT::dataTableOutput(ns("sampleDetails"))
            ),
            uiOutput(ns("beforebatchtable"))
          ),
          de_card(
            title = "Options",
            # B3.31 -- Mirror the Filter card pattern: form on top,
            # next-step CTAs INSIDE the same card stacked under Submit.
            div(
              class = "de-batch-card-content",
              div(
                class = "de-batch-form",
                normalizationMethods(id),
                batchMethod(id),
                uiOutput(ns("batchfields")),
                actionButtonDE(ns("submitBatchEffect"), label = "Submit", styleclass = "primary")
              ),
              conditionalPanel(
                condition = paste0("input['", ns("submitBatchEffect"), "']"),
                div(
                  class = "de-batch-cta-stack",
                  actionButtonDE("goDE", "Go to DE Analysis", styleclass = "primary"),
                  actionButtonDE("goQCplots", "Go to QC plots", styleclass = "primary")
                )
              )
            )
          ),
          tagList(
            div(
              style = "overflow: scroll",
              tableOutput(ns("filteredSummary")),
              DT::dataTableOutput(ns("filteredDetails"))
            ),
            uiOutput(ns("afterbatchtable"))
          )
        )
      ),
      bslib::card(
        bslib::card_header("Plots"),
        fluidRow(
          column(1, div()),
          tabsetPanel(
            id = ns("batchTabs"),
            tabPanel(
              id = ns("PCA"), "PCA",
              column(
                5,
                getPCAPlotUI(ns("beforeCorrectionPCA"))
              ),
              column(
                2,
                de_card(
                  title = "PCA Controls",
                  tabsetPanel(
                    id = ns("pcacontrols"),
                    tabPanel(
                      "Before",
                      pcaPlotControlsUI(ns("beforeCorrectionPCA"))
                    ),
                    tabPanel(
                      "After",
                      pcaPlotControlsUI(ns("afterCorrectionPCA"))
                    )
                  )
                )
              ),
              column(
                5,
                getPCAPlotUI(ns("afterCorrectionPCA"))
              )
            ),
            tabPanel(
              id = ns("IQR"), "IQR",
              column(
                5,
                getIQRPlotUI(ns("beforeCorrectionIQR"))
              ),
              column(2, div()),
              column(
                5,
                getIQRPlotUI(ns("afterCorrectionIQR"))
              )
            ),
            tabPanel(
              id = ns("Density"), "Density",
              column(
                5,
                getDensityPlotUI(ns("beforeCorrectionDensity"))
              ),
              column(2, div()),
              column(
                5,
                getDensityPlotUI(ns("afterCorrectionDensity"))
              )
            )
          )
        )
      )
    ), getPCAcontolUpdatesJS()
  )
}
#' normalizationMethods
#'
#' Select box to select normalization method prior to batch effect correction
#'
#' @note \code{normalizationMethods}
#' @param id, namespace id
#' @return radio control
#'
#' @examples
#'
#' x <- normalizationMethods("batch")
#'
#' @export
#'
normalizationMethods <- function(id) {
  ns <- NS(id)
  selectInput(ns("norm_method"), "Normalization Method:",
    choices = c("none", "MRN", "TMM", "RLE", "upperquartile")
  )
}

#' batchMethod
#'
#' select batch effect method
#' @param id, namespace id
#' @note \code{batchMethod}
#' @return radio control
#'
#' @examples
#'
#' x <- batchMethod("batch")
#'
#' @export
#'
batchMethod <- function(id) {
  ns <- NS(id)
  selectInput(ns("batchmethod"), "Correction Method:",
    choices = c("none", "Combat", "CombatSeq", "Harman"),
    selected = "none"
  )
}

#' Correct Batch Effect using Combat in sva package
#'
#' Batch effect correction
#' @param input, input values
#' @param idata, data
#' @param metadata, metadata
#' @param method, method: either Combat or CombatSeq
#' @return data
#' @export
#'
#' @examples
#' x <- correctCombat()
correctCombat <- function(input = NULL, idata = NULL, metadata = NULL,
                          method = NULL) {
  if (is.null(idata)) {
    return(NULL)
  }
  if (input$batch == "None") {
    de_notify_error(
      "ComBat needs a batch field. Pick one in the Batch dropdown above before applying."
    )
    return(NULL)
  }
  treatment_col <- if (!is.null(input$treatment) && input$treatment != "None") {
    input$treatment
  } else {
    NULL
  }
  # B3.32 -- sva::ComBat / ComBat_seq throws on confounded covariates,
  # singular models, etc. Catch and surface as a friendly notification
  # instead of letting the observer die and the page freeze.
  tryCatch(
    apply_batch_correction(idata, metadata,
      method = method,
      batch_col = input$batch, treatment_col = treatment_col
    ),
    error = function(e) {
      de_notify_error(paste0(
        "Batch correction (", method, ") could not run: ",
        conditionMessage(e),
        " -- try a different batch column, drop confounded covariates, ",
        "or pick a different correction method."
      ))
      NULL
    }
  )
}

#' Correct Batch Effect using Harman
#'
#' Batch effect correction
#' @param input, input values
#' @param idata, data
#' @param metadata, metadata
#' @return data
#' @export
#'
#' @examples
#' x <- correctHarman()
correctHarman <- function(input = NULL, idata = NULL, metadata = NULL) {
  if (is.null(idata)) {
    return(NULL)
  }
  if (input$treatment == "None" || input$batch == "None") {
    de_notify_error(
      "Harman needs both a batch and a treatment field. Pick one for each in the dropdowns above."
    )
    return(NULL)
  }
  # B3.32 -- Harman::harman throws on bad batch/treatment configurations
  # (e.g. only one batch level, or batch perfectly confounds treatment).
  # Catch and surface as a friendly notification instead of crashing.
  tryCatch(
    apply_batch_correction(idata, metadata,
      method = "Harman",
      batch_col = input$batch, treatment_col = input$treatment
    ),
    error = function(e) {
      de_notify_error(paste0(
        "Harman correction could not run: ",
        conditionMessage(e),
        " -- verify your batch and treatment fields are valid (more than ",
        "one level, not perfectly confounded), then try again."
      ))
      NULL
    }
  )
}
