"""
Entraînement Ensemble V2.0 avec TP/SL dynamiques (ATR)
Version avec Break Even à 1R

Version 2.0 - 2025-10-10

OBJECTIF:
- Utiliser les nouvelles données avec TP/SL basés sur ATR
- Entraîner modèle Ensemble (LightGBM + XGBoost + CatBoost)
- Backtest réaliste avec vérification TP/SL barre par barre
- Intégrer Break Even à 1R dans la simulation
"""

import pandas as pd
import numpy as np
import lightgbm as lgb
import xgboost as xgb
import catboost as cb
from sklearn.ensemble import VotingClassifier
from sklearn.metrics import roc_auc_score, classification_report, confusion_matrix
import joblib
import os
from datetime import datetime
from tqdm import tqdm

print("=" * 80)
print("ENTRAINEMENT ENSEMBLE V2.0 - TP/SL DYNAMIQUES (ATR)")
print("=" * 80)

# ==================== CONFIGURATION ====================
DATA_CSV = "XAUUSD_ML_Data_V2_ATR_20Y.csv"
OUTPUT_MODEL = "xauusd_ensemble_v2_atr_model.pkl"

# Split temporel
TRAIN_END_DATE = "2020-12-31"
TEST_START_DATE = "2021-01-01"

# Paramètres trading (pour backtest)
PROBABILITY_THRESHOLD = 0.50
RISK_PER_TRADE = 100
USE_BREAK_EVEN = False

print(f"\nConfiguration:")
print(f"   Donnees: {DATA_CSV}")
print(f"   Train: jusqu'a {TRAIN_END_DATE}")
print(f"   Test: a partir de {TEST_START_DATE}")
print(f"   Threshold: {PROBABILITY_THRESHOLD:.0%}")
print(f"   Break Even: {'OUI' if USE_BREAK_EVEN else 'NON'}")

# ==================== CHARGEMENT ====================
print("\n" + "=" * 80)
print("CHARGEMENT DONNEES")
print("=" * 80)

base_path = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
csv_path = os.path.join(base_path, DATA_CSV)

if not os.path.exists(csv_path):
    print(f"ERREUR: Fichier introuvable: {csv_path}")
    exit(1)

df = pd.read_csv(csv_path)
df['time'] = pd.to_datetime(df['time'])
df = df.sort_values('time').reset_index(drop=True)

print(f"OK: {len(df)} lignes chargees")
print(f"   Periode: {df['time'].min()} -> {df['time'].max()}")

# Vérifier les colonnes
required_cols = ['target_binary', 'target_pct_change', 'sl_price', 'tp_price', 'atr14']
missing = [col for col in required_cols if col not in df.columns]
if missing:
    print(f"ERREUR: Colonnes manquantes: {missing}")
    exit(1)

# Filtrer target valide (0 ou 1, exclure -1)
df_valid = df[df['target_binary'].isin([0, 1])].copy()
print(f"OK: {len(df_valid)} lignes avec target valide (0 ou 1)")
print(f"   Distribution target:")
print(f"      WIN (1):  {(df_valid['target_binary']==1).sum()} ({(df_valid['target_binary']==1).sum()/len(df_valid)*100:.1f}%)")
print(f"      LOSS (0): {(df_valid['target_binary']==0).sum()} ({(df_valid['target_binary']==0).sum()/len(df_valid)*100:.1f}%)")

# ==================== PREPARATION FEATURES ====================
print("\n" + "=" * 80)
print("PREPARATION FEATURES")
print("=" * 80)

# Exclure colonnes non-features
exclude_cols = ['time', 'target_binary', 'target_pct_change', 'sl_price', 'tp_price',
                'open', 'high', 'low', 'close']
feature_cols = [col for col in df_valid.columns if col not in exclude_cols]

print(f"OK: {len(feature_cols)} features")

# ==================== SPLIT TEMPOREL ====================
print("\n" + "=" * 80)
print("SPLIT TEMPOREL STRICT")
print("=" * 80)

train_mask = df_valid['time'] <= TRAIN_END_DATE
test_mask = df_valid['time'] >= TEST_START_DATE

df_train = df_valid[train_mask].copy()
df_test = df_valid[test_mask].copy()

print(f"\nTrain:")
print(f"   {len(df_train)} lignes")
print(f"   Periode: {df_train['time'].min()} -> {df_train['time'].max()}")

print(f"\nTest:")
print(f"   {len(df_test)} lignes")
print(f"   Periode: {df_test['time'].min()} -> {df_test['time'].max()}")

# ==================== EQUILIBRAGE ====================
print("\n" + "=" * 80)
print("EQUILIBRAGE DONNEES TRAIN")
print("=" * 80)

df_train_win = df_train[df_train['target_binary'] == 1].copy()
df_train_loss = df_train[df_train['target_binary'] == 0].copy()

print(f"\nAvant equilibrage:")
print(f"   WIN: {len(df_train_win)}")
print(f"   LOSS: {len(df_train_loss)}")

# Undersampling
n_samples = min(len(df_train_win), len(df_train_loss))
df_train_loss_sampled = df_train_loss.sample(n=n_samples, random_state=42)
df_train_balanced = pd.concat([df_train_win, df_train_loss_sampled], ignore_index=True)
df_train_balanced = df_train_balanced.sample(frac=1, random_state=42).reset_index(drop=True)

print(f"\nApres equilibrage: {len(df_train_balanced)} lignes")

# Preparer X, y
X_train = df_train_balanced[feature_cols].copy()
y_train = df_train_balanced['target_binary'].copy()
X_train = X_train.replace([np.inf, -np.inf], np.nan).fillna(0)

# ==================== ENTRAINEMENT ENSEMBLE ====================
print("\n" + "=" * 80)
print("ENTRAINEMENT ENSEMBLE (LightGBM + XGBoost + CatBoost)")
print("=" * 80)

# Split interne train/val
split_val = int(len(X_train) * 0.8)
X_train_fit = X_train.iloc[:split_val]
y_train_fit = y_train.iloc[:split_val]
X_val = X_train.iloc[split_val:]
y_val = y_train.iloc[split_val:]

print(f"   Train fit: {len(X_train_fit)} | Validation: {len(X_val)}")

# 1. LightGBM
print("\n   [1/3] LightGBM...")
lgbm_model = lgb.LGBMClassifier(
    objective='binary',
    metric='auc',
    boosting_type='gbdt',
    num_leaves=50,
    learning_rate=0.05,
    feature_fraction=0.8,
    bagging_fraction=0.8,
    bagging_freq=5,
    min_child_samples=20,
    max_depth=7,
    lambda_l1=0.1,
    lambda_l2=0.1,
    verbosity=-1,
    random_state=42,
    n_estimators=500
)
lgbm_model.fit(
    X_train_fit, y_train_fit,
    eval_set=[(X_val, y_val)],
    callbacks=[lgb.early_stopping(stopping_rounds=50, verbose=False)]
)
lgbm_pred = lgbm_model.predict_proba(X_val)[:, 1]
lgbm_auc = roc_auc_score(y_val, lgbm_pred)
print(f"      AUC: {lgbm_auc:.4f}")

# 2. XGBoost
print("   [2/3] XGBoost...")
xgb_model = xgb.XGBClassifier(
    objective='binary:logistic',
    eval_metric='auc',
    max_depth=7,
    learning_rate=0.05,
    subsample=0.8,
    colsample_bytree=0.8,
    min_child_weight=20,
    reg_alpha=0.1,
    reg_lambda=0.1,
    random_state=42,
    n_estimators=500,
    tree_method='hist',
    early_stopping_rounds=50
)
xgb_model.fit(
    X_train_fit, y_train_fit,
    eval_set=[(X_val, y_val)],
    verbose=False
)
xgb_pred = xgb_model.predict_proba(X_val)[:, 1]
xgb_auc = roc_auc_score(y_val, xgb_pred)
print(f"      AUC: {xgb_auc:.4f}")

# 3. CatBoost
print("   [3/3] CatBoost...")
cat_model = cb.CatBoostClassifier(
    iterations=500,
    learning_rate=0.05,
    depth=7,
    l2_leaf_reg=0.1,
    subsample=0.8,
    random_seed=42,
    verbose=False,
    loss_function='Logloss',
    eval_metric='AUC'
)
cat_model.fit(
    X_train_fit, y_train_fit,
    eval_set=(X_val, y_val),
    early_stopping_rounds=50,
    verbose=False
)
cat_pred = cat_model.predict_proba(X_val)[:, 1]
cat_auc = roc_auc_score(y_val, cat_pred)
print(f"      AUC: {cat_auc:.4f}")

# Créer Voting Ensemble
total_auc = lgbm_auc + xgb_auc + cat_auc
lgbm_weight = lgbm_auc / total_auc
xgb_weight = xgb_auc / total_auc
cat_weight = cat_auc / total_auc

print(f"\n   Poids calcules:")
print(f"      LightGBM: {lgbm_weight:.3f}")
print(f"      XGBoost:  {xgb_weight:.3f}")
print(f"      CatBoost: {cat_weight:.3f}")

ensemble = VotingClassifier(
    estimators=[
        ('lgbm', lgbm_model),
        ('xgb', xgb_model),
        ('cat', cat_model)
    ],
    voting='soft',
    weights=[lgbm_weight, xgb_weight, cat_weight]
)

ensemble.estimators_ = [lgbm_model, xgb_model, cat_model]
ensemble.classes_ = np.array([0, 1])

ensemble_pred = ensemble.predict_proba(X_val)[:, 1]
ensemble_auc = roc_auc_score(y_val, ensemble_pred)

print(f"\nOK: Ensemble entraine - AUC validation: {ensemble_auc:.4f}")

# ==================== BACKTEST REALISTE ====================
print("\n" + "=" * 80)
print("BACKTEST REALISTE AVEC TP/SL DYNAMIQUES (ATR)")
print("=" * 80)

# Préparer données test
X_test = df_test[feature_cols].copy()
X_test = X_test.replace([np.inf, -np.inf], np.nan).fillna(0)

print("\nPrediction en cours...")
y_pred_proba = ensemble.predict_proba(X_test)[:, 1]

# Filtrer signaux >= threshold
signals_mask = y_pred_proba >= PROBABILITY_THRESHOLD
df_signals = df_test[signals_mask].copy()
df_signals['predicted_proba'] = y_pred_proba[signals_mask]

print(f"OK: {len(df_signals)} signaux avec probabilite >={PROBABILITY_THRESHOLD:.0%}")
print(f"    Sur {len(df_test)} barres de test ({len(df_signals)/len(df_test)*100:.1f}%)")

# Créer index pour lookups rapides
df_test_indexed = df_test.set_index('time')

# Simulation trade par trade
print("\nSimulation trade par trade...")
trades = []

for idx, row in tqdm(df_signals.iterrows(), total=len(df_signals), desc="Trades"):
    entry_time = row['time']
    entry_price = row['close']
    signal_proba = row['predicted_proba']
    signal_score = row['signal_score']

    # TP/SL basés sur ATR (déjà calculés dans le CSV)
    sl_price = row['sl_price']
    tp_price = row['tp_price']
    atr = row['atr14']

    # Direction basée sur signal_score
    if signal_score >= 2:
        direction = 1  # BUY
    elif signal_score <= -2:
        direction = -1  # SELL
    else:
        continue  # Pas de signal clair

    # Chercher les barres suivantes
    future_bars = df_test[df_test['time'] > entry_time].head(180)

    if len(future_bars) == 0:
        continue

    # Break Even level
    sl_distance = abs(sl_price - entry_price)
    if direction > 0:
        be_level = entry_price + sl_distance  # +1R pour BUY
    else:
        be_level = entry_price - sl_distance  # +1R pour SELL

    be_activated = False
    trade_result = None
    exit_price = None
    bars_held = 0

    # Vérifier barre par barre
    for fb_idx, fb_row in future_bars.iterrows():
        bars_held += 1

        if direction > 0:
            # BUY: Check BE
            if USE_BREAK_EVEN and not be_activated and fb_row['high'] >= be_level:
                sl_price = entry_price  # Move SL to BE
                be_activated = True

            # Check SL
            if fb_row['low'] <= sl_price:
                if be_activated:
                    trade_result = 'WIN'  # BE protected
                    exit_price = entry_price
                else:
                    trade_result = 'LOSS'
                    exit_price = sl_price
                break

            # Check TP
            if fb_row['high'] >= tp_price:
                trade_result = 'WIN'
                exit_price = tp_price
                break
        else:
            # SELL: Check BE
            if USE_BREAK_EVEN and not be_activated and fb_row['low'] <= be_level:
                sl_price = entry_price  # Move SL to BE
                be_activated = True

            # Check SL
            if fb_row['high'] >= sl_price:
                if be_activated:
                    trade_result = 'WIN'  # BE protected
                    exit_price = entry_price
                else:
                    trade_result = 'LOSS'
                    exit_price = sl_price
                break

            # Check TP
            if fb_row['low'] <= tp_price:
                trade_result = 'WIN'
                exit_price = tp_price
                break

    # Si ni TP ni SL atteint
    if trade_result is None:
        exit_price = future_bars.iloc[-1]['close']
        bars_held = len(future_bars)
        pnl_pct = (exit_price - entry_price) / entry_price * 100
        if direction == -1:
            pnl_pct = -pnl_pct
        trade_result = 'WIN' if pnl_pct > 0 else 'LOSS'

    # Calculer P&L
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

print(f"\nOK: Simulation terminee - {len(df_trades)} trades")

# ==================== ANALYSE RESULTATS ====================
print("\n" + "=" * 80)
print("RESULTATS BACKTEST V2.0")
print("=" * 80)

if len(df_trades) == 0:
    print("\nERREUR: Aucun trade simule")
    exit(0)

n_wins = (df_trades['result'] == 'WIN').sum()
n_losses = (df_trades['result'] == 'LOSS').sum()
win_rate = n_wins / len(df_trades) * 100

total_pnl = df_trades['pnl_usd'].sum()
total_gains = df_trades[df_trades['pnl_usd'] > 0]['pnl_usd'].sum()
total_losses = abs(df_trades[df_trades['pnl_usd'] < 0]['pnl_usd'].sum())

profit_factor = total_gains / total_losses if total_losses > 0 else 0
avg_win = df_trades[df_trades['result'] == 'WIN']['pnl_usd'].mean() if n_wins > 0 else 0
avg_loss = df_trades[df_trades['result'] == 'LOSS']['pnl_usd'].mean() if n_losses > 0 else 0
avg_bars_held = df_trades['bars_held'].mean()

# Break Even stats
n_be = df_trades['be_activated'].sum()
n_be_saved = len(df_trades[(df_trades['be_activated']) & (df_trades['result'] == 'WIN')])

print(f"\nPerformance Globale:")
print(f"   Nombre de trades: {len(df_trades)}")
print(f"   Trades gagnants: {n_wins}")
print(f"   Trades perdants: {n_losses}")
print(f"   Win Rate: {win_rate:.2f}%")

print(f"\nBreak Even:")
print(f"   BE active: {n_be} fois ({n_be/len(df_trades)*100:.1f}% des trades)")
print(f"   BE protege (sortie a BE): {n_be_saved}")

print(f"\nResultats Financiers:")
print(f"   P&L Net: ${total_pnl:,.2f}")
print(f"   Gains totaux: ${total_gains:,.2f}")
print(f"   Pertes totales: ${total_losses:,.2f}")
print(f"   Profit Factor: {profit_factor:.2f}x")
print(f"   Avg Win: ${avg_win:.2f}")
print(f"   Avg Loss: ${avg_loss:.2f}")
print(f"   Avg $/trade: ${total_pnl/len(df_trades):.2f}")

print(f"\nDuree moyenne: {avg_bars_held:.1f} barres H1 ({avg_bars_held/24:.1f} jours)")

initial_capital = 10000
return_pct = (total_pnl / initial_capital) * 100
print(f"\nReturn sur $10,000: {return_pct:.2f}%")
print(f"Capital final: ${initial_capital + total_pnl:,.2f}")

# ==================== SAUVEGARDE ====================
print("\n" + "=" * 80)
print("SAUVEGARDE MODELE")
print("=" * 80)

output_path = os.path.join(base_path, OUTPUT_MODEL)

model_data = {
    'ensemble': ensemble,
    'lgbm_model': lgbm_model,
    'xgb_model': xgb_model,
    'cat_model': cat_model,
    'feature_cols': feature_cols,
    'weights': [lgbm_weight, xgb_weight, cat_weight],
    'ensemble_auc': ensemble_auc,
    'training_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'version': '2.0_ATR',
    'use_break_even': USE_BREAK_EVEN,
    'threshold': PROBABILITY_THRESHOLD,
    'backtest_results': {
        'win_rate': win_rate,
        'profit_factor': profit_factor,
        'total_pnl': total_pnl,
        'n_trades': len(df_trades)
    }
}

joblib.dump(model_data, output_path)
print(f"OK: Modele sauvegarde: {output_path}")

# Sauvegarder trades
trades_path = os.path.join(base_path, 'backtest_v2_atr_trades.csv')
df_trades.to_csv(trades_path, index=False)
print(f"OK: Trades sauvegardes: {trades_path}")

print("\n" + "=" * 80)
print("ENTRAINEMENT ET BACKTEST TERMINES")
print("=" * 80)

print(f"\nResume:")
print(f"   AUC validation: {ensemble_auc:.4f}")
print(f"   Win Rate: {win_rate:.2f}%")
print(f"   Profit Factor: {profit_factor:.2f}x")
print(f"   Return: {return_pct:.2f}%")
print(f"   BE active: {n_be/len(df_trades)*100:.1f}% des trades")

if win_rate >= 55 and profit_factor >= 1.5:
    print(f"\nOK: Performance prometteuse!")
    print(f"   -> Pret pour tests supplementaires")
elif win_rate >= 50 and profit_factor >= 1.2:
    print(f"\nWARNING: Performance acceptable")
    print(f"   -> Peut etre ameliore")
else:
    print(f"\nWARNING: Performance insuffisante")
    print(f"   -> Revoir parametres TP/SL ou features")

print("\n" + "=" * 80)
