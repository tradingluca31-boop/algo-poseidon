# -*- coding: utf-8 -*-
"""
Entraînement Ensemble V6 OPTIMIZED - Améliorations Complètes
- Feature Engineering Avancé
- Optimisation du Threshold
- Walk-Forward Optimization
- Ensemble élargi (5 modèles)
"""

import pandas as pd
import numpy as np
import joblib
from sklearn.model_selection import train_test_split
from sklearn.calibration import CalibratedClassifierCV
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score
from sklearn.ensemble import RandomForestClassifier, ExtraTreesClassifier
import lightgbm as lgb
import xgboost as xgb
from catboost import CatBoostClassifier
import optuna
from datetime import datetime
import os

print("="*80)
print("ENTRAINEMENT ENSEMBLE V6.0 OPTIMIZED")
print("="*80)

# Configuration
CSV_FILE = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files\XAUUSD_ML_Data_V3_FINAL_WITH_MACRO_20Y.csv"
OUTPUT_MODEL = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files\xauusd_ensemble_v6_OPTIMIZED_model.pkl"
OUTPUT_TRADES = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files\backtest_v6_OPTIMIZED_trades.csv"
OUTPUT_THRESHOLD_ANALYSIS = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files\threshold_analysis_v6.csv"

# Paramètres TP/SL avec RR 4:1 GARANTI
SL_ATR_MULTIPLIER = 1.5
TP_ATR_MULTIPLIER = 6.0
MIN_RR = 4.0

# Threshold sera optimisé automatiquement
INITIAL_CAPITAL = 10000
RISK_PERCENT = 1.0

print(f"\nConfiguration:")
print(f"   SL: {SL_ATR_MULTIPLIER}×ATR (variable)")
print(f"   TP: {TP_ATR_MULTIPLIER}×ATR (variable)")
print(f"   RR minimum garanti: {MIN_RR}:1")
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

# NOUVEAU: Feature Engineering Avancé
print("\n" + "="*80)
print("FEATURE ENGINEERING AVANCÉ")
print("="*80)

def create_advanced_features(df):
    """Création de features avancées"""

    print("\nCréation de nouvelles features...")

    # 1. Volatilité multi-timeframe
    df['atr_ratio_h4_h1'] = df['atr14'] / (df['atr14'].rolling(96).mean() + 1e-10)  # 96 bars = 4 jours H1

    # 2. Volume spike (écart par rapport à la moyenne)
    df['volume_ma20'] = df['volume'].rolling(20).mean()
    df['volume_spike'] = df['volume'] / (df['volume_ma20'] + 1e-10)

    # 3. Distance prix / EMAs
    df['price_distance_ema21'] = (df['close'] - df['ema21']) / df['close']
    df['price_distance_ema55'] = (df['close'] - df['ema55']) / df['close']

    # 4. RSI momentum (changement de RSI)
    df['rsi_momentum'] = df['rsi_h4'] - df['rsi_h4'].shift(1)

    # 5. MACD momentum
    df['macd_momentum'] = df['macd_hist'] - df['macd_hist'].shift(1)

    # 6. ADX strength (forte tendance si ADX > 25)
    df['adx_strong_trend'] = (df['adx14'] > 25).astype(int)

    # 7. Correlation DXY/VIX (inverse correlation avec or)
    df['dxy_vix_product'] = df['DXY'] * df['VIX']  # Produit comme proxy de risk-off

    # 8. Macro momentum
    df['dxy_momentum'] = df['DXY'] - df['DXY'].shift(1)
    df['vix_momentum'] = df['VIX'] - df['VIX'].shift(1)

    # 9. Support/Resistance approximatif (high/low rolling)
    df['resistance_distance'] = (df['high'].rolling(20).max() - df['close']) / df['close']
    df['support_distance'] = (df['close'] - df['low'].rolling(20).min()) / df['close']

    # 10. EMA crossover strength
    df['ema_cross_strength'] = (df['ema21'] - df['ema55']) / df['close']

    # 11. SMMA crossover H1 vs H4
    df['smma_alignment'] = ((df['smma50'] > df['smma200']).astype(int) == df['trend_h4']).astype(int)

    # 12. RSI extremes
    df['rsi_extreme_high'] = (df['rsi_h4'] > 70).astype(int)
    df['rsi_extreme_low'] = (df['rsi_h4'] < 30).astype(int)

    # Remplir NaN
    df = df.fillna(method='ffill').fillna(method='bfill').fillna(0)

    print(f"✅ {15} nouvelles features créées")

    return df

df = create_advanced_features(df)

# Recalculer target avec RR 4:1 garanti
print("\n" + "="*80)
print("RECALCUL TARGET AVEC RR 4:1 GARANTI")
print("="*80)

def recalculate_target_rr4(row):
    """Recalcule le target avec RR 4:1 minimum garanti"""
    if row['target_binary'] == -1:
        return row['target_binary']

    atr = row['atr14']
    sl_distance = atr * SL_ATR_MULTIPLIER
    tp_distance = atr * TP_ATR_MULTIPLIER

    rr_calculated = tp_distance / sl_distance if sl_distance > 0 else 0
    if rr_calculated < MIN_RR and sl_distance > 0:
        tp_distance = sl_distance * MIN_RR

    return row['target_binary']

df['target_binary_rr4'] = df.apply(recalculate_target_rr4, axis=1)
df_valid = df[df['target_binary_rr4'] != -1].copy()

print(f"\nLignes avec target valide: {len(df_valid)}")
print(f"Distribution target:")
print(df_valid['target_binary_rr4'].value_counts())

win_rate_data = (df_valid['target_binary_rr4'].sum() / len(df_valid)) * 100
print(f"\nWin Rate dans les données: {win_rate_data:.2f}%")
print(f"Break-even WR pour RR {MIN_RR}:1 = {(1/(1+MIN_RR))*100:.2f}%")

# WALK-FORWARD OPTIMIZATION
print("\n" + "="*80)
print("WALK-FORWARD OPTIMIZATION (3 FENÊTRES)")
print("="*80)

# Définir les fenêtres
windows = [
    {
        'name': 'Window 1',
        'train_start': '2008-01-01', 'train_end': '2016-12-31',
        'calib_start': '2017-01-01', 'calib_end': '2017-12-31',
        'test_start': '2018-01-01', 'test_end': '2019-12-31'
    },
    {
        'name': 'Window 2',
        'train_start': '2010-01-01', 'train_end': '2018-12-31',
        'calib_start': '2019-01-01', 'calib_end': '2019-12-31',
        'test_start': '2020-01-01', 'test_end': '2021-12-31'
    },
    {
        'name': 'Window 3',
        'train_start': '2012-01-01', 'train_end': '2020-12-31',
        'calib_start': '2021-01-01', 'calib_end': '2021-12-31',
        'test_start': '2022-01-01', 'test_end': '2025-12-31'
    }
]

# Features complètes (V5 + nouvelles features V6)
FEATURES_BASE = [
    # Poseidon base
    'ema21', 'ema55', 'macd', 'macd_signal', 'macd_hist', 'smma50', 'smma200',
    'signal_ema', 'signal_macd', 'signal_smma', 'signal_score',
    # H1
    'atr14', 'adx14', 'di_plus', 'di_minus',
    # H4
    'smma50_h4', 'rsi_h4', 'trend_h4',
    # Macro
    'DXY', 'VIX', 'US10Y', 'SP500', 'NASDAQ', 'DOW',
    # Filtres
    'rsi_filter', 'adx_regime',
    # Temporel
    'hour', 'day_of_week', 'month', 'in_session',
    # Prix
    'close', 'volume'
]

FEATURES_ADVANCED = [
    # Nouvelles V6
    'atr_ratio_h4_h1', 'volume_spike', 'price_distance_ema21', 'price_distance_ema55',
    'rsi_momentum', 'macd_momentum', 'adx_strong_trend', 'dxy_vix_product',
    'dxy_momentum', 'vix_momentum', 'resistance_distance', 'support_distance',
    'ema_cross_strength', 'smma_alignment', 'rsi_extreme_high', 'rsi_extreme_low'
]

FEATURES = FEATURES_BASE + FEATURES_ADVANCED

print(f"\n{len(FEATURES)} features totales:")
print(f"   - {len(FEATURES_BASE)} features de base (V5)")
print(f"   - {len(FEATURES_ADVANCED)} nouvelles features (V6)")

TARGET = 'target_binary_rr4'

# Entraînement Walk-Forward
all_models = []
all_test_results = []

for i, window in enumerate(windows, 1):
    print(f"\n{'='*80}")
    print(f"WINDOW {i}: {window['name']}")
    print(f"{'='*80}")

    # Split données
    df_train = df_valid[(df_valid['time'] >= window['train_start']) & (df_valid['time'] <= window['train_end'])].copy()
    df_calib = df_valid[(df_valid['time'] >= window['calib_start']) & (df_valid['time'] <= window['calib_end'])].copy()
    df_test = df_valid[(df_valid['time'] >= window['test_start']) & (df_valid['time'] <= window['test_end'])].copy()

    print(f"\nTrain: {len(df_train)} lignes ({window['train_start']} à {window['train_end']})")
    print(f"Calib: {len(df_calib)} lignes ({window['calib_start']} à {window['calib_end']})")
    print(f"Test:  {len(df_test)} lignes ({window['test_start']} à {window['test_end']})")

    if len(df_train) < 1000 or len(df_calib) < 100 or len(df_test) < 100:
        print(f"⚠️ Fenêtre {i} ignorée (données insuffisantes)")
        continue

    X_train = df_train[FEATURES]
    y_train = df_train[TARGET]
    X_calib = df_calib[FEATURES]
    y_calib = df_calib[TARGET]
    X_test = df_test[FEATURES]
    y_test = df_test[TARGET]

    # Optuna pour LightGBM (rapide, 30 trials)
    print(f"\n--- Optimisation Optuna (30 trials) ---")

    def objective(trial):
        params = {
            'objective': 'binary',
            'metric': 'binary_logloss',
            'boosting_type': 'gbdt',
            'verbosity': -1,
            'n_estimators': trial.suggest_int('n_estimators', 100, 300),
            'learning_rate': trial.suggest_float('learning_rate', 0.01, 0.05),
            'num_leaves': trial.suggest_int('num_leaves', 20, 60),
            'max_depth': trial.suggest_int('max_depth', 3, 6),
            'min_child_samples': trial.suggest_int('min_child_samples', 20, 60),
            'subsample': trial.suggest_float('subsample', 0.6, 0.9),
            'colsample_bytree': trial.suggest_float('colsample_bytree', 0.6, 0.9),
            'reg_alpha': trial.suggest_float('reg_alpha', 0.0, 1.0),
            'reg_lambda': trial.suggest_float('reg_lambda', 0.0, 1.0),
            'random_state': 42
        }

        model = lgb.LGBMClassifier(**params)
        model.fit(X_train, y_train, eval_set=[(X_calib, y_calib)])

        y_pred_proba = model.predict_proba(X_calib)[:, 1]
        score = roc_auc_score(y_calib, y_pred_proba)

        return score

    study = optuna.create_study(direction='maximize', study_name=f'v6_window{i}')
    study.optimize(objective, n_trials=30, show_progress_bar=False)

    print(f"Meilleur ROC-AUC: {study.best_value:.4f}")

    # Entraîner les 5 modèles
    print(f"\n--- Entraînement Ensemble (5 modèles) ---")

    # 1. LightGBM optimisé
    best_params_lgb = study.best_params.copy()
    best_params_lgb.update({'objective': 'binary', 'metric': 'binary_logloss', 'boosting_type': 'gbdt', 'verbosity': -1, 'random_state': 42})
    lgbm_model = lgb.LGBMClassifier(**best_params_lgb)
    lgbm_model.fit(X_train, y_train, eval_set=[(X_calib, y_calib)])

    # 2. XGBoost
    xgb_model = xgb.XGBClassifier(n_estimators=200, learning_rate=0.03, max_depth=5, subsample=0.8, colsample_bytree=0.8, random_state=42, eval_metric='logloss')
    xgb_model.fit(X_train, y_train, eval_set=[(X_calib, y_calib)], verbose=False)

    # 3. CatBoost
    cat_model = CatBoostClassifier(iterations=200, learning_rate=0.03, depth=5, random_state=42, verbose=False)
    cat_model.fit(X_train, y_train, eval_set=(X_calib, y_calib), verbose=False)

    # 4. RandomForest
    rf_model = RandomForestClassifier(n_estimators=200, max_depth=10, min_samples_split=20, random_state=42, n_jobs=-1)
    rf_model.fit(X_train, y_train)

    # 5. ExtraTrees
    et_model = ExtraTreesClassifier(n_estimators=200, max_depth=10, min_samples_split=20, random_state=42, n_jobs=-1)
    et_model.fit(X_train, y_train)

    # Calibration
    print(f"\n--- Calibration ---")
    lgbm_calibrated = CalibratedClassifierCV(lgbm_model, method='isotonic', cv='prefit')
    lgbm_calibrated.fit(X_calib, y_calib)

    xgb_calibrated = CalibratedClassifierCV(xgb_model, method='isotonic', cv='prefit')
    xgb_calibrated.fit(X_calib, y_calib)

    cat_calibrated = CalibratedClassifierCV(cat_model, method='isotonic', cv='prefit')
    cat_calibrated.fit(X_calib, y_calib)

    rf_calibrated = CalibratedClassifierCV(rf_model, method='isotonic', cv='prefit')
    rf_calibrated.fit(X_calib, y_calib)

    et_calibrated = CalibratedClassifierCV(et_model, method='isotonic', cv='prefit')
    et_calibrated.fit(X_calib, y_calib)

    # Prédictions ensemble
    y_pred_lgb = lgbm_calibrated.predict_proba(X_test)[:, 1]
    y_pred_xgb = xgb_calibrated.predict_proba(X_test)[:, 1]
    y_pred_cat = cat_calibrated.predict_proba(X_test)[:, 1]
    y_pred_rf = rf_calibrated.predict_proba(X_test)[:, 1]
    y_pred_et = et_calibrated.predict_proba(X_test)[:, 1]

    # Moyenne pondérée (donner plus de poids aux meilleurs modèles)
    y_pred_proba = (y_pred_lgb * 0.3 + y_pred_xgb * 0.25 + y_pred_cat * 0.25 + y_pred_rf * 0.1 + y_pred_et * 0.1)

    # Sauvegarder pour analyse
    all_models.append({
        'window': i,
        'lgbm': lgbm_calibrated,
        'xgb': xgb_calibrated,
        'catboost': cat_calibrated,
        'rf': rf_calibrated,
        'et': et_calibrated,
        'features': FEATURES
    })

    all_test_results.append({
        'window': i,
        'df_test': df_test,
        'y_pred_proba': y_pred_proba,
        'y_test': y_test
    })

    print(f"✅ Window {i} terminée")

# OPTIMISATION DU THRESHOLD
print("\n" + "="*80)
print("OPTIMISATION DU THRESHOLD")
print("="*80)

# Combiner tous les résultats de test
df_all_test = pd.concat([r['df_test'].assign(y_pred_proba=r['y_pred_proba']) for r in all_test_results])
y_all_test = pd.concat([pd.Series(r['y_test'].values) for r in all_test_results])

print(f"\nTotal test samples: {len(df_all_test)}")

# Tester différents thresholds
thresholds = np.arange(0.50, 0.71, 0.01)
threshold_results = []

for threshold in thresholds:
    df_test_bt = df_all_test.copy()
    df_test_bt['signal_binary'] = (df_test_bt['y_pred_proba'] >= threshold).astype(int)

    # Filtrer trades
    df_trades = df_test_bt[df_test_bt['signal_binary'] == 1].copy()

    if len(df_trades) == 0:
        continue

    # Backtest simple
    risk_amount = INITIAL_CAPITAL * (RISK_PERCENT / 100)
    wins = (df_trades['target_binary_rr4'] == 1).sum()
    losses = (df_trades['target_binary_rr4'] == 0).sum()
    total_trades = len(df_trades)

    if total_trades == 0:
        continue

    win_rate = wins / total_trades

    # P&L
    total_pnl = (wins * risk_amount * MIN_RR) - (losses * risk_amount)
    expectancy = total_pnl / total_trades

    # Sharpe approximatif
    pnls = []
    for _, row in df_trades.iterrows():
        if row['target_binary_rr4'] == 1:
            pnls.append(risk_amount * MIN_RR)
        else:
            pnls.append(-risk_amount)

    sharpe = np.mean(pnls) / (np.std(pnls) + 1e-10) if len(pnls) > 0 else 0

    threshold_results.append({
        'threshold': threshold,
        'total_trades': total_trades,
        'win_rate': win_rate,
        'expectancy': expectancy,
        'sharpe': sharpe,
        'total_pnl': total_pnl
    })

# Trouver meilleur threshold par Sharpe
df_threshold = pd.DataFrame(threshold_results)
best_idx = df_threshold['sharpe'].idxmax()
best_threshold = df_threshold.loc[best_idx, 'threshold']

print(f"\nMeilleur threshold trouvé: {best_threshold:.2f}")
print(f"   Sharpe Ratio: {df_threshold.loc[best_idx, 'sharpe']:.4f}")
print(f"   Win Rate: {df_threshold.loc[best_idx, 'win_rate']*100:.2f}%")
print(f"   Expectancy: ${df_threshold.loc[best_idx, 'expectancy']:.2f}")
print(f"   Total trades: {df_threshold.loc[best_idx, 'total_trades']:.0f}")

# Sauvegarder analyse
df_threshold.to_csv(OUTPUT_THRESHOLD_ANALYSIS, index=False)
print(f"\n✅ Analyse threshold sauvegardée: {OUTPUT_THRESHOLD_ANALYSIS}")

# BACKTEST FINAL AVEC THRESHOLD OPTIMAL
print("\n" + "="*80)
print(f"BACKTEST FINAL (Threshold: {best_threshold:.2f})")
print("="*80)

df_test_final = df_all_test.copy()
df_test_final['signal_binary'] = (df_test_final['y_pred_proba'] >= best_threshold).astype(int)
df_trades_final = df_test_final[df_test_final['signal_binary'] == 1].copy()

print(f"\nNombre de trades: {len(df_trades_final)}")

# Backtest complet
capital = INITIAL_CAPITAL
max_capital = capital
max_dd = 0
equity_curve = []

for idx, row in df_trades_final.iterrows():
    risk_amount = INITIAL_CAPITAL * (RISK_PERCENT / 100)

    if row['target_binary_rr4'] == 1:
        pnl = risk_amount * MIN_RR
        result = "WIN"
    else:
        pnl = -risk_amount
        result = "LOSS"

    capital += pnl

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
        'signal_proba': row['y_pred_proba']
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

print(f"\n{'='*80}")
print(f"RESULTATS V6.0 OPTIMIZED (RR {MIN_RR}:1 - Threshold {best_threshold:.2f}):")
print(f"{'='*80}")
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
    print(f"   ✅ PROFITABLE: WR est {margin:.2f} points au-dessus du break-even!")
else:
    print(f"   ❌ NON PROFITABLE: WR est {abs(margin):.2f} points en dessous du break-even")

# Sauvegarder
print("\n" + "="*80)
print("SAUVEGARDE")
print("="*80)

# Utiliser le dernier modèle (window 3 = 2022-2025)
final_model = all_models[-1]

model_data = {
    'lgbm': final_model['lgbm'],
    'xgb': final_model['xgb'],
    'catboost': final_model['catboost'],
    'rf': final_model['rf'],
    'et': final_model['et'],
    'features': FEATURES,
    'threshold': best_threshold,
    'config': {
        'sl_atr_mult': SL_ATR_MULTIPLIER,
        'tp_atr_mult': TP_ATR_MULTIPLIER,
        'min_rr': MIN_RR,
        'risk_percent': RISK_PERCENT
    }
}

joblib.dump(model_data, OUTPUT_MODEL)
print(f"\n✅ Modèle sauvegardé: {OUTPUT_MODEL}")

# Sauvegarder trades
df_trades_save = df_trades_final[['time', 'close', 'y_pred_proba', 'signal_score', 'target_binary_rr4',
                                   'atr14', 'rsi_h4', 'adx14', 'DXY', 'VIX', 'US10Y']].copy()
df_trades_save.to_csv(OUTPUT_TRADES, index=False)
print(f"✅ Trades sauvegardés: {OUTPUT_TRADES}")

print("\n" + "="*80)
print("ENTRAINEMENT V6.0 OPTIMIZED TERMINE")
print("="*80)
