# Credit Risk Model

A probability-of-default model built on the Home Credit Default Risk data. The data flows
through `raw -> stg -> mart` layers in PostgreSQL, and the models are trained in notebooks.

## Setup

1. Download the CSV files from the
   [Home Credit Default Risk competition on Kaggle](https://www.kaggle.com/c/home-credit-default-risk/data)
   into the `home-credit-default-risk/` folder.
2. Set up the environment:

   ```bash
   cp .env.example .env
   python -m venv venv
   venv/bin/pip install -r requirements.txt
   docker compose up -d
   ```

3. Run the data pipeline:

   ```bash
   venv/bin/python run_pipeline.py
   ```

   Add `--skip-load` to run only the SQL steps when `raw` is already loaded.

4. Run the notebooks in order: `modeling.ipynb`, `model_selection.ipynb`, `final_test.ipynb`.
   `final_test.ipynb` stops if `artifacts/test_result.json` exists, so the test set is used only once.

## Layers

| Schema | Contents |
|---|---|
| `raw` | The CSV files, unchanged |
| `stg` | Cleaning and per-source summaries |
| `mart` | Model feature tables: `mart.features_application`, `mart.features_application_test` |
| `public` | Metadata files: `columns_description`, `sample_submission` |

## Files

| File | Purpose |
|---|---|
| `run_pipeline.py` | Builds the whole data pipeline |
| `load_to_postgres.py` | Loads the CSV files into the database |
| `sql/` | Transformations; run in name order and idempotent |
| `modeling.ipynb` | Baseline models (without the `fe_` features) |
| `model_selection.ipynb` | CV, `organization_type`, hyperparameters, SHAP, calibration, threshold, fairness |
| `final_test.ipynb` | One-time test evaluation and `application_test` predictions |
| `modeling_utils.py` | Shared notebook helpers and business assumptions |
| `artifacts/` | Decisions, test result and charts |
| `data/split_ids.csv` | Train / validation / test assignments |
| `data/submission.csv` | `application_test` predictions (generated, not tracked) |
| `test.ipynb` | Initial data exploration |

## Results

| Metric | Value |
|---|---|
| Test ROC-AUC | 0.7893 (95% CI 0.7825-0.7962) |
| Test Gini | 0.5787 |
| 5-fold CV ROC-AUC | 0.7873 |
| Threshold | PD < 0.22 |
| Test approval rate | 92.0% |
| Default rate among approved | 5.9% (8.1% if everyone is approved) |

The threshold assumes a 15% margin and a 50% loss given default per unit of credit
(`MARGIN`, `LGD`). These values should be replaced with real figures. The data only
contains loans that were approved in the past, so approval rates do not represent the
real application flow.

The test set has been used. If the model changes, an unbiased evaluation needs new data.
