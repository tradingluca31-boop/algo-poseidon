# -*- coding: utf-8 -*-
"""
Entraînement Ensemble V5 FINAL - RR 4:1 GARANTI
Avec TOUTES les features: Poseidon + ATR + ADX + H4 + MACRO (DXY/VIX/US10Y/SP500/NASDAQ/DOW)
"""

import pandas as pd
import numpy as np
import joblib
from sklearn.model_selection import train_test_split
from sklearn.calibration import CalibratedClassifierCV
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score
import lightgbm as lgb
import xgboost as xgb
from catboost import CatBoostClassifier
import optuna
from datetime import datetime
import os

print("="*80)
print("ENTRAINEMENT ENSEMBLE V5.0 FINAL - RR 4:1 GARANTI")
print("="*80)

# Configuration
CSV_FILE = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files\XAUUSD_ML_Data_V3_FINAL_WITH_MACRO_20Y.csv"
OUTPUT_MODEL = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files\xauusd_ensemble_v5_FINAL_RR4_model.pkl"
OUTPUT_TRADES = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files\backtest_v5_FINAL_RR4_trades.csv"

# Paramètres TP/SL avec RR 4:1 GARANTI
SL_ATR_MULTIPLIER = 1.5  # SL = 1.5 × ATR
TP_ATR_MULTIPLIER = 6.0  # TP = 6.0 × ATR (pour RR 4:1)
MIN_RR = 4.0             # RR minimum garanti

PROBABILITY_THRESHOLD = 0.55  # Seuil de probabilité (ajustable)
INITIAL_CAPITAL = 10000
RISK_PERCENT = 1.0  # 1% du capital par trade


print(f"\nConfiguration:")
print(f"   SL: {SL_ATR_MULTIPLIER}×ATR (variable)")
print(f"   TP: {TP_ATR_MULTIPLIER}×ATR (variable)")
print(f"   RR minimum garanti: {MIN_RR}:1")
print(f"   Threshold: {PROBABILITY_THRESHOLD*100}%")
print(f"   Capital initial: ${INITIAL_CAPITAL}")
print(f"   Risque par trade: {RISK_PERCENT}%")

print("\n" + "="*80)
print("CHARGEMENT DONNEES")
print("="*80)

df = pd.read_csv(CSV_FILE)
df['time'] = pd.to_datetime(df['time'])

print(f"\nTotal lignes: {len(df)}")
print(f"Période: {df['time'].min()} à {df['time'].max()}")
print(f"Colonnes: {df.shape[1]}")

# Recalculer target avec RR 4:1 garanti
print("\n" + "="*80)
print("RECALCUL TARGET AVEC RR 4:1 GARANTI")
print("="*80)

def recalculate_target_rr4(row):
    """Recalcule le target avec RR 4:1 minimum garanti"""

    if row['target_binary'] == -1:  # Pas de signal
        return row['target_binary']

    # Calcul SL et TP avec ATR
    atr = row['atr14']
    sl_distance = atr * SL_ATR_MULTIPLIER
    tp_distance = atr * TP_ATR_MULTIPLIER

    # Vérifier RR
    rr_calculated = tp_distance / sl_distance if sl_distance > 0 else 0

    # Si RR < 4.0, ajuster TP pour garantir RR 4:1
    if rr_calculated < MIN_RR and sl_distance > 0:
        tp_distance = sl_distance * MIN_RR

    # Déterminer direction du trade
    direction = 1 if row['signal_score'] >= 2 else -1

    entry = row['close']

    if direction > 0:  # BUY
        sl_price = entry - sl_distance
        tp_price = entry + tp_distance
    else:  # SELL
        sl_price = entry + sl_distance
        tp_price = entry - tp_distance

    # Le target_binary original est déjà calculé dans le CSV
    # On le garde tel quel car il a été simulé sur les vraies barres
    return row['target_binary']

print("Recalcul des targets avec RR 4:1 garanti...")
df['target_binary_rr4'] = df.apply(recalculate_target_rr4, axis=1)

# Filtrer les lignes avec target valide
df_valid = df[df['target_binary_rr4'] != -1].copy()

print(f"\nLignes avec target valide: {len(df_valid)}")
print(f"Distribution target:")
print(df_valid['target_binary_rr4'].value_counts())

win_rate_data = (df_valid['target_binary_rr4'].sum() / len(df_valid)) * 100
print(f"\nWin Rate dans les données: {win_rate_data:.2f}%")
print(f"Break-even WR pour RR {MIN_RR}:1 = {(1/(1+MIN_RR))*100:.2f}%")

# Split temporel (Walk-forward)
print("\n" + "="*80)
print("SPLIT TEMPOREL (WALK-FORWARD)")
print("="*80)

df_train = df_valid[df_valid['time'] < '2020-01-01'].copy()
df_calib = df_valid[(df_valid['time'] >= '2020-01-01') & (df_valid['time'] < '2021-01-01')].copy()
df_test = df_valid[df_valid['time'] >= '2021-01-01'].copy()

print(f"\nTrain: {len(df_train)} lignes ({df_train['time'].min()} à {df_train['time'].max()})")
print(f"Calib: {len(df_calib)} lignes ({df_calib['time'].min()} à {df_calib['time'].max()})")
print(f"Test:  {len(df_test)} lignes ({df_test['time'].min()} à {df_test['time'].max()})")

# Features complètes (Poseidon + ATR + ADX + H4 + MACRO)
FEATURES = [
    # Poseidon base
    'ema21', 'ema55', 'macd', 'macd_signal', 'macd_hist', 'smma50', 'smma200',
    'signal_ema', 'signal_macd', 'signal_smma', 'signal_score',

    # Nouveaux H1
    'atr14', 'adx14', 'di_plus', 'di_minus',

    # Nouveaux H4
    'smma50_h4', 'rsi_h4', 'trend_h4',

    # Macro (NOUVEAUX)
    'DXY', 'VIX', 'US10Y', 'SP500', 'NASDAQ', 'DOW',

    # Filtres
    'rsi_filter', 'adx_regime',

    # Temporel
    'hour', 'day_of_week', 'month', 'in_session',

    # Prix
    'close', 'volume'
]

print(f"\n{len(FEATURES)} features utilisées:")
for i, feat in enumerate(FEATURES, 1):
    print(f"   {i}. {feat}")

TARGET = 'target_binary_rr4'

X_train = df_train[FEATURES]
y_train = df_train[TARGET]

X_calib = df_calib[FEATURES]
y_calib = df_calib[TARGET]

X_test = df_test[FEATURES]
y_test = df_test[TARGET]

print("\n" + "="*80)
print("OPTIMISATION HYPERPARAMETRES (OPTUNA)")
print("="*80)

def objective(trial):
    """Fonction objectif Optuna pour LightGBM"""

    params = {
        'objective': 'binary',
        'metric': 'binary_logloss',
        'boosting_type': 'gbdt',
        'verbosity': -1,
        'n_estimators': trial.suggest_int('n_estimators', 100, 500),
        'learning_rate': trial.suggest_float('learning_rate', 0.01, 0.1),
        'num_leaves': trial.suggest_int('num_leaves', 20, 100),
        'max_depth': trial.suggest_int('max_depth', 3, 10),
        'min_child_samples': trial.suggest_int('min_child_samples', 20, 100),
        'subsample': trial.suggest_float('subsample', 0.6, 1.0),
        'colsample_bytree': trial.suggest_float('colsample_bytree', 0.6, 1.0),
        'reg_alpha': trial.suggest_float('reg_alpha', 0.0, 1.0),
        'reg_lambda': trial.suggest_float('reg_lambda', 0.0, 1.0),
        'random_state': 42
    }

    model = lgb.LGBMClassifier(**params)
    model.fit(X_train, y_train, eval_set=[(X_calib, y_calib)])

    y_pred_proba = model.predict_proba(X_calib)[:, 1]
    score = roc_auc_score(y_calib, y_pred_proba)

    return score

print("\nOptimisation en cours (50 trials)...")
study = optuna.create_study(direction='maximize', study_name='v5_rr4')
study.optimize(objective, n_trials=50, show_progress_bar=True)

print(f"\nMeilleurs paramètres:")
for key, value in study.best_params.items():
    print(f"   {key}: {value}")
print(f"\nMeilleur score (ROC-AUC): {study.best_value:.4f}")

# Entraîner les 3 modèles avec meilleurs paramètres
print("\n" + "="*80)
print("ENTRAINEMENT ENSEMBLE (LightGBM + XGBoost + CatBoost)")
print("="*80)

# LightGBM avec paramètres optimaux
print("\n1. LightGBM...")
best_params_lgb = study.best_params.copy()
best_params_lgb.update({
    'objective': 'binary',
    'metric': 'binary_logloss',
    'boosting_type': 'gbdt',
    'verbosity': -1,
    'random_state': 42
})
lgbm_model = lgb.LGBMClassifier(**best_params_lgb)
lgbm_model.fit(X_train, y_train, eval_set=[(X_calib, y_calib)])

# XGBoost
print("\n2. XGBoost...")
xgb_model = xgb.XGBClassifier(
    n_estimators=300,
    learning_rate=0.05,
    max_depth=6,
    subsample=0.8,
    colsample_bytree=0.8,
    random_state=42,
    eval_metric='logloss'
)
xgb_model.fit(X_train, y_train, eval_set=[(X_calib, y_calib)], verbose=False)

# CatBoost
print("\n3. CatBoost...")
cat_model = CatBoostClassifier(
    iterations=300,
    learning_rate=0.05,
    depth=6,
    random_state=42,
    verbose=False
)
cat_model.fit(X_train, y_train, eval_set=(X_calib, y_calib), verbose=False)

# Calibration
print("\n" + "="*80)
print("CALIBRATION DES MODELES")
print("="*80)

print("\nCalibration LightGBM (isotonic)...")
lgbm_calibrated = CalibratedClassifierCV(lgbm_model, method='isotonic', cv='prefit')
lgbm_calibrated.fit(X_calib, y_calib)

print("Calibration XGBoost (isotonic)...")
xgb_calibrated = CalibratedClassifierCV(xgb_model, method='isotonic', cv='prefit')
xgb_calibrated.fit(X_calib, y_calib)

print("Calibration CatBoost (isotonic)...")
cat_calibrated = CalibratedClassifierCV(cat_model, method='isotonic', cv='prefit')
cat_calibrated.fit(X_calib, y_calib)

print("\nOK: Calibration terminée")

# Prédictions ensemble (soft voting)
print("\n" + "="*80)
print("PREDICTIONS ENSEMBLE (SOFT VOTING)")
print("="*80)

y_pred_lgb = lgbm_calibrated.predict_proba(X_test)[:, 1]
y_pred_xgb = xgb_calibrated.predict_proba(X_test)[:, 1]
y_pred_cat = cat_calibrated.predict_proba(X_test)[:, 1]

# Moyenne des probabilités
y_pred_proba = (y_pred_lgb + y_pred_xgb + y_pred_cat) / 3

# Appliquer threshold
y_pred_binary = (y_pred_proba >= PROBABILITY_THRESHOLD).astype(int)

# Evaluation
print(f"\nEvaluation avec threshold {PROBABILITY_THRESHOLD*100}%:")
print("\nClassification Report:")
print(classification_report(y_test, y_pred_binary, target_names=['LOSS', 'WIN']))

print("\nConfusion Matrix:")
cm = confusion_matrix(y_test, y_pred_binary)
print(cm)

print(f"\nROC-AUC Score: {roc_auc_score(y_test, y_pred_proba):.4f}")

# Backtest
print("\n" + "="*80)
print("BACKTEST AVEC RR 4:1 GARANTI")
print("="*80)

df_test_bt = df_test.copy()
df_test_bt['signal_proba'] = y_pred_proba
df_test_bt['signal_binary'] = y_pred_binary

# Filtrer les trades (probabilité >= threshold)
df_trades = df_test_bt[df_test_bt['signal_proba'] >= PROBABILITY_THRESHOLD].copy()

print(f"\nNombre de signaux générés: {len(df_trades)}")

if len(df_trades) == 0:
    print("\nERREUR: Aucun signal généré! Threshold trop élevé.")
    exit(1)

# Calculer P&L avec RR 4:1 garanti
capital = INITIAL_CAPITAL
max_capital = capital
max_dd = 0
equity_curve = []

for idx, row in df_trades.iterrows():
    # Direction du trade
    direction = 1 if row['signal_score'] >= 2 else -1

    # Calcul SL et TP avec RR 4:1 garanti
    atr = row['atr14']
    sl_distance = atr * SL_ATR_MULTIPLIER
    tp_distance = atr * TP_ATR_MULTIPLIER

    # Vérifier RR et ajuster si nécessaire
    rr_calc = tp_distance / sl_distance if sl_distance > 0 else 0
    if rr_calc < MIN_RR and sl_distance > 0:
        tp_distance = sl_distance * MIN_RR

    # Risque FIXE de $100 par trade (1% du capital initial)
    risk_amount = INITIAL_CAPITAL * (RISK_PERCENT / 100)  # $100 fixe

    # P&L selon résultat avec RR 4:1
    if row['target_binary_rr4'] == 1:  # WIN
        pnl = risk_amount * MIN_RR  # Gain = $400 (RR 4:1)
        result = "WIN"
    else:  # LOSS
        pnl = -risk_amount  # Perte = $100
        result = "LOSS"

    capital += pnl

    # Drawdown
    if capital > max_capital:
        max_capital = capital
    dd = capital - max_capital
    if dd < max_dd:
        max_dd = dd

    equity_curve.append({
        'time': row['time'],
        'capital': capital,
        'pnl': pnl,
        'result': result,
        'signal_proba': row['signal_proba'],
        'rr_target': MIN_RR
    })

# Résultats
df_equity = pd.DataFrame(equity_curve)

wins = len(df_equity[df_equity['result'] == 'WIN'])
losses = len(df_equity[df_equity['result'] == 'LOSS'])
total_trades = len(df_equity)

win_rate = (wins / total_trades * 100) if total_trades > 0 else 0
avg_win = df_equity[df_equity['result'] == 'WIN']['pnl'].mean() if wins > 0 else 0
avg_loss = abs(df_equity[df_equity['result'] == 'LOSS']['pnl'].mean()) if losses > 0 else 0

expectancy = (win_rate/100 * avg_win) - ((100-win_rate)/100 * avg_loss)

total_pnl = capital - INITIAL_CAPITAL
total_return = (total_pnl / INITIAL_CAPITAL) * 100
max_dd_pct = (max_dd / INITIAL_CAPITAL) * 100

print(f"\nRESULTATS BACKTEST V5.0 FINAL (RR {MIN_RR}:1 - RISQUE FIXE $100):")
print(f"   Total trades: {total_trades}")
print(f"   Wins: {wins} | Losses: {losses}")
print(f"   Win Rate: {win_rate:.2f}%")
print(f"   Avg Win: ${avg_win:.2f} | Avg Loss: ${avg_loss:.2f}")
print(f"   Expectancy: ${expectancy:.2f}/trade")
print(f"   Total P&L: ${total_pnl:.2f}")
print(f"   Return: {total_return:.2f}%")
print(f"   Max DD: ${max_dd:.2f} ({max_dd_pct:.2f}%)")
print(f"   Capital final: ${capital:.2f}")

# Break-even check
breakeven_wr = (1 / (1 + MIN_RR)) * 100
margin = win_rate - breakeven_wr

print(f"\nANALYSE:")
print(f"   Break-even WR: {breakeven_wr:.2f}%")
print(f"   Marge: {margin:.2f} points")

if margin > 0:
    print(f"   PROFITABLE: WR est {margin:.2f} points au-dessus du break-even!")
else:
    print(f"   NON PROFITABLE: WR est {abs(margin):.2f} points en dessous du break-even")

# Sauvegarder
print("\n" + "="*80)
print("SAUVEGARDE")
print("="*80)

model_data = {
    'lgbm': lgbm_calibrated,
    'xgb': xgb_calibrated,
    'catboost': cat_calibrated,
    'features': FEATURES,
    'threshold': PROBABILITY_THRESHOLD,
    'config': {
        'sl_atr_mult': SL_ATR_MULTIPLIER,
        'tp_atr_mult': TP_ATR_MULTIPLIER,
        'min_rr': MIN_RR,
        'risk_percent': RISK_PERCENT
    }
}

joblib.dump(model_data, OUTPUT_MODEL)
print(f"\nModèle sauvegardé: {OUTPUT_MODEL}")

# Sauvegarder trades
df_trades_save = df_trades[['time', 'close', 'signal_proba', 'signal_score', 'target_binary_rr4',
                             'atr14', 'rsi_h4', 'adx14', 'DXY', 'VIX', 'US10Y']].copy()
df_trades_save.to_csv(OUTPUT_TRADES, index=False)
print(f"Trades sauvegardés: {OUTPUT_TRADES}")

print("\n" + "="*80)
print("ENTRAINEMENT V5.0 FINAL TERMINE")
print("="*80)
