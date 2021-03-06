#' 99_utils.R
#' =======================================================
#+ setup, include=FALSE
knitr::opts_chunk$set(eval = FALSE)
#+


# ---- source_utils ----

library(sp)
suppressMessages(library(dplyr))
library(gstat)
library(ggplot2)
library(sf)
library(LAGOSNEgis)
library(LAGOSNE)
library(lwgeom)
library(classInt)
library(tidyr)
library(stringr)
library(cowplot)
library(mapview)
library(macroag)
library(broom)
library(ggsn)

theme_opts <- theme(axis.text = element_blank(),
                    axis.ticks = element_blank(),
                    panel.background = element_blank(),
                    legend.text = element_text(size = 8),
                    legend.title = element_text(size = 10),
                    legend.key.size = unit(0.7, "line"),
                    plot.margin = unit(c(0, -0.13, 0, -0.13), "cm"))
                    # plot.margin = unit(c(0, 0, -2, 0), "cm")) # t, r, b, l

signif_star <- function(x){
  if(!is.na(x)){
    if(x){
      "*"
    }else{
      ""
    }
  }else{
    ""
  }
}

county_sf <- function(){
  county_sf        <- st_as_sf(maps::map("county", fill = TRUE, plot = FALSE))
  county_sf        <- tidyr::separate(county_sf, ID, c("state", "county"), ",")
  county_sf$county <- gsub("\\.", "", gsub(" ", "", county_sf$county))
  county_sf        <- st_make_valid(county_sf)

  county_key <- data.frame(state = tolower(state.name), state_abb = state.abb,
                           stringsAsFactors = FALSE)
  county_sf <- left_join(county_sf, county_key)
  # county_sf <- county_sf[
  #   unlist(lapply(
  #     st_intersects(county_sf, iws),
  #     function(x) length(x) > 0)),]
  county_sf
}

state_sf <- function(){
  state_sf <- st_as_sf(maps::map("state", fill = TRUE, plot = FALSE))
  key <- data.frame(ID = tolower(state.name),
                    ABB = state.abb, stringsAsFactors = FALSE)
  left_join(state_sf, key, by = "ID")
}

get_states <- function(bbox){
  state_sf <- sf::st_as_sf(maps::map("state", fill = TRUE, plot = FALSE))
  key <- data.frame(ID = tolower(state.name),
                    ABB = state.abb, stringsAsFactors = FALSE)
  state_sf <- left_join(state_sf, key, by = "ID")
  bbox <- st_transform(st_as_sfc(bbox), st_crs(state_sf))

  state_sf <- state_sf[unlist(lapply(
    st_intersects(state_sf, bbox),
    function(x) length(x) > 0)),]

  state_sf$ABB
}

# https://gist.github.com/gadenbuie/284671997992aefe295bed34bb53fde6
backstitch <- function(
  infile,
  outfile = NULL,
  output_type = c('both'),
  chunk_header = "# ----"
) {
  requireNamespace('knitr', quietly = TRUE)
  requireNamespace('stringr', quietly = TRUE)
  stopifnot(output_type %in% c('script', 'code', 'both'))

  if (is.null(outfile) && output_type == 'both')
    stop("Please choose output_type of 'script' or 'code' when not outputting to a file.")

  knitr::knit_patterns$set(knitr::all_patterns[['md']])

  x <- readLines(infile)
  if (inherits(infile, 'connection')) close(infile)

  empty_lines <- which(stringr::str_detect(x, "^\\s?+$"))
  last_non_empty_line <- max(setdiff(seq_along(x), empty_lines))
  x <- x[1:last_non_empty_line]

  x_type <- rep('text', length(x))

  # Find YAML section
  yaml_markers <- which(stringr::str_detect(x, "^[-.]{3}\\s*$"))
  if (length(yaml_markers) > 2) {
    message("Input file may have multiple YAML chunks, only considering lines",
            paste(yaml_markers[1:2], collapse='-'), 'as YAML header.')
  }
  if (length(yaml_markers) > 0) {
    i.yaml <- yaml_markers[1]:yaml_markers[2]
    x_type[i.yaml] <- 'yaml'
  }

  # Mark code chunk.begin, chunk.end and regular chunk codelines
  i.chunk.begin <- which(stringr::str_detect(x, knitr::knit_patterns$get('chunk.begin')))
  i.chunk.end   <- which(stringr::str_detect(x, knitr::knit_patterns$get('chunk.end')))
  x_type[i.chunk.end] <- 'chunk.end'
  for (j in i.chunk.begin) {
    j.chunk.end <- min(i.chunk.end[i.chunk.end > j])-1
    x_type[j:j.chunk.end] <- 'chunk'
  }
  x_type[i.chunk.begin] <- 'chunk.begin'

  # Check for inline code
  i.inline <- which(stringr::str_detect(x, knitr::knit_patterns$get('inline.code')))
  i.inline <- intersect(i.inline, which(x_type == 'text'))
  x_type[i.inline] <- 'inline'

  # Check empty lines
  i.empty <- which(stringr::str_detect(x, "^\\s*$"))
  i.empty <- intersect(i.empty, which(x_type == 'text'))
  x_type[i.empty] <- 'empty'

  really_empty <- function(x_type, j, n = -1) {
    if (grepl('(chunk|yaml)', x_type[j + n])) {
      return('empty')
    } else if (n < 0) {
      return(really_empty(x_type, j, 1))
    } else if (x_type[j + n] %in% c('text', 'inline')) {
      return('text')
    } else {
      return(really_empty(x_type, j, n+1))
    }
  }

  for (j in i.empty) {
    x_type[j] <- really_empty(x_type, j)
  }

  # Rewrite lines helper functions
  comment <- function(x) paste("#'", x)
  make_chunk_header <- function(x, chunk_header) {
    stringr::str_replace(stringr::str_replace(x, knitr::knit_patterns$get('chunk.begin'), "\\1"),
                         "^r[, ]?", paste(chunk_header, ""))
  }
  # Rewrite lines
  y <- x
  regex_inline_grouped <- "`r[ ]?#?(([^`]+)\\s*)`"
  i.empty       <- which(x_type == 'empty')
  i.text        <- which(x_type == 'text')
  y[i.chunk.begin] <- make_chunk_header(x[i.chunk.begin], chunk_header)
  y[i.inline]      <- comment(stringr::str_replace_all(x[i.inline], regex_inline_grouped, "{{\\1}}"))
  y[i.text]        <- comment(x[i.text])
  if (length(yaml_markers) > 0) y[i.yaml] <- comment(x[i.yaml])
  y[i.empty]       <- ""
  y[i.chunk.end]   <- ""

  y_code <- y[which(stringr::str_detect(x_type, 'chunk'))]

  if (!is.null(outfile)){
    outfile_name <- stringr::str_replace(outfile, "(.+)\\.R$", "\\1")
    if (output_type == "script") {
      cat(c(y, ""), file = paste0(outfile_name, ".R"), sep = '\n')
    } else if (output_type == "code") {
      cat(c(y_code, ""), file = paste0(outfile_name, ".R"), sep = '\n')
    } else {
      cat(c(y, ""), file = paste0(outfile_name, ".R"), sep = '\n')
      cat(c(y_code, ""), file = paste0(outfile_name, "_code.R"), sep = '\n')
    }
  } else {
    switch(
      output_type,
      'script' = unname(y),
      'code' = unname(y_code)
    )
  }
}
