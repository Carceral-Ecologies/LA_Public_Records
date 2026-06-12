# ============================================================
# Exoloring LAPD public-records requests 
# ============================================================

## ---- Packages ----------------------------------------------------------
# install.packages(c("readr","dplyr","tidyr","stringr","lubridate","ggplot2","scales"))
library(readr); library(dplyr); library(tidyr); library(stringr)
library(lubridate); library(ggplot2); library(scales)

# Parsing the "hh:mm:ss AM/PM" timestamps needs an English/C time locale.
# (On some Windows installs use "English" instead of "C".)
suppressWarnings(try(Sys.setlocale("LC_TIME", "C"), silent = TRUE))

CSV <- "~/Downloads/requests-2026-06-11_All_Open_Closed.csv"

## ---- Load, clean, derive fields ---------------------------------------
raw <- read_csv(CSV, col_types = cols(.default = col_character()))

dat <- raw %>%
  rename(id = Id, created_at = `Created At`, request_text = `Request Text`,
         poc = `Point of Contact`, embargo_raw = `Embargo Ends On Date`,
         closed_at = `Closed Date`, closure = `Closure Reasons`, url = URL) %>%
  mutate(
    # collapse internal whitespace, trim, blank -> NA
    across(c(poc, closure, request_text), ~ na_if(str_squish(.x), "")),
    created = as.POSIXct(created_at, format = "%m/%d/%Y %I:%M:%S %p", tz = "UTC"),
    closed  = as.POSIXct(closed_at,  format = "%m/%d/%Y %I:%M:%S %p", tz = "UTC"),
    is_closed = !is.na(closed),

    # ID parts: prefix is the filing year, number is a shared sequential counter
    idyr  = 2000L + as.integer(sub("-.*$", "", id)),
    idnum = as.integer(sub("^[^-]+-", "", id)),

    # Department from the closure-reason prefix, then consolidate everything
    # police-related (PD / LAPD / 1421 prefixes, or an LAPD-labelled analyst) into "LAPD"
    dept_raw = if_else(is.na(closure), "Unknown",
                       toupper(str_extract(str_remove(closure, "^[*\\s]+"), "^[A-Za-z0-9]+"))),
    poc_lapd = if_else(is.na(poc), FALSE,
                       str_detect(poc, regex("LAPD", ignore_case = TRUE))),
    dept = if_else(poc_lapd | dept_raw %in% c("PD", "LAPD", "1421"), "LAPD", dept_raw),

    # LAPD closure-outcome bucket (priority order: first match wins)
    cl = str_to_lower(closure),
    LO = case_when(
      is.na(closure)                                                                 ~ "Still open",
      str_detect(cl, "closed - other|closed, other")                                 ~ "Closed-Other",
      str_detect(cl, "duplicate")                                                    ~ "Duplicate",
      str_detect(cl, "fail.*respond|clarification|no payment|missing info|withdraw|abandon") ~ "Withdrawn",
      str_detect(cl, "denial|denied|exempt|hipaa|jurisdiction")                      ~ "Denied/Exempt",
      str_detect(cl, "no responsive|no record|no document|does not have|no results") ~ "No records",
      str_detect(cl, "provid|fulfill|complete|released|summary")                     ~ "Records released",
      TRUE                                                                           ~ "Other/uncoded"
    )
  )

## ---- Shared theme & palettes ------------------------------------------
theme_lapd <- theme_minimal(base_size = 12) +
  theme(plot.title         = element_text(face = "bold"),
        plot.title.position = "plot",
        panel.grid.minor   = element_blank(),
        panel.grid.major.x = element_blank(),
        legend.title       = element_blank())

# outcome categories ordered bottom -> top of the stack
outcome_levels <- c("Records released","No records","Denied/Exempt",
                    "Other/uncoded","Withdrawn","Duplicate","Closed-Other")
outcome_cols <- c("Records released"="#2e7d4f","No records"="#7fc6a0",
                  "Denied/Exempt"="#e0a458","Other/uncoded"="#c9cdd6",
                  "Withdrawn"="#b0b7c3","Duplicate"="#8a94a6","Closed-Other"="#9b1c1c")

CUT <- as.Date("2025-04-01")   # neutral reference date (delete geom_vline lines to remove)

# ============================================================
# 1. Monthly posted requests, 2024-2026 : LAPD vs other depts
# ============================================================
m1 <- dat %>%
  filter(!is.na(created), created >= as.POSIXct("2024-01-01", tz = "UTC")) %>%
  mutate(month = floor_date(as.Date(created), "month"),
         grp   = if_else(dept == "LAPD", "LAPD", "Other depts")) %>%
  count(month, grp) %>%
  complete(month, grp, fill = list(n = 0)) %>%
  # first level sits at the BOTTOM with position_stack(reverse = TRUE):
  mutate(grp = factor(grp, levels = c("Other depts", "LAPD")))

p1 <- ggplot(m1, aes(month, n, fill = grp)) +
  geom_area(position = position_stack(reverse = TRUE), alpha = 0.9) +
  geom_vline(xintercept = CUT, linetype = "dashed", colour = "grey30") +
  scale_fill_manual(values = c("Other depts" = "#3f7e99", "LAPD" = "#9b1c1c")) +
  scale_x_date(date_breaks = "3 months", date_labels = "%b %Y", expand = c(0, 0)) +
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0, .05))) +
  labs(title = "Monthly posted requests, 2024-2026",
       x = "month", y = "publicly-posted requests / month") +
  theme_lapd + theme(axis.text.x = element_text(angle = 45, hjust = 1))

print(p1)
ggsave("lapd_1_monthly_lapd_vs_other.png", p1, width = 8.5, height = 5.5, dpi = 140, bg = "white")

# ============================================================
# 2. Where LAPD requests end up : outcome mix by year 
# ============================================================
oc <- dat %>%
  filter(dept == "LAPD", is_closed, !is.na(created)) %>%
  mutate(yr = year(created)) %>%
  filter(yr %in% 2018:2026) %>%
  count(yr, LO) %>%
  group_by(yr) %>%
  mutate(pct = n / sum(n) * 100, ntot = sum(n)) %>%
  ungroup() %>%
  mutate(LO = factor(LO, levels = outcome_levels))

# in-bar % labels for the three main bands; segment midpoints measured from the bottom
seg_pos <- oc %>%
  arrange(yr, LO) %>%
  group_by(yr) %>%
  mutate(ypos = cumsum(pct) - pct / 2) %>%
  ungroup() %>%
  filter(LO %in% c("Records released", "Denied/Exempt", "Closed-Other"), pct >= 7)

# per-bar request counts above each column
n_pos <- oc %>%
  distinct(yr, ntot) %>%
  mutate(lbl = paste0("n=", format(ntot, big.mark = ","),
                      ifelse(yr >= 2025, "\n(partial)", "")))

p2 <- ggplot(oc, aes(factor(yr), pct, fill = LO)) +
  geom_col(position = position_stack(reverse = TRUE),
           width = 0.78, colour = "white", linewidth = 0.3) +
  geom_text(data = seg_pos, aes(factor(yr), ypos, label = sprintf("%.0f%%", pct)),
            colour = "white", fontface = "bold", size = 3) +
  geom_text(data = n_pos, aes(factor(yr), 101, label = lbl), inherit.aes = FALSE,
            vjust = 0, size = 2.8, colour = "grey35", lineheight = 0.9) +
  scale_fill_manual(values = outcome_cols, guide = guide_legend(reverse = TRUE)) +
  scale_y_continuous(limits = c(0, 109), breaks = seq(0, 100, 20),
                     expand = expansion(mult = c(0, 0))) +
  labs(title = "Where LAPD requests end up\n(outcome mix by year)",
       x = "year request was filed", y = "% of closed LAPD requests") +
  theme_lapd + theme(axis.text.x = element_text(angle = 45, hjust = 1))

print(p2)
ggsave("lapd_2_outcome_mix_by_year.png", p2, width = 9, height = 6.5, dpi = 140, bg = "white")

# ============================================================
# 3. LAPD requests filed per month (volume over time)
# ============================================================
m3 <- dat %>%
  filter(dept == "LAPD", !is.na(created)) %>%
  mutate(month = floor_date(as.Date(created), "month")) %>%
  count(month)

p3 <- ggplot(m3, aes(month, n)) +
  geom_area(fill = "#2f6f8f", alpha = 0.9) +
  geom_vline(xintercept = CUT, linetype = "dashed", colour = "grey30") +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y", expand = c(0, 0)) +
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0, .05))) +
  labs(title = "LAPD requests visible in the public portal per month\n(volume over time)",
       x = "month", y = "requests / month") +
  theme_lapd

print(p3)
ggsave("lapd_3_monthly_volume.png", p3, width = 8.5, height = 5, dpi = 140, bg = "white")

# ============================================================
# 4. Public vs. withheld : share of requests that appear publicly, by year
# ============================================================
seg_other <- "Posted publicly (other depts)"
seg_lapd  <- "Posted publicly (LAPD)"
seg_wh    <- "Not in public portal\n(drafts/withdrawn/spam + withheld)"

# For each filing year: published (LAPD vs other) and the portion of the ID
# sequence that never appears publicly (max ID reached minus rows published).
P <- dat %>%
  filter(idyr %in% 2018:2026) %>%
  group_by(idyr) %>%
  summarise(pub_lapd  = sum(dept == "LAPD"),
            published = n(),
            initiated = max(idnum, na.rm = TRUE), .groups = "drop") %>%
  mutate(pub_other = published - pub_lapd,
         withheld  = pmax(initiated - published, 0),
         pub_rate  = published / initiated * 100)

pw_long <- bind_rows(
  P %>% transmute(year = idyr, seg = seg_other, val = pub_other),
  P %>% transmute(year = idyr, seg = seg_lapd,  val = pub_lapd),
  P %>% transmute(year = idyr, seg = seg_wh,    val = withheld)
) %>%
  mutate(seg = factor(seg, levels = c(seg_other, seg_lapd, seg_wh)))  # other bottom -> withheld top

rate_lab <- P %>% transmute(year = idyr, initiated, lbl = paste0(round(pub_rate), "% public"))

p4 <- ggplot(pw_long, aes(factor(year), val, fill = seg)) +
  geom_col(position = position_stack(reverse = TRUE),
           width = 0.8, colour = "white", linewidth = 0.3) +
  geom_text(data = rate_lab, aes(factor(year), initiated, label = lbl), inherit.aes = FALSE,
            vjust = -0.4, size = 3, colour = "grey25") +
  scale_fill_manual(values = setNames(c("#3f7e99", "#9b1c1c", "#cbd0d8"),
                                      c(seg_other, seg_lapd, seg_wh))) +
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0, .12))) +
  labs(title = "Public vs. withheld: share of requests that actually\nappear in the public portal, by year",
       x = "year", y = "requests initiated in the portal (by ID)",
       caption = paste0("Note: ~30% of IDs are always absent from public view (drafts, withdrawn, spam); ",
                        "the jump in 2025-26 is timed to April and specific to LAPD.")) +
  theme_lapd +
  theme(axis.text.x      = element_text(angle = 45, hjust = 1),
        legend.position  = "top",
        plot.caption     = element_text(colour = "grey45", hjust = 0))

print(p4)
ggsave("lapd_4_public_vs_withheld.png", p4, width = 9.5, height = 6, dpi = 140, bg = "white")

#ya done!
