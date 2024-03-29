#' Import analyst files
#'
#' Create a historical file that will be referenced next quarter to create templates for analysts.
#'
#' @param files A list of file paths
#'
#' @return An Excel file with
#'
#' @author Lillian Nguyen
#' @author Sara Brumfield
#'
#' @import dplyr
#' @importFrom purrr map set_names
#' @export

import_analyst_files <- function(files) {

  files %>%
    map(import, which = "Projections by Spend Category", guess_max = 2000) %>%
    set_names(files) %>%
    map(select, Agency:`Spend Category`,
        matches("^Q[1-4]{1} Calculation$|^Q[1-4]{1} Manual Formula$|^Q[1-4]{1} Projection$|^Q[1-4]{1} Surplus/Deficit$|^Q[1-4]{1} Actuals|^FY[0-9]{2} Actual|^FY[0-9]{2} Adopted"),
        `YTD Actuals`, !!paste0("FY", params$fy, " Budget"), Notes) %>%
    # changing data types here, before bind_rows()
    #bring in prior FY actuals
    map(mutate_at, vars(matches(".*Calculation|.*Manual Formula")), as.character) %>%
    map(mutate_at, vars(matches(".*Projection|.*Budget|.*Surplus|.*Actuals")), as.numeric)
}


#' Export analyst calculations
#'
#' Create a historical file that will be referenced next quarter to create templates for analysts.
#'
#' @param df
#'
#' @return An Excel file with
#'
#' @author Lillian Nguyen
#'
#' @import dplyr
#' @export

export_analyst_calcs <- function(df) {

  check <- compiled %>%
    group_by(`Service ID`, `Activity ID`, `Fund ID`, `Subobject ID`) %>%
    count() %>%
    filter(n > 1)

  if (nrow(check) > 0) {
    warning("There are ", nrow(check), " duplicated line item calculations")
  }


  # keep all Name columns just for easy troubleshooting; they aren't needed to create the templates

  df %>%
    select(-File) %>%
    # keep all funds in this file to bring analyst calcs for every line item forward...
    write.csv(paste0("quarterly_outputs/FY", params$fy, " Q", params$qt, " Analyst Calcs.csv"))
}

#' Export analyst calculations with Workday values
#'
#' Create a historical file that will be referenced next quarter to create templates for analysts.
#'
#' @param df
#'
#' @return An Excel file with current analyst calcs
#'
#' @author Sara Brumfield
#'
#' @import dplyr
#' @export

export_analyst_calcs_workday <- function(df) {
  
  check <- df %>%
    group_by(Agency, Service, `Cost Center`, Fund, Grant, 
             `Special Purpose`, `Spend Category`) %>%
    count() %>%
    filter(n > 1)
  
  if (nrow(check) > 0) {
    warning("There are ", nrow(check), " duplicated line item calculations")
    export_excel(check, "Duplicate", "quarterly_outputs/Duplicate Calcs.xlsx")
  } else {warning("No duplicate caculations found.")}
  
  cc_check <- df %>%
    select(Agency, Service, `Cost Center`)%>%
    distinct() %>%
    group_by(Agency, Service, `Cost Center`) %>%
    count() %>%
    filter(n > 1)
  
  if (nrow(cc_check) > 0) {
    warning("There are ", nrow(cc_check), " duplicated cost centers")
    export_excel(cc_check, "Duplicate CCs", "quarterly_outputs/Duplicate CC Calcs.xlsx")
  }
  
  
  # keep all Name columns just for easy troubleshooting; they aren't needed to create the templates
  
  df %>%
    select(-File) %>%
    # keep all funds in this file to bring analyst calcs for every line item forward...
    write.csv(paste0("quarterly_outputs/FY", params$fy, " Q", params$qt, " Analyst Calcs.csv"))
}


#' Run summary reports
#'
#' @param df
#'
#' @return An Excel file with citywide projections, and summary "Pivot" tabs by Object, Subobject, and Agency
#'
#' @author Lillian Nguyen
#'
#' @import dplyr
#' @importFrom bbmR export_excel
#' @export

run_summary_reports <- function(df) {

  # params:
  #   - df: a dataframe containing all cleaned analyst projections

  reports <- list(
    object = df %>%
      group_by(`Agency ID`, `Agency Name`, `Service ID`, `Service Name`,
               `Object ID`, `Object Name`),
    subobject = df %>%
      group_by(`Agency ID`, `Agency Name`, `Service ID`, `Service Name`,
               `Object ID`, `Object Name`,
               `Subobject ID`, `Subobject Name`),
    pillar = df %>%
      group_by(`Agency ID`, `Agency Name`, `Service ID`, `Service Name`,
               `Pillar ID`, `Pillar Name`),
    agency = df %>%
      group_by(`Agency Name`)) %>%
    map(summarize_at,
        vars(matches("Q.*Projection|Total Budget|Q.*Surplus|Q.*Diff")),
        sum, na.rm = TRUE) %>%
    map(filter, !is.na(`Agency Name`))

  # Add 'significant difference' col for easy spotting of errors
  reports$subobject <- reports$subobject %>%
    mutate(`Signif Diff` = ifelse(
      (!!sym(cols$proj) / `Total Budget` <= .8 | !!sym(cols$proj) / `Total Budget` >= 1.2) &
        `Total Budget` - !!sym(cols$proj) > 20000, TRUE, FALSE))

  reports$agency <- reports$agency %>%
    select(`Agency Name`, `Total Budget`,
           starts_with("Q1"), starts_with("Q2"), starts_with("Q3")) %>%
    mutate_all(replace_na, 0)

  export_excel(df, "Compiled", internal$output, "new",
               col_width = rep(15, ncol(compiled)))
  export_excel(reports$object, "Object", internal$output, "existing",
               col_width = rep(15, ncol(reports$object)))
  export_excel(reports$subobject, "Subobject", internal$output, "existing",
               col_width = rep(15, ncol(reports$subobject)))
  export_excel(reports$pillar, "Pillar", internal$output, "existing",
               col_width = rep(15, ncol(reports$pillar)))
  export_excel(reports$agency, "Agency", internal$output, "existing")

}

#' Run summary reports for Workday vlaues
#'
#' @param df
#'
#' @return An Excel file with citywide projections, and summary "Pivot" tabs by Cost Center, Spend Category
#'
#' @author Sara Brumfield
#'
#' @import dplyr
#' @importFrom bbmR export_excel
#' @export

run_summary_reports_workday <- function(df) {
  
  # params:
  #   - df: a dataframe containing all cleaned analyst projections
  
  reports <- list(
    spend_category = df %>%
      group_by(Agency, Service, `Spend Category`),
    cost_center = df %>%
      group_by(Agency, Service, `Cost Center`),
    fund = df %>%
      group_by(Agency, Service, Fund),
    grant = df %>%
      group_by(Agency, Service, Grant) %>% filter(!is.na(Grant)),
    special = df %>%
      group_by(Agency, Service, `Special Purpose`) %>% filter(!is.na(`Special Purpose`)),
    agency = df %>%
      group_by(`Agency`)) %>%
    map(summarize_at,
        vars(matches("Q.*Projection|* Budget|Q.*Actuals|Q.*Surplus|Q.*Diff")),
        sum, na.rm = TRUE) %>%
    map(filter, !is.na(`Agency`))
  
  # Add 'significant difference' col for easy spotting of errors
  reports$spend_category <- reports$spend_category %>%
    mutate(`Signif Diff` = ifelse(
      (!!sym(cols$proj) / !!sym(cols$budget) <= .8 | !!sym(cols$proj) / !!sym(cols$budget) >= 1.2) &
        !!sym(cols$budget) - !!sym(cols$proj) > 20000, TRUE, FALSE))
  
  reports$agency <- reports$agency %>%
    select(`Agency`, !!sym(cols$budget),
           starts_with("Q1"), starts_with("Q2"), starts_with("Q3")) %>%
    mutate_if(is_numeric, replace_na, 0) %>%
    mutate(`Signif Diff` = ifelse(
      (!!sym(cols$proj) / !!sym(cols$budget) <= .8 | !!sym(cols$proj) / !!sym(cols$budget) >= 1.2) &
        !!sym(cols$budget) - !!sym(cols$proj) > 20000, TRUE, FALSE))
  
  export_excel(df, "Compiled", internal$output, "new",
               col_width = rep(15, ncol(df)))
  export_excel(reports$spend_category, "Spend Category", internal$output, "existing",
               col_width = rep(15, ncol(reports$spend_category)))
  export_excel(reports$cost_center, "Cost Center", internal$output, "existing",
               col_width = rep(15, ncol(reports$cost_center)))
  export_excel(reports$fund, "Fund", internal$output, "existing",
               col_width = rep(15, ncol(reports$fund)))
  export_excel(reports$grant, "Grant", internal$output, "existing",
               col_width = rep(15, ncol(reports$grant)))
  export_excel(reports$special, "Special Purpose", internal$output, "existing",
               col_width = rep(15, ncol(reports$special)))
  export_excel(reports$agency, "Agency", internal$output, "existing")
  
}

#' Import Workday file
#'
#' Data transformation for Workday Budget vs Actuals - BBMR report from Workday
#'
#' @param file path
#' @param fund vector of funds
#'
#' @return An Excel file with
#'
#' @author Sara Brumfield
#'
#' @import dplyr
#' @export


import_workday <- function(file_name = file_name, fund = c("1001 General Fund")) {
  input <- import(paste0("inputs/", file_name), skip = 9) %>%
    filter(Fund %in% fund_list) %>%
    select(-`...10`, -`Total Spent`) %>%
    mutate(`Workday Agency ID` = str_extract(Agency, pattern = "(AGC\\d{4})"),
           `Fund ID`= as.numeric(substr(Fund, 1, 4))) %>%
    ##manually adjust columns by date for now
    rename(`Jul Actuals` = `Actuals...13`,
           `Aug Actuals` =  `Actuals...16`,
           `Sep Actuals` =  `Actuals...19`,
           `Jul Obligations` = `Obligations...14`,
           `Aug Obligations` =  `Obligations...17`,
           `Sep Obligations` =  `Obligations...20`) %>%
    mutate(
      `Q1 Actuals` = as.numeric(`Jul Actuals`) + as.numeric(`Aug Actuals`) + as.numeric(`Sep Actuals`),
      `Q1 Obligations` = as.numeric(`Jul Obligations`) + as.numeric(`Aug Obligations`) + as.numeric(`Sep Obligations`),
      `YTD Actuals + Obligations` = `Q1 Actuals` + `Q1 Obligations`,
      `YTD Actuals` = `Q1 Actuals`,
      `YTD Obligations` = `Q1 Obligations`,
      `Special Purpose ID` = substr(`Special Purpose`, 1, 9))
  
  if (params$qtr == 2) {
    input <- input %>%
      rename(`Oct Actuals` = `Actuals...22`,
               `Nov Actuals` = `Actuals...25`,
               `Dec Actuals` =  `Actuals...28`,
             `Oct Obligations` = `Obligations...23`,
             `Nov Obligations` = `Obligations...26`,
             `Dec Obligations` =  `Obligations...29`) %>%
      mutate(`Q2 Actuals` = as.numeric(`Oct Actuals`) + as.numeric(`Nov Actuals`) + as.numeric(`Dec Actuals`),
             `Q2 Obligations` = as.numeric(`Oct Obligations`) + as.numeric(`Nov Obligations`) + as.numeric(`Dec Obligations`),
             `YTD Actuals + Obligations` = `Q1 Actuals` + `Q1 Obligations` + `Q2 Actuals` + `Q2 Obligations`,
             `YTD Actuals` = `Q1 Actuals` + `Q2 Actuals`,
             `YTD Obligations` = `Q1 Obligations` + `Q2 Obligations`)
        
  } else if (params$qtr == 3) {
    input <- input %>%
      rename(`Oct Actuals` = `Actuals...22`,
             `Nov Actuals` = `Actuals...25`,
             `Dec Actuals` =  `Actuals...28`,
             `Oct Obligations` = `Obligations...23`,
             `Nov Obligations` = `Obligations...26`,
             `Dec Obligations` =  `Obligations...29`,
             `Jan Actuals` = `Actuals...31`,
             `Feb Actuals` =  `Actuals...34`,
             `Mar Actuals` =  `Actuals...37`,
             `Jan Obligations` = `Obligations...32`,
             `Feb Obligations` =  `Obligations...35`,
             `Mar Obligations` =  `Obligations...38`) %>%
      mutate(`Q2 Actuals` = as.numeric(`Oct Actuals`) + as.numeric(`Nov Actuals`) + as.numeric(`Dec Actuals`),
             `Q2 Obligations` = as.numeric(`Oct Obligations`) + as.numeric(`Nov Obligations`) + as.numeric(`Dec Obligations`),
             `Q3 Actuals` = as.numeric(`Jan Actuals`) + as.numeric(`Feb Actuals`) + as.numeric(`Mar Actuals`),
             `Q3 Obligations` = as.numeric(`Jan Obligations`) + as.numeric(`Feb Obligations`) + as.numeric(`Mar Obligations`),
             `YTD Actuals + Obligations` = `Q1 Actuals` + `Q1 Obligations` + `Q2 Actuals` + `Q2 Obligations` + `Q3 Actuals` + `Q3 Obligations`,
             `YTD Actuals` = `Q1 Actuals` + `Q2 Actuals` + `Q3 Actuals`,
             `YTD Obligations` = `Q1 Obligations` + `Q2 Obligations` + `Q3 Obligations`)
  }
      
  inputs <- input %>%
    select(-matches("(\\...)")) %>%
    relocate(`Q1 Actuals`, .after = `YTD Actuals + Obligations`) %>%
    relocate(`Q1 Obligations`, .after = `Q1 Actuals`)
  
  if (params$qtr == 2) {
    input <- input %>%
      relocate(`Q2 Actuals`, .after = `Q1 Obligations`) %>%
      relocate(`Q2 Obligations`, .after = `Q2 Actuals`) 
  } else if (params$qtr == 3) {
    input <- input %>%
      relocate(`Q2 Actuals`, .after = `Q1 Obligations`) %>%
      relocate(`Q2 Obligations`, .after = `Q2 Actuals`) %>%
      relocate(`Q3 Actuals`, .after = `Q2 Obligations`) %>%
      relocate(`Q3 Obligations`, .after = `Q3 Actuals`)
  }
    input <- input %>%
    relocate(`YTD Actuals`, .after = `YTD Actuals + Obligations`) %>%
      relocate(`Workday Agency ID`, .before = `Agency`) %>%
      relocate(`Special Purpose ID`, .before = `Special Purpose`) %>%
    select(-starts_with("Obligations"), -starts_with("Commitments"), -starts_with("Actuals"))
  
  return(input)
}


#' Export Workday file
#'
#' Takes a subset of data by agency id and exports projection Excel files for each agency, distributes to Agency file path on G-drive
#'
#' @param list of dataframes, agency id
#'
#' @return An Excel file for each agency
#'
#' @author Sara Brumfield
#'
#' @import dplyr
#' @export

export_workday <- function(agency_id, list) {
  agency_id <- as.character(agency_id)
  agency_name <- analysts$`Agency Name - Cleaned`[analysts$`Workday Agency ID`==agency_id]
  file_path <- paste0(
    "G:/Agencies/", agency_name, "/File Distribution/FY", params$fy, " Q", params$qtr, " - ", agency_name, ".xlsx")
  data <- list[[agency_id]]$line.item %>%
    apply_formula_class(c(cols$proj, cols$surdef)) 
  
  style <- list(cell.bg = createStyle(fgFill = "lightgreen", border = "TopBottomLeftRight",
                                      borderColour = "black", textDecoration = "bold",
                                      wrapText = TRUE),
                formula.num = createStyle(numFmt = "#,##0"),
                negative = createStyle(fontColour = "#9C0006"))
  
  style$rows <- 2:nrow(data)
  
  wb<- createWorkbook()
  addWorksheet(wb, "Projections by Spend Category")
  addWorksheet(wb, "Calcs", visible = FALSE)
  writeDataTable(wb, 1, x = data)
  writeDataTable(wb, 2, x = calc.list)
  
  dataValidation(
    wb = wb,
    sheet = 1,
    rows = 2:nrow(data),
    type = "list",
    value = "Calcs!$A$2:$A$8",
    cols = grep(cols$calc, names(data)))
  
  conditionalFormatting(
    wb, 1, rows = style$rows, style = style$negative,
    type = "expression", rule = "<0",
    cols = grep(paste0(c(cols$calc, "Projection", "Surplus/Deficit"),
                       collapse = "|"), names(data)))
  
  addStyle(wb, 1, style$cell.bg, rows = 1,
           gridExpand = TRUE, stack = FALSE,
           cols = grep(paste0(c(cols$calc, "Projection", "Surplus/Deficit"),
                              collapse = "|"), names(data)))
  
  addStyle(wb, 1, style$formula.num, rows = style$rows,
           gridExpand = TRUE, stack = FALSE,
           cols = grep(paste0(c(cols$calc, "Projection", "Surplus/Deficit"),
                              collapse = "|"), names(data)))
  
  writeComment(
    excel, sheet = 1, col = "YTD Actuals", row = 1,
    createComment(
      paste("Includes values posted in June assigned to FY23."),
      visible = FALSE, width = 3, height = 6))
  
  writeComment(
    excel, sheet = 1, col = "Q1 Actuals", row = 1,
    createComment(
      paste("Includes values posted in June assigned to FY23."),
      visible = FALSE, width = 3, height = 6))
  
  saveWorkbook(wb, file_path, overwrite = TRUE)
  
  message(agency_name, " projections tab exported.")
}

