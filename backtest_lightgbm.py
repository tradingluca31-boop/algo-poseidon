"""
Script de BACKTEST pour valider le modèle LightGBM
Simule les trades sur données historiques avec prédictions ML
Version 1.0 - 2025-10-09

OBJECTIF:
- Vérifier si True Win Rate de 82% est réel ou overfitting
- Calculer métriques réalistes (Profit Factor, Sharpe, Drawdown)
- Comparer avec stratégie "buy all signals"
"""

import pandas as pd
import numpy as np
import joblib
import os
from datetime import datetime
import matplotlib.pyplot as plt

print("=" * 80)
print("📊 BACKTEST MODÈLE LIGHTGBM")
print("=" * 80)

# ==================== CONFIGURATION ====================
DATA_CSV = "XAUUSD_COMPLETE_ML_Data.csv"
MODEL_FILE = "xauusd_lightgbm_balanced_model.pkl"

# Paramètres trading
INITIAL_CAPITAL = 10000  # Capital initial en USD
RISK_PER_TRADE = 100     # Risque par trade en USD (comme Poseidon)
SL_PERCENT = 0.35        # SL en % du prix
TP_PERCENT = 1.75        # TP en % du prix

# Période de test (out-of-sample)
# On teste sur les 20% dernières données (non vues pendant l'entraînement)
TEST_RATIO = 0.2

# Seuil de prédiction
PREDICTION_THRESHOLD = 0.25  # Probabilité minimum pour prendre un trade

# ==================== CHARGEMENT ====================
print("\n" + "=" * 80)
print("📂 CHARGEMENT MODÈLE ET DONNÉES")
print("=" * 80)

base_path = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
csv_path = os.path.join(base_path, DATA_CSV)
model_path = os.path.join(base_path, MODEL_FILE)

# Charger le modèle
print("🤖 Chargement du modèle...")
model_data = joblib.load(model_path)
model = model_data['model']
feature_cols = model_data['feature_cols']
print(f"✅ Modèle chargé ({len(feature_cols)} features)")

# Charger les données
print("\n📊 Chargement des données...")
df = pd.read_csv(csv_path)
df['time'] = pd.to_datetime(df['time'])
df = df.sort_values('time').reset_index(drop=True)

# Filtrer targets valides
df = df[df['target'].isin([0, 1])].copy()
print(f"✅ {len(df)} lignes chargées")

# Split train/test (temporel)
split_idx = int(len(df) * (1 - TEST_RATIO))
df_train = df.iloc[:split_idx].copy()
df_test = df.iloc[split_idx:].copy()

print(f"\n📅 Période de test (out-of-sample):")
print(f"   Train: {df_train['time'].min()} → {df_train['time'].max()}")
print(f"   Test:  {df_test['time'].min()} → {df_test['time'].max()}")
print(f"   Test:  {len(df_test)} barres ({len(df_test)/len(df)*100:.1f}% du dataset)")

# ==================== PRÉDICTIONS ====================
print("\n" + "=" * 80)
print("🔮 GÉNÉRATION PRÉDICTIONS ML")
print("=" * 80)

X_test = df_test[feature_cols].copy()
X_test = X_test.replace([np.inf, -np.inf], np.nan).fillna(0)

print("🚀 Prédiction en cours...")
y_pred_proba = model.predict(X_test, num_iteration=model.best_iteration)
y_pred = (y_pred_proba >= PREDICTION_THRESHOLD).astype(int)

df_test['ml_pred'] = y_pred
df_test['ml_proba'] = y_pred_proba

print(f"✅ Prédictions générées")
print(f"   Signaux WIN prédits: {(y_pred == 1).sum()} ({(y_pred == 1).sum()/len(y_pred)*100:.1f}%)")
print(f"   Signaux LOSS prédits: {(y_pred == 0).sum()} ({(y_pred == 0).sum()/len(y_pred)*100:.1f}%)")

# ==================== SIMULATION TRADES ====================
print("\n" + "=" * 80)
print("💼 SIMULATION TRADES")
print("=" * 80)

def simulate_trade(entry_price, direction, sl_pct, tp_pct, risk_usd):
    """
    Simule un trade avec SL/TP fixes
    Retourne le P&L en USD
    """
    sl_distance = entry_price * (sl_pct / 100)
    tp_distance = entry_price * (tp_pct / 100)

    # Calculer le lot size pour risquer exactement risk_usd
    # risk_usd = lot_size × sl_distance × contract_value
    # Pour XAUUSD: 1 lot = 100 oz, pip value ~$1 par 0.01 mouvement
    lot_size = risk_usd / sl_distance  # Simplifié

    # Les targets sont déjà calculés dans le dataset
    # On retourne juste le P&L basé sur target
    return None  # Sera calculé après

# Filtrer les trades que le ML prend (pred == 1)
df_ml_trades = df_test[df_test['ml_pred'] == 1].copy()

print(f"\n📊 Stratégie ML:")
print(f"   Trades pris: {len(df_ml_trades)}")

# Calculer les résultats
ml_wins = (df_ml_trades['target'] == 1).sum()
ml_losses = (df_ml_trades['target'] == 0).sum()
ml_win_rate = ml_wins / len(df_ml_trades) * 100 if len(df_ml_trades) > 0 else 0

print(f"   WIN:  {ml_wins}")
print(f"   LOSS: {ml_losses}")
print(f"   Win Rate: {ml_win_rate:.2f}%")

# Calculer P&L
# WIN = +1.75% du prix, LOSS = -0.35% du prix
ml_profit_per_win = RISK_PER_TRADE * (TP_PERCENT / SL_PERCENT)  # Ratio R:R
ml_profit_per_loss = -RISK_PER_TRADE

ml_total_pnl = (ml_wins * ml_profit_per_win) + (ml_losses * ml_profit_per_loss)
ml_profit_factor = abs(ml_wins * ml_profit_per_win / max(ml_losses * ml_profit_per_loss, 1))

print(f"\n💰 Résultats Financiers ML:")
print(f"   Profit/trade WIN:  ${ml_profit_per_win:.2f}")
print(f"   Perte/trade LOSS:  ${ml_profit_per_loss:.2f}")
print(f"   P&L Total:         ${ml_total_pnl:.2f}")
print(f"   Return:            {ml_total_pnl/INITIAL_CAPITAL*100:.2f}%")
print(f"   Profit Factor:     {ml_profit_factor:.2f}")

# ==================== COMPARAISON SANS FILTRE ML ====================
print("\n" + "=" * 80)
print("📊 COMPARAISON AVEC STRATÉGIE 'BUY ALL SIGNALS'")
print("=" * 80)

# Tous les signaux (sans filtre ML)
all_wins = (df_test['target'] == 1).sum()
all_losses = (df_test['target'] == 0).sum()
all_win_rate = all_wins / len(df_test) * 100

print(f"\n📊 Stratégie 'Buy All':")
print(f"   Trades pris: {len(df_test)}")
print(f"   WIN:  {all_wins}")
print(f"   LOSS: {all_losses}")
print(f"   Win Rate: {all_win_rate:.2f}%")

all_total_pnl = (all_wins * ml_profit_per_win) + (all_losses * ml_profit_per_loss)
all_profit_factor = abs(all_wins * ml_profit_per_win / max(all_losses * ml_profit_per_loss, 1))

print(f"\n💰 Résultats Financiers 'Buy All':")
print(f"   P&L Total:         ${all_total_pnl:.2f}")
print(f"   Return:            {all_total_pnl/INITIAL_CAPITAL*100:.2f}%")
print(f"   Profit Factor:     {all_profit_factor:.2f}")

# ==================== COMPARAISON ====================
print("\n" + "=" * 80)
print("🎯 COMPARAISON FINALE")
print("=" * 80)

improvement_pnl = ml_total_pnl - all_total_pnl
improvement_pct = (ml_total_pnl / max(abs(all_total_pnl), 1) - 1) * 100

print(f"\n{'Métrique':<25} {'ML Strategy':<15} {'Buy All':<15} {'Amélioration':<15}")
print("-" * 70)
print(f"{'Trades':<25} {len(df_ml_trades):<15} {len(df_test):<15} {len(df_test)-len(df_ml_trades):<15}")
print(f"{'Win Rate':<25} {ml_win_rate:.2f}%{'':<10} {all_win_rate:.2f}%{'':<10} {ml_win_rate-all_win_rate:+.2f}%")
print(f"{'P&L Total ($)':<25} ${ml_total_pnl:>10.2f}{'':<4} ${all_total_pnl:>10.2f}{'':<4} ${improvement_pnl:>+10.2f}")
print(f"{'Return (%)':<25} {ml_total_pnl/INITIAL_CAPITAL*100:>10.2f}%{'':<4} {all_total_pnl/INITIAL_CAPITAL*100:>10.2f}%{'':<4} {improvement_pct:>+10.2f}%")
print(f"{'Profit Factor':<25} {ml_profit_factor:>10.2f}{'':<4} {all_profit_factor:>10.2f}{'':<4} {ml_profit_factor-all_profit_factor:>+10.2f}")

# ==================== CONCLUSION ====================
print("\n" + "=" * 80)
print("✅ BACKTEST TERMINÉ")
print("=" * 80)

print(f"\n🎯 Verdict:")
if ml_win_rate > 70:
    print(f"   ⚠️  Win Rate de {ml_win_rate:.1f}% est TRÈS élevé")
    print(f"   → Possible overfitting")
    print(f"   → Testez en paper trading avant le réel!")
elif ml_win_rate > 50:
    print(f"   ✅ Win Rate de {ml_win_rate:.1f}% est EXCELLENT")
    print(f"   → Le modèle filtre efficacement les signaux")
    print(f"   → Prêt pour paper trading")
elif ml_win_rate > 30:
    print(f"   ✅ Win Rate de {ml_win_rate:.1f}% est BON")
    print(f"   → Amélioration significative vs 'Buy All' ({all_win_rate:.1f}%)")
else:
    print(f"   ❌ Win Rate de {ml_win_rate:.1f}% est trop faible")
    print(f"   → Modèle pas assez performant")

if ml_total_pnl > all_total_pnl:
    print(f"\n   💰 Le ML améliore le P&L de ${improvement_pnl:.2f} ({improvement_pct:+.1f}%)")
    print(f"   → Le modèle ajoute de la valeur!")
else:
    print(f"\n   ❌ Le ML réduit le P&L de ${improvement_pnl:.2f}")
    print(f"   → À revoir")

print(f"\n🚀 Prochaines étapes recommandées:")
if ml_win_rate > 60 and ml_total_pnl > all_total_pnl:
    print(f"   1. Testez sur données 2024-2025 uniquement (plus récent)")
    print(f"   2. Paper trading 1-2 semaines")
    print(f"   3. Si confirmé → Intégration MT5")
else:
    print(f"   1. Analyser feature_importance_balanced.png")
    print(f"   2. Feature selection (top 20 features)")
    print(f"   3. Réentraîner et retester")

print("\n" + "=" * 80)
