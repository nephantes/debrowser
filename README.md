# DEBrowser

**Interactive differential expression analysis & visualization for count data.**

[![DOI](https://zenodo.org/badge/DOI/10.1186/zenodo.s12864-018-5362-x.svg)](https://doi.org/10.1186/s12864-018-5362-x)
[![Bioconductor](https://img.shields.io/badge/Bioconductor-debrowser-blue.svg)](https://bioconductor.org/packages/debrowser)
[![Documentation](https://img.shields.io/badge/docs-readthedocs-blue.svg)](https://debrowser.readthedocs.io)

DEBrowser turns RNA-Seq differential expression analysis into an interactive,
point-and-click workflow. It wraps three established Bioconductor engines —
**DESeq2**, **edgeR**, and **limma** — in a [Shiny](https://shiny.posit.co)
app, so changing a cutoff, a normalization method, or a comparison re-draws
every plot and table in real time. No code required to explore your results;
full reproducibility exports when you're done.

> **📖 Full user guide:** the complete, screenshot-by-screenshot walkthrough
> lives at **[debrowser.readthedocs.io](https://debrowser.readthedocs.io)**.
> It is hosted outside the package to keep the package itself small.

![DEBrowser opens on the Data Prep wizard](https://raw.githubusercontent.com/UMMS-Biocore/debrowser-docs/master/docs/debrowser_pics2/debrowser-upload.png)

## Highlights

- **Guided six-step wizard** — Quick start → Upload → Filter & normalize →
  Batch effect → Comparison → DE analysis. Each step unlocks the next.
- **Three DE engines** — DESeq2, edgeR, limma, with their key parameters
  exposed in the UI.
- **Interactive Main Plots** — scatter / volcano / MA with Up/Down/NS coloring;
  lasso- or box-select genes to spawn a linked heatmap.
- **Quality control** — all-to-all correlation, PCA, IQR, and density views,
  before and after batch correction.
- **Cross-contrast concordance** — see where two or more comparisons agree.
- **Enrichment** — GO/KEGG over-representation (clusterProfiler) and GSEA
  (fgsea) with a leading-edge and NES-heatmap view.
- **Reproducibility** — export the session as an R script, R Markdown /
  HTML, Jupyter notebook, or a ready-to-paste methods paragraph.
- **Bookmark & share** the full analysis state behind a stable URL.
- **Optional AI interpretation** of gene-set biology (off by default; local
  Ollama supported for privacy).
- **Modern, restrained UI** — a "Clinical Indigo" theme with light/dark modes
  and `1`–`6` / `T` keyboard shortcuts.

## Installation

```r
# From Bioconductor (release)
if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager")
BiocManager::install("debrowser")

library(debrowser)
startDEBrowser()
```

`startDEBrowser()` opens the app in your browser on port `3838` (so bookmark
URLs stay stable across restarts). See
[Operating system dependencies](#operating-system-dependencies) if system
libraries are missing.

> **New to DEBrowser?** Click **Vernia et al.** under *Demos* on the Upload
> step, then **Upload**, to walk the whole pipeline on bundled data.

## Walkthrough

### 1. Load your data

Drop in a count matrix (genes in the first column, one raw-count column per
sample) and, optionally, a metadata table mapping samples to conditions and
batches. DEBrowser accepts `.csv` / `.tsv` / `.txt` / `.csv.gz`. On upload it
shows a summary — samples, genes, conditions — plus a preview and the
sample-design table.

![Upload summary](https://raw.githubusercontent.com/UMMS-Biocore/debrowser-docs/master/docs/debrowser_pics2/debrowser-summary.png)

> DESeq2 needs **un-normalized** counts (it models library size internally).
> Use pre-normalized values only with edgeR or limma.

### 2. Filter & normalize

Trim low-signal features with **Max**, **Mean**, or **CPM** filtering. Row
counts before and after are shown side by side, with per-sample histograms.

![Low-count filtering](https://raw.githubusercontent.com/UMMS-Biocore/debrowser-docs/master/docs/debrowser_pics2/debrowser-filter.png)

### 3. Correct batch effects (optional)

Choose a normalization (MRN, TMM, RLE, upperquartile) and a correction method
(ComBat, ComBat-Seq, Harman). Inline PCA / IQR / Density plots — *Before* vs.
*After* — confirm samples cluster by biology, not batch.

![Batch-effect correction](https://raw.githubusercontent.com/UMMS-Biocore/debrowser-docs/master/docs/debrowser_pics2/debrowser-batch.png)

### 4. Choose comparisons

Define one or more contrasts by assigning samples to each side. Each becomes
its own DE result set you can switch between.

![Comparison selection](https://raw.githubusercontent.com/UMMS-Biocore/debrowser-docs/master/docs/debrowser_pics2/debrowser-comparison.png)

### 5. Run DE and explore

**Start DE** runs the analysis (progress is reported in stages) and opens
**Main Plots**. Genes are colored Up (red), Down (blue), NS (grey) per your
`padj` and log2-fold-change cutoffs; every change is instant.

![Main Plots scatter](https://raw.githubusercontent.com/UMMS-Biocore/debrowser-docs/master/docs/debrowser_pics2/debrowser-main-plots.png)

Switch to the **Volcano** or **MA** view with the same controls; lasso- or
box-select a region to spawn a linked heatmap of just those genes.

![Volcano view](https://raw.githubusercontent.com/UMMS-Biocore/debrowser-docs/master/docs/debrowser_pics2/debrowser-volcano.png)

## Beyond DE

- **QC Plots** — all-to-all correlation, PCA, IQR, density across the dataset.
- **Concordance** — where two or more comparisons agree/disagree.
- **Enrichment** — GO/KEGG (`enrichGO`, `enrichKEGG`, `Disease`,
  `compareCluster`) and GSEA against MSigDB, with a NES heatmap.
- **Tables** — searchable, sortable result tables (All Detected, Up/Down,
  Most varied, Comparison differences) with regex search that applies
  everywhere.

## Reproducibility & sharing

The **Export** menu turns your interactive session into an **R script**,
**R Markdown / HTML**, a **Jupyter notebook**, or a **methods paragraph** for
your manuscript. The **Bookmark** button captures the entire analysis state
behind a stable, shareable URL.

![Bookmark & share dialog](https://raw.githubusercontent.com/UMMS-Biocore/debrowser-docs/master/docs/debrowser_pics2/debrowser-bookmark.png)

## AI interpretation (optional)

DEBrowser can summarize the biology of a GSEA gene set on the Enrichment tab.
It is **off by default** — no network calls until you enable it and configure a
provider (**Anthropic**, **OpenAI**, or local **Ollama**). Per-call privacy
modes control what leaves your machine; API keys are stored in your OS keychain
via `keyring`, never in plaintext.

![AI Settings dialog](https://raw.githubusercontent.com/UMMS-Biocore/debrowser-docs/master/docs/debrowser_pics2/debrowser-ai.png)

Install the AI extras once: `install.packages(c("ellmer", "whisker", "keyring"))`.

## Design system

DEBrowser ships a self-contained visual redesign layer. Contributors editing
the UI should read [`DESIGN.md`](DESIGN.md) (the token vocabulary + editing
rules) and open the live component gallery with `debrowser::de_style_guide()`.
Full rationale: [`docs/design/`](docs/design/).

## Operating system dependencies

- **Fedora / Red Hat / CentOS:** `openssl-devel libxml2-devel libcurl-devel libpng-devel`
- **Ubuntu:** `sudo apt-get install libcurl4-openssl-dev libssl-dev libxml2-dev libudunits2-dev`

## Documentation

- **Full user guide** (illustrated, with worked examples):
  [debrowser.readthedocs.io](https://debrowser.readthedocs.io) — source in the
  [debrowser-docs](https://github.com/UMMS-Biocore/debrowser-docs) repo.
- Quick reference: `vignette("DEBrowser")`, or the
  [Bioconductor page](https://bioconductor.org/packages/debrowser).
- Design system & contributor notes: [`DESIGN.md`](DESIGN.md),
  [`docs/design/`](docs/design/).

## Citation

If you use DEBrowser in your research, please cite:

> Kucukural A, Yukselen O, Ozata DM, Moore MJ, Garber M. **DEBrowser:
> interactive differential expression analysis and visualization tool for count
> data.** *BMC Genomics* 2019, 20:6. doi:
> [10.1186/s12864-018-5362-x](https://doi.org/10.1186/s12864-018-5362-x)

## License

GPL-3 (see [`LICENSE`](LICENSE)).
