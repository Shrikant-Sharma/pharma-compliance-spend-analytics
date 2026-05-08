# Pharma Compliance Spend Analytics

> End-to-end compliance spend analytics on real CMS Open Payments data — anomaly detection, tiered risk classifier, and an interactive Tableau dashboard surfacing the relationships that compliance teams actually need to investigate.

[![Python](https://img.shields.io/badge/Python-3.10%2B-blue.svg)](https://www.python.org)
[![Pandas](https://img.shields.io/badge/Pandas-2.0%2B-150458.svg)](https://pandas.pydata.org)
[![NumPy](https://img.shields.io/badge/NumPy-1.24%2B-013243.svg)](https://numpy.org)
[![SciPy](https://img.shields.io/badge/SciPy-1.10%2B-8CAAE6.svg)](https://scipy.org)
[![Tableau](https://img.shields.io/badge/Tableau-Public-E97627.svg)](https://public.tableau.com/app/profile/shrikant.sharma)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**🔗 [Live Interactive Dashboard on Tableau Public →](https://public.tableau.com/shared/GFWDZJ8WF)**

![Feature distributions](output/feature_distributions.png)

---

## Why This Project

The Sunshine Act requires pharmaceutical and medical-device manufacturers to publicly report every payment to U.S. physicians. The 2024 CMS Open Payments dataset contains **16.16 million records totaling $13.18 billion** — far more than any compliance team can manually review.

This project answers a question compliance teams ask every quarter: *"Of all the physicians who received payments this year, which ones should we investigate first?"*

The system combines two complementary statistical methods with a compliance-specific domain rule to produce a **tiered triage queue** that focuses human review on the highest-risk relationships first — the same triage logic used in production compliance monitoring at major pharma companies, applied here to publicly available federal data.

---

## Pipeline

```
┌─────────────────────────────┐
│ CMS Open Payments 2024 CSV  │
│ 16.16M records, ~6 GB       │
└──────────────┬──────────────┘
               │ chunked read (500K rows × 32)
               │ filter: physicians only
               │ filter: drop null NPI / amount
               │ random 10% sample (seed=42)
               ▼
┌─────────────────────────────┐
│ Sampled transactions        │
│ ~989K rows × 10 columns     │
└──────────────┬──────────────┘
               │ groupby NPI + derived features
               ▼
┌─────────────────────────────┐
│ HCP-level table             │
│ ~289K HCPs × 5 features     │
│ - total_payment_value       │
│ - payment_frequency         │
│ - avg_payment_size          │
│ - n_unique_states           │
│ - top_company_share         │
└──────────────┬──────────────┘
               │ within-specialty z-score (3 features)
               │ global IQR outliers (3 features)
               │ compliance concentration rule
               ▼
┌─────────────────────────────┐
│ Tiered risk classifier      │
│ HIGH / MEDIUM / LOW / NONE  │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│ Tableau Public dashboard    │
│ Geographic + Specialty +    │
│ Company + Trend + Detail    │
└─────────────────────────────┘
```

---

## Key Design Decisions

| Decision | Choice | Why |
|---|---|---|
| **Filter to physicians only** | Drop teaching hospitals & non-physician practitioners | Cleanest analytical unit — every physician has a unique NPI, specialty, and state. Mixing in teaching hospitals (no specialty) would corrupt specialty-level z-scores. |
| **10% random sample** | `frac=0.1`, `random_state=42` | The full 16M-row file doesn't fit comfortably in 16 GB RAM. A random sample preserves distributional shape, which is what z-score and IQR rely on. The same code runs on the full file with one parameter change. |
| **Z-score within specialty** | Group by `Covered_Recipient_Specialty_1`, min 30 HCPs/specialty | Different specialties have wildly different payment baselines. Orthopedic surgeons routinely receive larger device payments than pediatricians; a single global z-score would flag entire specialties rather than unusual individuals. |
| **Both z-score AND IQR** | Compute both, combine in tier logic | The CMS payment distribution is heavily right-skewed (median $21, max $3.2M). Right-skew inflates the standard deviation enough that even genuine outliers fall below z=2 — IQR catches what z-score misses. **Receipt: on `total_payment_value`, IQR flagged 30,223 HCPs that z-score missed.** |
| **Concentration with monetary floor** | `top_company_share > 0.7 AND total_payment_value > $500` | The median `top_company_share` is 1.0 (half of all HCPs received a single payment from a single rep). A naïve concentration flag would alert on 50%+ of physicians. The $500 floor strips out the casual food-and-beverage population and leaves the relationships that actually involve compensation. |
| **Tiered classifier (not binary)** | HIGH / MEDIUM / LOW / NONE based on signal count | A binary "flagged / not flagged" output is unusable when 17% of the population qualifies. Tiering gives the compliance team a triage queue: HIGH first (1.7% — manageable manual review), automated rules for MEDIUM/LOW. |

---

## Results

### Tier breakdown (288,942 HCPs total)

| Tier | Count | % of total | What it represents |
|---|---|---|---|
| **HIGH** | 4,819 | 1.67% | All three signals fire — the actionable manual-review queue |
| **MEDIUM** | 23,423 | 8.11% | High value with concentration, or high value with high frequency |
| **LOW** | 22,772 | 7.88% | Single statistical signal, no concentration |
| **NONE** | 237,928 | 82.34% | Below all thresholds |

### Top HIGH-risk HCPs — the headline finding

The top 10 HIGH-risk physicians by total payment value are **all orthopedic-related specialists**, with **9 of 10 receiving over 99% of their payments from a single device manufacturer**:

| Rank | Specialty | State | Total Paid | Frequency | Top Company | Share |
|---|---|---|---|---|---|---|
| 1 | Adult Reconstructive Orthopedic Surgery | ID | $3,200,055 | 14 | Zimmer Biomet | 100% |
| 2 | Vascular & Interventional Radiology | AZ | $1,813,137 | 13 | Boston Scientific | 100% |
| 3 | Orthopaedic Surgery | NY | $950,342 | 19 | Arthrex | 100% |
| 4 | Orthopaedic Sports Medicine | IL | $808,444 | 10 | Arthrex | 94% |
| 5 | Orthopaedic Surgery | IL | $543,748 | 29 | Stryker | 100% |
| 6 | Orthopaedic Surgery | MN | $442,356 | 11 | Stryker | 100% |
| 7 | Orthopaedic Surgery | GA | $435,248 | 9 | Stryker | 100% |
| 8 | Adult Reconstructive Orthopedic Surgery | NY | $312,872 | 19 | Stryker | 100% |
| 9 | Orthopaedic Surgery | WI | $302,522 | 22 | Stryker | 100% |
| 10 | Orthopaedic Surgery | NY | $265,922 | 18 | Smith+Nephew | 86% |

**Interpretation:** Orthopedic surgeons are the highest-leverage prescribers for joint-replacement and sports-medicine devices. The top 10 list reveals a structural pattern — four manufacturers (Stryker, Arthrex, Zimmer Biomet, Boston Scientific) collectively dominate orthopedic-physician compensation. This is exactly the kind of concentration the Sunshine Act was designed to make visible.

---

## Tech Stack

- **Python 3.10+** — `pandas`, `numpy`, `scipy`, `matplotlib`, `seaborn`
- **Tableau Public** — interactive dashboards
- **Jupyter** — analysis notebook
- **Git** — version control

---

## Repository Structure

```
pharma-compliance-spend-analytics/
├── notebooks/
│   └── 01_data_features.ipynb     # End-to-end pipeline
├── output/
│   ├── hcp_features.csv           # HCP-level features (no flags)
│   ├── hcp_features_with_flags.csv # HCP features + risk tiers (Tableau input)
│   └── feature_distributions.png  # Distribution visualizations
├── data/                          # gitignored — see "How to Run"
├── requirements.txt
├── .gitignore
└── README.md
```

---

## How to Run

### 1. Clone and set up environment

```bash
git clone https://github.com/Shrikant-Sharma/pharma-compliance-spend-analytics.git
cd pharma-compliance-spend-analytics
python -m venv .venv
.venv\Scripts\activate   # Windows
# source .venv/bin/activate  # macOS/Linux
pip install -r requirements.txt
```

### 2. Download the CMS data

The 2024 General Payments file is too large to host on GitHub (~6 GB). Download from CMS:

```
https://download.cms.gov/openpayments/PGYR2024_P06302025_06162025/OP_DTL_GNRL_PGYR2024_P06302025_06162025.csv
```

Save as `data/general_payments_2024.csv`.

### 3. Run the notebook

```bash
jupyter notebook notebooks/01_data_features.ipynb
```

Run all cells. Total runtime: ~3 minutes on a modern laptop.

### 4. Open the Tableau workbook (optional)

The published version is on [Tableau Public](https://public.tableau.com/shared/GFWDZJ8WF). To rebuild locally, use the `output/hcp_features_with_flags.csv` and `output/payments_sampled.csv` (regenerated by the notebook) as data sources in Tableau Desktop.

---

## What I Learned

- **Right-skew breaks z-score.** On `total_payment_value`, z-score within specialty flagged 1.5% of HCPs — *fewer* than the 2.3% expected from a normal distribution. The standard deviation was inflated badly enough by the long tail that even genuine outliers fell below z=2. Switching to IQR caught **30,223 additional HCPs** that z-score missed.
- **Domain rules outperform pure statistics.** A naïve "flag everyone with `top_company_share > 0.7`" rule would have flagged 50%+ of the dataset because the median share is 1.0 (most physicians who receive payments only get them from one rep). Adding a $500 monetary floor to the concentration rule cut the flag rate from 73.7% to 17.7% without losing a single HIGH-tier HCP.
- **Tiered triage matters.** Compliance teams can't review 50,000 flags. They can review ~5,000 HIGH-tier flags. The tier system isn't theoretical polish — it's the difference between a system that gets adopted and one that gets ignored.
- **Specialty-level structure is a finding, not a parameter.** Going in, I expected anomalies to be distributed across specialties. The data revealed that orthopedic surgery is structurally captured by four device manufacturers — a finding that wouldn't have surfaced without specialty-level grouping in the analysis.

---

## Author

**Shrikant Sharma** — Data Scientist with 8+ years across pharma and financial services. Currently building ML models that uncover hidden compliance risk.

- 🔗 [LinkedIn](https://www.linkedin.com/in/shrikant-sharma)
- 🔗 [Tableau Public](https://public.tableau.com/app/profile/shrikant.sharma)
- 🔗 [GitHub](https://github.com/Shrikant-Sharma)