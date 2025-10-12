# -*- coding: utf-8 -*-
"""
Entraînement Ensemble V3.0 avec CALIBRATION DES PROBABILITES
Version CORRIGÉE avec CalibratedClassifierCV

AMELIORATIONS:
- Calibration Isotonic des probabilités (fix le problème de sur-optimisme)
- Validation temporelle stricte
- Vérification de la calibration sur données out-of-sample
"""

import pandas as pd
import numpy as np
import lightgbm as lgb
import xgboost as xgb
import catboost as cb
from sklearn.ensemble import VotingClassifier
from sklearn.calibration import CalibratedClassifierCV
from sklearn.metrics import roc_auc_score, brier_score_loss
import joblib
import os
from datetime import datetime
from tqdm import tqdm

print("=" * 80)
print("ENTRAINEMENT ENSEMBLE V3.0 - AVEC CALIBRATION")
print("=" * 80)

# ==================== CONFIGURATION ====================
DATA_CSV = "XAUUSD_ML_Data_V2_ATR_20Y.csv"
OUTPUT_MODEL = "xauusd_ensemble_v3_calibrated_model.pkl"

# Split temporel
TRAIN_END_DATE = "2019-12-31"  # Reduire train pour avoir plus de validation
VAL_END_DATE = "2020-12-31"    # Période de calibration
TEST_START_DATE = "2021-01-01"

# Paramètres trading
PROBABILITY_THRESHOLD = 0.50
RISK_PER_TRADE = 100
USE_BREAK_EVEN = False

print(f"\nConfiguration:")
print(f"   Donnees: {DATA_CSV}")
print(f"   Train: jusqu'a {TRAIN_END_DATE}")
print(f"   Calibration: {TRAIN_END_DATE} -> {VAL_END_DATE}")
print(f"   Test: a partir de {TEST_START_DATE}")

# ==================== CHARGEMENT ====================
print("\n" + "=" * 80)
print("CHARGEMENT DONNEES")
print("=" * 80)

base_path = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
csv_path = os.path.join(base_path, DATA_CSV)

df = pd.read_csv(csv_path)
df['time'] = pd.to_datetime(df['time'])
df = df.sort_values('time').reset_index(drop=True)

print(f"OK: {len(df)} lignes chargees")

# Filtrer target valide
df_valid = df[df['target_binary'].isin([0, 1])].copy()
print(f"OK: {len(df_valid)} lignes avec target valide")

# ==================== PREPARATION FEATURES ====================
exclude_cols = ['time', 'target_binary', 'target_pct_change', 'sl_price', 'tp_price',
                'open', 'high', 'low', 'close']
feature_cols = [col for col in df_valid.columns if col not in exclude_cols]

print(f"Features: {len(feature_cols)}")

# ==================== SPLIT TEMPOREL ====================
print("\n" + "=" * 80)
print("SPLIT TEMPOREL STRICT")
print("=" * 80)

train_mask = df_valid['time'] <= TRAIN_END_DATE
calib_mask = (df_valid['time'] > TRAIN_END_DATE) & (df_valid['time'] <= VAL_END_DATE)
test_mask = df_valid['time'] >= TEST_START_DATE

df_train = df_valid[train_mask].copy()
df_calib = df_valid[calib_mask].copy()
df_test = df_valid[test_mask].copy()

print(f"\nTrain: {len(df_train)} lignes ({df_train['time'].min()} -> {df_train['time'].max()})")
print(f"Calib: {len(df_calib)} lignes ({df_calib['time'].min()} -> {df_calib['time'].max()})")
print(f"Test: {len(df_test)} lignes ({df_test['time'].min()} -> {df_test['time'].max()})")

# ==================== EQUILIBRAGE TRAIN ====================
print("\n" + "=" * 80)
print("EQUILIBRAGE TRAIN")
print("=" * 80)

df_train_win = df_train[df_train['target_binary'] == 1]
df_train_loss = df_train[df_train['target_binary'] == 0]

n_samples = min(len(df_train_win), len(df_train_loss))
df_train_loss_sampled = df_train_loss.sample(n=n_samples, random_state=42)
df_train_balanced = pd.concat([df_train_win, df_train_loss_sampled], ignore_index=True)
df_train_balanced = df_train_balanced.sample(frac=1, random_state=42).reset_index(drop=True)

print(f"Train equilibre: {len(df_train_balanced)} lignes")

# Preparer donnees
X_train = df_train_balanced[feature_cols].replace([np.inf, -np.inf], np.nan).fillna(0)
y_train = df_train_balanced['target_binary']

X_calib = df_calib[feature_cols].replace([np.inf, -np.inf], np.nan).fillna(0)
y_calib = df_calib['target_binary']

# ==================== ENTRAINEMENT BASE MODELS ====================
print("\n" + "=" * 80)
print("ENTRAINEMENT MODELES DE BASE")
print("=" * 80)

# LightGBM
print("\n[1/3] LightGBM...")
lgbm_model = lgb.LGBMClassifier(
    objective='binary',
    boosting_type='gbdt',
    num_leaves=30,  # Réduire complexité
    learning_rate=0.03,  # Plus lent
    feature_fraction=0.7,
    bagging_fraction=0.7,
    min_child_samples=50,  # Plus conservateur
    max_depth=5,  # Moins profond
    lambda_l1=0.5,  # Plus de régularisation
    lambda_l2=0.5,
    verbosity=-1,
    random_state=42,
    n_estimators=300
)
lgbm_model.fit(X_train, y_train)
print(f"   OK")

# XGBoost
print("[2/3] XGBoost...")
xgb_model = xgb.XGBClassifier(
    objective='binary:logistic',
    max_depth=5,
    learning_rate=0.03,
    subsample=0.7,
    colsample_bytree=0.7,
    min_child_weight=50,
    reg_alpha=0.5,
    reg_lambda=0.5,
    random_state=42,
    n_estimators=300,
    tree_method='hist'
)
xgb_model.fit(X_train, y_train)
print(f"   OK")

# CatBoost
print("[3/3] CatBoost...")
cat_model = cb.CatBoostClassifier(
    iterations=300,
    learning_rate=0.03,
    depth=5,
    l2_leaf_reg=0.5,
    subsample=0.7,
    random_seed=42,
    verbose=False
)
cat_model.fit(X_train, y_train)
print(f"   OK")

# ==================== CALIBRATION ====================
print("\n" + "=" * 80)
print("CALIBRATION DES PROBABILITES (ISOTONIC)")
print("=" * 80)

print("\nCalibration en cours...")

# Calibrer chaque modèle individuellement
lgbm_calibrated = CalibratedClassifierCV(
    lgbm_model,
    method='isotonic',  # Meilleur pour les tree models
    cv='prefit'  # On a déjà fit le modèle
)
lgbm_calibrated.fit(X_calib, y_calib)
print("   [1/3] LightGBM calibré")

xgb_calibrated = CalibratedClassifierCV(
    xgb_model,
    method='isotonic',
    cv='prefit'
)
xgb_calibrated.fit(X_calib, y_calib)
print("   [2/3] XGBoost calibré")

cat_calibrated = CalibratedClassifierCV(
    cat_model,
    method='isotonic',
    cv='prefit'
)
cat_calibrated.fit(X_calib, y_calib)
print("   [3/3] CatBoost calibré")

# ==================== VERIFICATION CALIBRATION ====================
print("\n" + "=" * 80)
print("VERIFICATION CALIBRATION SUR DONNEES CALIB")
print("=" * 80)

def check_calibration(model, X, y, name):
    proba = model.predict_proba(X)[:, 1]

    # Brier score (plus bas = mieux calibré)
    brier = brier_score_loss(y, proba)

    # Calibration par bins
    bins = [0.499, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.90, 1.0]
    df_temp = pd.DataFrame({'proba': proba, 'actual': y})
    df_temp['bin'] = pd.cut(df_temp['proba'], bins=bins)

    print(f"\n{name}:")
    print(f"   Brier Score: {brier:.4f} (plus bas = mieux)")
    print(f"   Bin            Predicted %  Actual %    Ecart")
    print(f"   " + "-" * 50)

    total_error = 0
    n_bins = 0

    for bin_range in df_temp['bin'].unique():
        if pd.notna(bin_range):
            bin_data = df_temp[df_temp['bin'] == bin_range]
            if len(bin_data) > 10:  # Au moins 10 samples
                pred_avg = bin_data['proba'].mean() * 100
                actual_wr = bin_data['actual'].mean() * 100
                error = abs(pred_avg - actual_wr)
                total_error += error
                n_bins += 1
                print(f"   {str(bin_range):<15} {pred_avg:<12.1f} {actual_wr:<12.1f} {error:.1f}")

    mae = total_error / n_bins if n_bins > 0 else 0
    print(f"\n   MAE Calibration: {mae:.1f} points")
    return mae

# Vérifier avant/après calibration
print("\nAVANT CALIBRATION:")
mae_before = check_calibration(lgbm_model, X_calib, y_calib, "LightGBM")

print("\nAPRES CALIBRATION:")
mae_after = check_calibration(lgbm_calibrated, X_calib, y_calib, "LightGBM Calibré")

improvement = mae_before - mae_after
print(f"\nAmélioration: {improvement:.1f} points de MAE")

# ==================== ENSEMBLE CALIBRE ====================
print("\n" + "=" * 80)
print("CREATION ENSEMBLE CALIBRE")
print("=" * 80)

# Créer ensemble avec modèles calibrés
ensemble_calibrated = VotingClassifier(
    estimators=[
        ('lgbm', lgbm_calibrated),
        ('xgb', xgb_calibrated),
        ('cat', cat_calibrated)
    ],
    voting='soft',
    weights=[1, 1, 1]  # Poids égaux pour simplicité
)

# Simuler le fit (déjà fait)
ensemble_calibrated.estimators_ = [lgbm_calibrated, xgb_calibrated, cat_calibrated]
ensemble_calibrated.classes_ = np.array([0, 1])

print("OK: Ensemble calibré créé")

# Vérifier calibration de l'ensemble
mae_ensemble = check_calibration(ensemble_calibrated, X_calib, y_calib, "Ensemble Calibré")

# ==================== BACKTEST ====================
print("\n" + "=" * 80)
print("BACKTEST SUR DONNEES TEST")
print("=" * 80)

X_test = df_test[feature_cols].replace([np.inf, -np.inf], np.nan).fillna(0)

print("\nPrediction...")
y_pred_proba = ensemble_calibrated.predict_proba(X_test)[:, 1]

signals_mask = y_pred_proba >= PROBABILITY_THRESHOLD
df_signals = df_test[signals_mask].copy()
df_signals['predicted_proba'] = y_pred_proba[signals_mask]

print(f"OK: {len(df_signals)} signaux >= {PROBABILITY_THRESHOLD:.0%}")

# Simulation trades
print("\nSimulation trades...")
trades = []

for idx, row in tqdm(df_signals.iterrows(), total=len(df_signals)):
    entry_time = row['time']
    entry_price = row['close']
    signal_proba = row['predicted_proba']
    signal_score = row['signal_score']

    sl_price = row['sl_price']
    tp_price = row['tp_price']
    atr = row['atr14']

    if signal_score >= 2:
        direction = 1
    elif signal_score <= -2:
        direction = -1
    else:
        continue

    future_bars = df_test[df_test['time'] > entry_time].head(180)
    if len(future_bars) == 0:
        continue

    sl_distance = abs(sl_price - entry_price)
    be_activated = False
    trade_result = None
    exit_price = None
    bars_held = 0

    for fb_idx, fb_row in future_bars.iterrows():
        bars_held += 1

        if direction > 0:
            if fb_row['low'] <= sl_price:
                trade_result = 'LOSS'
                exit_price = sl_price
                break
            if fb_row['high'] >= tp_price:
                trade_result = 'WIN'
                exit_price = tp_price
                break
        else:
            if fb_row['high'] >= sl_price:
                trade_result = 'LOSS'
                exit_price = sl_price
                break
            if fb_row['low'] <= tp_price:
                trade_result = 'WIN'
                exit_price = tp_price
                break

    if trade_result is None:
        exit_price = future_bars.iloc[-1]['close']
        bars_held = len(future_bars)
        pnl_pct = (exit_price - entry_price) / entry_price * 100
        if direction == -1:
            pnl_pct = -pnl_pct
        trade_result = 'WIN' if pnl_pct > 0 else 'LOSS'

    pnl_pct = (exit_price - entry_price) / entry_price * 100
    if direction == -1:
        pnl_pct = -pnl_pct

    pnl_usd = RISK_PER_TRADE * (pnl_pct / (sl_distance / entry_price * 100))

    trades.append({
        'entry_time': entry_time,
        'entry_price': entry_price,
        'exit_price': exit_price,
        'direction': direction,
        'signal_proba': signal_proba,
        'result': trade_result,
        'pnl_pct': pnl_pct,
        'pnl_usd': pnl_usd,
        'bars_held': bars_held,
        'be_activated': be_activated,
        'tp_price': tp_price,
        'sl_price_initial': row['sl_price'],
        'atr': atr
    })

df_trades = pd.DataFrame(trades)

# ==================== RESULTATS ====================
print("\n" + "=" * 80)
print("RESULTATS BACKTEST V3.0 CALIBRE")
print("=" * 80)

n_wins = (df_trades['result'] == 'WIN').sum()
win_rate = n_wins / len(df_trades) * 100

total_pnl = df_trades['pnl_usd'].sum()
initial_capital = 10000
return_pct = (total_pnl / initial_capital) * 100

print(f"\nTrades: {len(df_trades)}")
print(f"Win Rate: {win_rate:.2f}%")
print(f"P&L: ${total_pnl:,.2f}")
print(f"Return: {return_pct:.2f}%")

# Vérifier calibration sur résultats backtest
print("\n" + "=" * 80)
print("CALIBRATION SUR BACKTEST")
print("=" * 80)

df_trades['actual_win'] = (df_trades['result'] == 'WIN').astype(int)
mae_backtest = check_calibration(
    type('obj', (object,), {
        'predict_proba': lambda self, X: np.column_stack([1-df_trades['signal_proba'].values, df_trades['signal_proba'].values])
    })(),
    None,
    df_trades['actual_win'],
    "Backtest"
)

# ==================== SAUVEGARDE ====================
print("\n" + "=" * 80)
print("SAUVEGARDE")
print("=" * 80)

output_path = os.path.join(base_path, OUTPUT_MODEL)

model_data = {
    'ensemble': ensemble_calibrated,
    'feature_cols': feature_cols,
    'version': '3.0_CALIBRATED',
    'training_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'calibration_mae': mae_ensemble,
    'backtest_mae': mae_backtest,
    'backtest_results': {
        'win_rate': win_rate,
        'total_pnl': total_pnl,
        'n_trades': len(df_trades)
    }
}

joblib.dump(model_data, output_path)
print(f"OK: Modèle sauvegardé: {output_path}")

trades_path = os.path.join(base_path, 'backtest_v3_calibrated_trades.csv')
df_trades.to_csv(trades_path, index=False)
print(f"OK: Trades sauvegardés: {trades_path}")

print("\n" + "=" * 80)
print("TERMINE - MODELE V3.0 CALIBRE")
print("=" * 80)
print(f"\nCalibration MAE: {mae_ensemble:.1f} points (vs {mae_before:.1f} avant)")
print(f"Win Rate: {win_rate:.2f}%")
print(f"Return: {return_pct:.2f}%")
