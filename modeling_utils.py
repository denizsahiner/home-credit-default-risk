"""Shared helpers for model_selection.ipynb and final_test.ipynb."""

import os
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd
import psycopg2
from dotenv import load_dotenv
from sklearn.metrics import average_precision_score, brier_score_loss, log_loss, roc_auc_score
from sklearn.model_selection import StratifiedKFold
from sqlalchemy import create_engine

SEED = 42
ID, TARGET = "sk_id_curr", "target"
ROOT = Path(__file__).parent
ARTIFACTS = ROOT / "artifacts"

# Assumptions: the data has no interest income or recovery information.
# Profit is measured per unit of credit: a good loan earns +MARGIN, a default loses -LGD.
MARGIN = 0.15
LGD = 0.50

# Postgres NUMERIC -> float (otherwise pandas receives Decimal objects)
DEC2FLOAT = psycopg2.extensions.new_type(
    psycopg2.extensions.DECIMAL.values, "DEC2FLOAT", lambda v, cur: float(v) if v is not None else None
)
psycopg2.extensions.register_type(DEC2FLOAT)

LGB_PARAMS = dict(
    objective="binary",
    learning_rate=0.05,
    num_leaves=31,
    min_child_samples=100,
    subsample=0.8,
    subsample_freq=1,
    colsample_bytree=0.8,
    reg_lambda=1.0,
    n_estimators=5000,
    random_state=SEED,
    n_jobs=8,
    verbose=-1,
)

RATIO_FEATURES = [
    "fe_credit_income_ratio", "fe_annuity_income_ratio", "fe_credit_annuity_ratio", "fe_goods_credit_ratio",
    "fe_income_per_person", "fe_employed_birth_ratio", "fe_bureau_debt_income_ratio",
    "fe_ext_source_mean", "fe_ext_source_std", "fe_ext_source_min", "fe_ext_source_max",
    "fe_ext_source_prod", "fe_ext_source_null_count",
]


def get_engine():
    load_dotenv(ROOT / ".env")
    return create_engine(
        f"postgresql+psycopg2://{os.environ['POSTGRES_USER']}:{os.environ['POSTGRES_PASSWORD']}"
        f"@localhost:{os.environ['POSTGRES_PORT']}/{os.environ['POSTGRES_DB']}"
    )


def load_split(engine, splits):
    """Returns only the requested splits from mart; other rows are never kept in memory."""
    ids = pd.read_csv(ROOT / "data" / "split_ids.csv")
    ids = ids[ids["split"].isin(splits)]
    df = pd.read_sql("SELECT * FROM mart.features_application ORDER BY sk_id_curr", engine)
    return df.merge(ids, on=ID, how="inner").reset_index(drop=True)


def feature_groups(columns):
    fe = [c for c in columns if c.startswith("fe_")]
    base = [c for c in columns if c not in (ID, TARGET, "split") and not c.startswith("fe_")]
    ratio = [c for c in fe if c in RATIO_FEATURES]
    window = [c for c in fe if c not in RATIO_FEATURES]
    return base, ratio, window


def to_lgb_frame(frame, features, categories):
    X = frame[features].copy()
    for c in features:
        if c in categories:
            X[c] = pd.Categorical(X[c], categories=categories[c])
    return X


def target_encode(train_values, y_train, apply_values, smoothing=100):
    """Smoothed default rate; unseen categories fall back to the overall rate."""
    prior = y_train.mean()
    stats = pd.DataFrame({"v": train_values, "y": y_train}).groupby("v")["y"].agg(["sum", "count"])
    encoded = (stats["sum"] + smoothing * prior) / (stats["count"] + smoothing)
    return pd.Series(apply_values).map(encoded).fillna(prior).to_numpy(float)


def encode_fold(X_tr, y_tr, X_va, column, seed=SEED):
    """The train side is encoded with inner OOF; otherwise the column would see its own target."""
    X_tr, X_va = X_tr.copy(), X_va.copy()
    tr_values = X_tr[column].astype(object).to_numpy()
    encoded = np.zeros(len(X_tr))
    inner = StratifiedKFold(5, shuffle=True, random_state=seed)
    for a, b in inner.split(tr_values, y_tr):
        encoded[b] = target_encode(tr_values[a], y_tr[a], tr_values[b])
    X_va[column] = target_encode(tr_values, y_tr, X_va[column].astype(object).to_numpy())
    X_tr[column] = encoded
    return X_tr, X_va


def run_cv(frame, features, categories, params=None, n_splits=5, seed=SEED, encode_column=None):
    params = {**LGB_PARAMS, **(params or {})}
    y = frame[TARGET].to_numpy()
    X = to_lgb_frame(frame, features, categories)
    oof = np.zeros(len(frame))
    aucs, train_aucs, iters = [], [], []
    for tr, va in StratifiedKFold(n_splits, shuffle=True, random_state=seed).split(X, y):
        X_tr, X_va = X.iloc[tr], X.iloc[va]
        if encode_column:
            X_tr, X_va = encode_fold(X_tr, y[tr], X_va, encode_column, seed)
        model = lgb.LGBMClassifier(**params)
        model.fit(
            X_tr, y[tr],
            eval_X=(X_va,),
            eval_y=(y[va],),
            eval_metric="auc",
            callbacks=[lgb.early_stopping(100, verbose=False)],
        )
        oof[va] = model.predict_proba(X_va)[:, 1]
        aucs.append(roc_auc_score(y[va], oof[va]))
        train_aucs.append(roc_auc_score(y[tr], model.predict_proba(X_tr)[:, 1]))
        iters.append(model.best_iteration_)
    return dict(
        oof=oof,
        auc=float(np.mean(aucs)),
        auc_std=float(np.std(aucs)),
        train_auc=float(np.mean(train_aucs)),
        best_iter=int(np.median(iters)),
    )


def cv_row(result):
    return {
        "CV AUC": result["auc"],
        "std": result["auc_std"],
        "train AUC": result["train_auc"],
        "train-CV gap": result["train_auc"] - result["auc"],
        "trees": result["best_iter"],
    }


def score_metrics(y, p):
    return {
        "ROC-AUC": roc_auc_score(y, p),
        "Gini": 2 * roc_auc_score(y, p) - 1,
        "PR-AUC": average_precision_score(y, p),
        "LogLoss": log_loss(y, p),
        "Brier": brier_score_loss(y, p),
    }


def expected_calibration_error(y, p, bins=10):
    q = pd.qcut(p, bins, duplicates="drop")
    g = pd.DataFrame({"y": y, "p": p, "q": q}).groupby("q", observed=True).agg(y=("y", "mean"), p=("p", "mean"), n=("y", "size"))
    return float((np.abs(g["y"] - g["p"]) * g["n"]).sum() / g["n"].sum())


def reliability_table(y, p, bins=10):
    q = pd.qcut(p, bins, duplicates="drop")
    return (pd.DataFrame({"y": y, "p": p, "q": q})
            .groupby("q", observed=True)
            .agg(mean_predicted=("p", "mean"), observed_rate=("y", "mean"), n=("y", "size"))
            .reset_index(drop=True))


def policy_row(y, p, credit, threshold, margin=MARGIN, lgd=LGD):
    """Applications with p < threshold are approved; profit is divided by total credit."""
    ok = p < threshold
    good, bad = ok & (y == 0), ok & (y == 1)
    profit = margin * credit[good].sum() - lgd * credit[bad].sum()
    return {
        "threshold": threshold,
        "approval rate": ok.mean(),
        "default rate (approved)": y[ok].mean() if ok.any() else np.nan,
        "defaults rejected": 1 - y[ok].sum() / y.sum(),
        "profit / total credit": profit / credit.sum(),
    }


def fairness_table(y, p, groups, threshold):
    rows = {}
    for name in pd.unique(groups[pd.notna(groups)]):
        m = (groups == name)
        yg, pg = y[m], p[m]
        ok = pg < threshold
        rows[name] = {
            "n": int(m.sum()),
            "actual default rate": yg.mean(),
            "mean PD": pg.mean(),
            "AUC": roc_auc_score(yg, pg),
            "approval rate": ok.mean(),
            "approval rate (good)": ok[yg == 0].mean(),
            "approval rate (bad)": ok[yg == 1].mean(),
            "default rate (approved)": yg[ok].mean(),
        }
    return pd.DataFrame(rows).T.sort_index()


def age_band(days_birth):
    return pd.cut(-days_birth / 365.25, [0, 30, 45, 60, 120], labels=["<30", "30-44", "45-59", "60+"], right=False).astype(object).to_numpy()
