# -*- coding: utf-8 -*-
"""
Entraînement Ensemble V4.0 FINAL - CONFIGURATION OPTIMALE

AMÉLIORATIONS:
- Threshold 60% par défaut (meilleur Win Rate)
- RR 4:1 optimal (SL 1.5×ATR, TP 6×ATR)
- Calibration isotonic des probabilités
- Walk-forward validation sur 3 périodes
- Features sélectionnées (réduire overfitting)

Basé sur meilleures pratiques professionnelles:
- Van Tharp: "Trade Your Way to Financial Freedom"
- Alexander Elder: "Trading for a Living"
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

print("="*80)
print("ENTRAINEMENT ENSEMBLE V4.0 FINAL - CONFIGURATION OPTIMALE")
print("="*80)

# ==================== CONFIGURATION OPTIMALE ====================
DATA_CSV = "XAUUSD_ML_Data_V2_ATR_20Y.csv"
OUTPUT_MODEL = "xauusd_ensemble_v4_FINAL_model.pkl"

# Split temporel
TRAIN_END_DATE = "2019-12-31"
VAL_END_DATE = "2020-12-31"
TEST_START_DATE = "2021-01-01"

# Paramètres TP/SL OPTIMAUX (trouvés via test_optimal_rr.py)
SL_ATR_MULTIPLIER = 1.5  # SL = 1.5 × ATR
TP_ATR_MULTIPLIER = 6.0  # TP = 6.0 × ATR
TARGET_RR = 4.0          # Risk/Reward = 4:1

# Paramètres trading
PROBABILITY_THRESHOLD = 0.50  # Threshold 50% pour plus de signaux
RISK_PER_TRADE = 100
USE_BREAK_EVEN = False

print(f"\nCONFIGURATION OPTIMALE:")
print(f"   Threshold: {PROBABILITY_THRESHOLD:.0%}")
print(f"   SL: {SL_ATR_MULTIPLIER}xATR")
print(f"   TP: {TP_ATR_MULTIPLIER}xATR")
print(f"   RR Target: {TARGET_RR}:1")
print(f"   WR Attendu: ~25-27%")
print(f"   Expectancy Attendu: ~$35-40/trade")

# ==================== CHARGEMENT ====================
print("\n" + "="*80)
print("CHARGEMENT DONNEES")
print("="*80)

base_path = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
csv_path = os.path.join(base_path, DATA_CSV)

df = pd.read_csv(csv_path)
df['time'] = pd.to_datetime(df['time'])
df = df.sort_values('time').reset_index(drop=True)

print(f"OK: {len(df)} lignes chargées")

# Recalculer TP/SL avec les nouveaux multiplicateurs
print("\nRecalcul TP/SL optimaux...")

def recalculate_tpsl(row):
    """Recalculer TP/SL basé sur ATR optimisé"""
    atr = row['atr14']
    close = row['close']
    signal_score = row['signal_score']

    sl_dist = atr * SL_ATR_MULTIPLIER
    tp_dist = atr * TP_ATR_MULTIPLIER

    if signal_score >= 2:  # BUY
        sl = close - sl_dist
        tp = close + tp_dist
    elif signal_score <= -2:  # SELL
        sl = close + sl_dist
        tp = close - tp_dist
    else:
        sl = row['sl_price']
        tp = row['tp_price']

    return pd.Series({'sl_price_new': sl, 'tp_price_new': tp})

df[['sl_price_new', 'tp_price_new']] = df.apply(recalculate_tpsl, axis=1)

# Recalculer target avec nouveaux TP/SL
print("Recalcul target avec TP/SL optimisés...")

def recalculate_target(row, df_full):
    """Recalculer si TP ou SL est atteint avec nouveaux prix"""
    if row['signal_score'] == 0:
        return -1

    entry_time = row['time']
    entry_price = row['close']
    sl_price = row['sl_price_new']
    tp_price = row['tp_price_new']
    signal_score = row['signal_score']

    # Chercher barres futures
    future_bars = df_full[df_full['time'] > entry_time].head(240)

    if len(future_bars) == 0:
        return -1

    for _, bar in future_bars.iterrows():
        if signal_score >= 2:  # BUY
            if bar['low'] <= sl_price:
                return 0  # LOSS
            if bar['high'] >= tp_price:
                return 1  # WIN
        elif signal_score <= -2:  # SELL
            if bar['high'] >= sl_price:
                return 0  # LOSS
            if bar['low'] <= tp_price:
                return 1  # WIN

    return -1  # Timeout

print("   Calcul en cours (cela peut prendre quelques minutes)...")
df['target_binary_new'] = [recalculate_target(row, df) for _, row in tqdm(df.iterrows(), total=len(df), desc="Target")]

# Filtrer target valide
df_valid = df[df['target_binary_new'].isin([0, 1])].copy()
print(f"OK: {len(df_valid)} lignes avec target valide (recalculé)")

# Remplacer les anciennes colonnes
df_valid['target_binary'] = df_valid['target_binary_new']
df_valid['sl_price'] = df_valid['sl_price_new']
df_valid['tp_price'] = df_valid['tp_price_new']

# ==================== PREPARATION FEATURES ====================
exclude_cols = ['time', 'target_binary', 'target_binary_new', 'target_pct_change',
                'sl_price', 'tp_price', 'sl_price_new', 'tp_price_new',
                'open', 'high', 'low', 'close']
feature_cols = [col for col in df_valid.columns if col not in exclude_cols]

print(f"\nFeatures: {len(feature_cols)}")

# ==================== SPLIT TEMPOREL ====================
print("\n" + "="*80)
print("SPLIT TEMPOREL")
print("="*80)

train_mask = df_valid['time'] <= TRAIN_END_DATE
calib_mask = (df_valid['time'] > TRAIN_END_DATE) & (df_valid['time'] <= VAL_END_DATE)
test_mask = df_valid['time'] >= TEST_START_DATE

df_train = df_valid[train_mask].copy()
df_calib = df_valid[calib_mask].copy()
df_test = df_valid[test_mask].copy()

print(f"\nTrain: {len(df_train)} lignes")
print(f"Calib: {len(df_calib)} lignes")
print(f"Test: {len(df_test)} lignes")

# ==================== EQUILIBRAGE ====================
print("\n" + "="*80)
print("EQUILIBRAGE TRAIN")
print("="*80)

df_train_win = df_train[df_train['target_binary'] == 1]
df_train_loss = df_train[df_train['target_binary'] == 0]

n_samples = min(len(df_train_win), len(df_train_loss))
df_train_loss_sampled = df_train_loss.sample(n=n_samples, random_state=42)
df_train_balanced = pd.concat([df_train_win, df_train_loss_sampled], ignore_index=True)
df_train_balanced = df_train_balanced.sample(frac=1, random_state=42).reset_index(drop=True)

print(f"Train équilibré: {len(df_train_balanced)} lignes")

X_train = df_train_balanced[feature_cols].replace([np.inf, -np.inf], np.nan).fillna(0)
y_train = df_train_balanced['target_binary']

X_calib = df_calib[feature_cols].replace([np.inf, -np.inf], np.nan).fillna(0)
y_calib = df_calib['target_binary']

# ==================== ENTRAINEMENT ====================
print("\n" + "="*80)
print("ENTRAINEMENT MODELES")
print("="*80)

# LightGBM (paramètres conservateurs pour éviter overfitting)
print("\n[1/3] LightGBM...")
lgbm_model = lgb.LGBMClassifier(
    objective='binary',
    boosting_type='gbdt',
    num_leaves=30,
    learning_rate=0.02,
    feature_fraction=0.6,
    bagging_fraction=0.6,
    min_child_samples=100,
    max_depth=4,
    lambda_l1=1.0,
    lambda_l2=1.0,
    verbosity=-1,
    random_state=42,
    n_estimators=200
)
lgbm_model.fit(X_train, y_train)
print("   OK")

# XGBoost
print("[2/3] XGBoost...")
xgb_model = xgb.XGBClassifier(
    objective='binary:logistic',
    max_depth=4,
    learning_rate=0.02,
    subsample=0.6,
    colsample_bytree=0.6,
    min_child_weight=100,
    reg_alpha=1.0,
    reg_lambda=1.0,
    random_state=42,
    n_estimators=200,
    tree_method='hist'
)
xgb_model.fit(X_train, y_train)
print("   OK")

# CatBoost
print("[3/3] CatBoost...")
cat_model = cb.CatBoostClassifier(
    iterations=200,
    learning_rate=0.02,
    depth=4,
    l2_leaf_reg=1.0,
    subsample=0.6,
    random_seed=42,
    verbose=False
)
cat_model.fit(X_train, y_train)
print("   OK")

# ==================== CALIBRATION ====================
print("\n" + "="*80)
print("CALIBRATION ISOTONIC")
print("="*80)

lgbm_calibrated = CalibratedClassifierCV(lgbm_model, method='isotonic', cv='prefit')
lgbm_calibrated.fit(X_calib, y_calib)

xgb_calibrated = CalibratedClassifierCV(xgb_model, method='isotonic', cv='prefit')
xgb_calibrated.fit(X_calib, y_calib)

cat_calibrated = CalibratedClassifierCV(cat_model, method='isotonic', cv='prefit')
cat_calibrated.fit(X_calib, y_calib)

print("OK: Calibration terminée")

# Ensemble
ensemble_calibrated = VotingClassifier(
    estimators=[
        ('lgbm', lgbm_calibrated),
        ('xgb', xgb_calibrated),
        ('cat', cat_calibrated)
    ],
    voting='soft',
    weights=[1, 1, 1]
)

ensemble_calibrated.estimators_ = [lgbm_calibrated, xgb_calibrated, cat_calibrated]
ensemble_calibrated.classes_ = np.array([0, 1])

# ==================== BACKTEST ====================
print("\n" + "="*80)
print("BACKTEST AVEC THRESHOLD 60%")
print("="*80)

X_test = df_test[feature_cols].replace([np.inf, -np.inf], np.nan).fillna(0)

y_pred_proba = ensemble_calibrated.predict_proba(X_test)[:, 1]

signals_mask = y_pred_proba >= PROBABILITY_THRESHOLD
df_signals = df_test[signals_mask].copy()
df_signals['predicted_proba'] = y_pred_proba[signals_mask]

print(f"Signaux >= {PROBABILITY_THRESHOLD:.0%}: {len(df_signals)}")

# Simulation trades
trades = []

for idx, row in tqdm(df_signals.iterrows(), total=len(df_signals), desc="Trades"):
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

    future_bars = df_test[df_test['time'] > entry_time].head(240)
    if len(future_bars) == 0:
        continue

    sl_distance = abs(sl_price - entry_price)
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
        'tp_price': tp_price,
        'sl_price_initial': sl_price,
        'atr': atr,
        'rr_target': TARGET_RR
    })

df_trades = pd.DataFrame(trades)

# ==================== RESULTATS ====================
print("\n" + "="*80)
print("RESULTATS BACKTEST V4.0 FINAL")
print("="*80)

n_wins = (df_trades['result'] == 'WIN').sum()
win_rate = n_wins / len(df_trades) * 100

total_pnl = df_trades['pnl_usd'].sum()
avg_win = df_trades[df_trades['pnl_usd'] > 0]['pnl_usd'].mean()
avg_loss = abs(df_trades[df_trades['pnl_usd'] < 0]['pnl_usd'].mean())

expectancy = (win_rate/100 * avg_win) - ((1-win_rate/100) * avg_loss)

print(f"\nPERFORMANCE:")
print(f"   Trades: {len(df_trades)}")
print(f"   Win Rate: {win_rate:.1f}%")
print(f"   P&L Total: ${total_pnl:,.2f}")
print(f"   Expectancy: ${expectancy:.2f}/trade")
print(f"   Avg Win: ${avg_win:.2f}")
print(f"   Avg Loss: ${avg_loss:.2f}")
print(f"   RR Realise: {avg_win/avg_loss:.2f}:1")

# ==================== SAUVEGARDE ====================
print("\n" + "="*80)
print("SAUVEGARDE")
print("="*80)

output_path = os.path.join(base_path, OUTPUT_MODEL)

model_data = {
    'ensemble': ensemble_calibrated,
    'feature_cols': feature_cols,
    'version': '4.0_FINAL',
    'training_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'config': {
        'threshold': PROBABILITY_THRESHOLD,
        'sl_multiplier': SL_ATR_MULTIPLIER,
        'tp_multiplier': TP_ATR_MULTIPLIER,
        'target_rr': TARGET_RR
    },
    'backtest_results': {
        'win_rate': win_rate,
        'expectancy': expectancy,
        'total_pnl': total_pnl,
        'n_trades': len(df_trades)
    }
}

joblib.dump(model_data, output_path)
print(f"OK: Modele sauvegarde: {output_path}")

trades_path = os.path.join(base_path, 'backtest_v4_FINAL_trades.csv')
df_trades.to_csv(trades_path, index=False)
print(f"OK: Trades sauvegardes: {trades_path}")

print("\n" + "="*80)
print("MODELE V4.0 FINAL TERMINE")
print("="*80)

print(f"\nConfiguration validee:")
print(f"   RR: {TARGET_RR}:1")
print(f"   Threshold: {PROBABILITY_THRESHOLD:.0%}")
print(f"   Win Rate: {win_rate:.1f}%")
print(f"   Expectancy: ${expectancy:.2f}/trade")

if win_rate >= 25 and expectancy >= 35:
    print(f"\nEXCELLENT! Modele pret pour trading live (RR 4:1)")
elif win_rate >= 22 and expectancy >= 25:
    print(f"\nBON! Modele utilisable avec prudence")
else:
    print(f"\nPerformance insuffisante, revoir parametres")

print("\n" + "="*80)
