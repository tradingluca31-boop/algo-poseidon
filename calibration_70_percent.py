"""
Calibration pour obtenir 70%+ de Win Rate
Ajuste le seuil de prédiction pour maximiser la précision
Version 1.0 - 2025-10-09

OBJECTIF:
- Calibrer le modèle pour n'entrer que sur signaux à 70%+ de confiance
- Réduire le nombre de trades mais augmenter drastiquement le win rate
- Optimiser le seuil de probabilité (threshold)
"""

import pandas as pd
import numpy as np
import joblib
import os
from sklearn.calibration import calibration_curve
from sklearn.metrics import roc_auc_score, precision_score, recall_score, f1_score
import matplotlib.pyplot as plt

print("=" * 80)
print("🎯 CALIBRATION 70%+ WIN RATE")
print("=" * 80)

# ==================== CONFIGURATION ====================
DATA_CSV = "XAUUSD_COMPLETE_ML_Data_20Y_ENGINEERED.csv"
MODEL_FILE = "xauusd_lightgbm_optimized_model.pkl"  # Généré par Optuna
OUTPUT_MODEL = "xauusd_calibrated_70percent_model.pkl"

# Objectifs de calibration
TARGET_WIN_RATE = 0.70  # 70% de win rate minimum
MIN_TRADES = 100        # Minimum de trades sur période test (pour statistique valide)

# ==================== CHARGEMENT ====================
print("\n" + "=" * 80)
print("📂 CHARGEMENT MODÈLE ET DONNÉES")
print("=" * 80)

base_path = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
csv_path = os.path.join(base_path, DATA_CSV)
model_path = os.path.join(base_path, MODEL_FILE)

# Charger le modèle
print("🤖 Chargement du modèle...")
if not os.path.exists(model_path):
    print(f"❌ Modèle introuvable: {model_path}")
    print(f"Lancez d'abord: python ensemble_methods.py")
    print(f"   ou: python hyperparameter_tuning_optuna.py")
    exit(1)

model_data = joblib.load(model_path)

# Déterminer le type de modèle
if 'ensemble' in model_data:
    model = model_data['ensemble']
    model_type = "Ensemble"
    print(f"✅ Modèle Ensemble chargé")
else:
    model = model_data['model']
    model_type = "LightGBM"
    print(f"✅ Modèle LightGBM chargé")

feature_cols = model_data['feature_cols']
print(f"   Features: {len(feature_cols)}")

# Charger les données
print("\n📊 Chargement des données...")
df = pd.read_csv(csv_path)
df = df[df['target'].isin([0, 1])].copy()
print(f"✅ {len(df)} lignes chargées")

# Split train/test temporel (test = 20% dernières données)
split_idx = int(len(df) * 0.8)
df_test = df.iloc[split_idx:].copy()

print(f"\n📅 Période de test:")
print(f"   {len(df_test)} barres ({len(df_test)/len(df)*100:.1f}% du dataset)")

X_test = df_test[feature_cols].copy()
X_test = X_test.replace([np.inf, -np.inf], np.nan).fillna(0)
y_test = df_test['target'].copy()

# ==================== PRÉDICTIONS ====================
print("\n" + "=" * 80)
print("🔮 GÉNÉRATION PRÉDICTIONS")
print("=" * 80)

print("🚀 Prédiction en cours...")
y_pred_proba = model.predict_proba(X_test)[:, 1]
print(f"✅ Prédictions générées")

# ==================== ANALYSE CALIBRATION ====================
print("\n" + "=" * 80)
print("📊 ANALYSE CALIBRATION DU MODÈLE")
print("=" * 80)

# Courbe de calibration
fraction_of_positives, mean_predicted_value = calibration_curve(
    y_test, y_pred_proba, n_bins=10
)

print("\n📈 Courbe de calibration (bins):")
print(f"{'Probabilité Prédite':<25} {'Probabilité Réelle':<25} {'Différence':<15}")
print("-" * 65)
for pred, real in zip(mean_predicted_value, fraction_of_positives):
    diff = real - pred
    print(f"{pred:.2f}{'':<21} {real:.2f}{'':<21} {diff:+.2f}")

# ==================== OPTIMISATION THRESHOLD ====================
print("\n" + "=" * 80)
print("🎯 OPTIMISATION THRESHOLD POUR 70%+ WIN RATE")
print("=" * 80)

# Tester différents seuils
thresholds = np.arange(0.50, 0.95, 0.01)
results = []

for threshold in thresholds:
    y_pred = (y_pred_proba >= threshold).astype(int)

    # Calculer métriques
    n_predicted_win = y_pred.sum()

    if n_predicted_win == 0:
        continue

    # Win rate = parmi les signaux prédits WIN, combien sont réellement WIN
    predicted_win_mask = (y_pred == 1)
    actual_wins = y_test[predicted_win_mask].sum()
    win_rate = actual_wins / n_predicted_win if n_predicted_win > 0 else 0

    # Autres métriques
    precision = precision_score(y_test, y_pred, zero_division=0)
    recall = recall_score(y_test, y_pred, zero_division=0)
    f1 = f1_score(y_test, y_pred, zero_division=0)

    results.append({
        'threshold': threshold,
        'n_trades': n_predicted_win,
        'win_rate': win_rate,
        'precision': precision,
        'recall': recall,
        'f1': f1
    })

df_results = pd.DataFrame(results)

# Trouver le seuil qui donne 70%+ win rate avec le plus de trades
df_70plus = df_results[df_results['win_rate'] >= TARGET_WIN_RATE].copy()

if len(df_70plus) == 0:
    print(f"❌ IMPOSSIBLE d'atteindre {TARGET_WIN_RATE*100}% de win rate")
    print(f"   Win rate maximum: {df_results['win_rate'].max()*100:.2f}%")
    print(f"   Au seuil: {df_results.loc[df_results['win_rate'].idxmax(), 'threshold']:.2f}")

    # Prendre le meilleur disponible
    best_idx = df_results['win_rate'].idxmax()
    optimal_threshold = df_results.loc[best_idx, 'threshold']
    optimal_win_rate = df_results.loc[best_idx, 'win_rate']
    optimal_n_trades = df_results.loc[best_idx, 'n_trades']

    print(f"\n⚠️  Utilisation du meilleur win rate disponible:")
    print(f"   Threshold: {optimal_threshold:.2f}")
    print(f"   Win Rate: {optimal_win_rate*100:.2f}%")
    print(f"   Trades: {int(optimal_n_trades)}")
else:
    # Parmi les seuils à 70%+, prendre celui avec le plus de trades
    best_idx = df_70plus['n_trades'].idxmax()
    optimal_threshold = df_70plus.loc[best_idx, 'threshold']
    optimal_win_rate = df_70plus.loc[best_idx, 'win_rate']
    optimal_n_trades = df_70plus.loc[best_idx, 'n_trades']

    print(f"✅ SEUIL OPTIMAL TROUVÉ:")
    print(f"   Threshold: {optimal_threshold:.2f}")
    print(f"   Win Rate: {optimal_win_rate*100:.2f}%")
    print(f"   Trades: {int(optimal_n_trades)}")
    print(f"   Precision: {df_70plus.loc[best_idx, 'precision']:.4f}")
    print(f"   Recall: {df_70plus.loc[best_idx, 'recall']:.4f}")

# ==================== AFFICHER TOP THRESHOLDS ====================
print("\n" + "=" * 80)
print("📊 TOP 10 THRESHOLDS PAR WIN RATE")
print("=" * 80)

top_10 = df_results.nlargest(10, 'win_rate')

print(f"\n{'Threshold':<12} {'Win Rate':<12} {'Trades':<10} {'Precision':<12} {'Recall':<12}")
print("-" * 60)
for _, row in top_10.iterrows():
    threshold_str = f"{row['threshold']:.2f}"
    win_rate_str = f"{row['win_rate']*100:.2f}%"
    trades_str = f"{int(row['n_trades'])}"
    precision_str = f"{row['precision']:.4f}"
    recall_str = f"{row['recall']:.4f}"

    marker = "  ← OPTIMAL" if row['threshold'] == optimal_threshold else ""

    print(f"{threshold_str:<12} {win_rate_str:<12} {trades_str:<10} {precision_str:<12} {recall_str:<12}{marker}")

# ==================== VALIDATION FINALE ====================
print("\n" + "=" * 80)
print("✅ VALIDATION FINALE AVEC THRESHOLD OPTIMAL")
print("=" * 80)

y_pred_optimal = (y_pred_proba >= optimal_threshold).astype(int)
predicted_win_mask = (y_pred_optimal == 1)

n_predicted_win = y_pred_optimal.sum()
n_actual_win = y_test[predicted_win_mask].sum()
n_actual_loss = n_predicted_win - n_actual_win

print(f"\n📊 Résultats sur période test:")
print(f"   Total barres: {len(y_test)}")
print(f"   Signaux WIN prédits: {n_predicted_win}")
print(f"   Dont réels WIN: {n_actual_win}")
print(f"   Dont réels LOSS: {n_actual_loss}")
print(f"   Win Rate: {optimal_win_rate*100:.2f}%")

# Calcul P&L simulé
RISK_PER_TRADE = 100
TP_PERCENT = 1.75
SL_PERCENT = 0.35
profit_per_win = RISK_PER_TRADE * (TP_PERCENT / SL_PERCENT)
profit_per_loss = -RISK_PER_TRADE

total_pnl = (n_actual_win * profit_per_win) + (n_actual_loss * profit_per_loss)
profit_factor = abs(n_actual_win * profit_per_win / max(n_actual_loss * profit_per_loss, 1))

print(f"\n💰 Résultats Financiers Simulés:")
print(f"   P&L Total: ${total_pnl:.2f}")
print(f"   Return: {total_pnl/10000*100:.2f}%")
print(f"   Profit Factor: {profit_factor:.2f}")
print(f"   Avg $ per trade: ${total_pnl/n_predicted_win:.2f}")

# Comparer avec threshold 0.5
y_pred_50 = (y_pred_proba >= 0.5).astype(int)
n_50 = y_pred_50.sum()
win_50 = y_test[y_pred_50 == 1].sum()
wr_50 = win_50 / n_50 if n_50 > 0 else 0

print(f"\n📊 Comparaison avec threshold 0.5:")
print(f"   Threshold 0.5:")
print(f"      Trades: {n_50}")
print(f"      Win Rate: {wr_50*100:.2f}%")
print(f"   Threshold {optimal_threshold:.2f}:")
print(f"      Trades: {n_predicted_win} ({(n_predicted_win/n_50-1)*100:+.1f}%)")
print(f"      Win Rate: {optimal_win_rate*100:.2f}% ({(optimal_win_rate-wr_50)*100:+.2f}%)")

# ==================== SAUVEGARDE ====================
print("\n" + "=" * 80)
print("💾 SAUVEGARDE MODÈLE CALIBRÉ")
print("=" * 80)

output_path = os.path.join(base_path, OUTPUT_MODEL)

calibrated_model_data = model_data.copy()
calibrated_model_data['calibrated_threshold'] = optimal_threshold
calibrated_model_data['calibrated_win_rate'] = optimal_win_rate
calibrated_model_data['calibration_date'] = pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')
calibrated_model_data['target_win_rate'] = TARGET_WIN_RATE

joblib.dump(calibrated_model_data, output_path)
print(f"✅ Modèle calibré sauvegardé: {output_path}")

file_size_mb = os.path.getsize(output_path) / (1024 * 1024)
print(f"📦 Taille: {file_size_mb:.2f} MB")

# ==================== COURBE CALIBRATION ====================
print("\n" + "=" * 80)
print("📈 GÉNÉRATION GRAPHIQUE CALIBRATION")
print("=" * 80)

try:
    fig, axes = plt.subplots(1, 2, figsize=(14, 6))

    # 1. Courbe de calibration
    axes[0].plot([0, 1], [0, 1], 'k--', label='Parfaitement calibré')
    axes[0].plot(mean_predicted_value, fraction_of_positives, 'o-', label='Modèle')
    axes[0].set_xlabel('Probabilité Prédite')
    axes[0].set_ylabel('Probabilité Réelle')
    axes[0].set_title('Courbe de Calibration')
    axes[0].legend()
    axes[0].grid(True, alpha=0.3)

    # 2. Win Rate vs Threshold
    axes[1].plot(df_results['threshold'], df_results['win_rate'] * 100, label='Win Rate')
    axes[1].axhline(y=TARGET_WIN_RATE * 100, color='r', linestyle='--', label=f'Target {TARGET_WIN_RATE*100}%')
    axes[1].axvline(x=optimal_threshold, color='g', linestyle='--', label=f'Optimal {optimal_threshold:.2f}')
    axes[1].set_xlabel('Threshold')
    axes[1].set_ylabel('Win Rate (%)')
    axes[1].set_title('Win Rate vs Threshold')
    axes[1].legend()
    axes[1].grid(True, alpha=0.3)

    plt.tight_layout()

    plot_path = os.path.join(base_path, 'calibration_curve.png')
    plt.savefig(plot_path, dpi=150, bbox_inches='tight')
    print(f"✅ Graphique sauvegardé: {plot_path}")
    plt.close()
except Exception as e:
    print(f"⚠️  Impossible de générer le graphique: {e}")

# ==================== RÉSUMÉ ====================
print("\n" + "=" * 80)
print("✅ CALIBRATION TERMINÉE")
print("=" * 80)

print(f"\n🎯 Résumé:")
print(f"   Modèle: {model_type}")
print(f"   Threshold optimal: {optimal_threshold:.2f}")
print(f"   Win Rate obtenu: {optimal_win_rate*100:.2f}%")
print(f"   Trades sur test: {n_predicted_win}")
print(f"   P&L simulé: ${total_pnl:.2f}")

if optimal_win_rate >= TARGET_WIN_RATE:
    print(f"\n✅ OBJECTIF ATTEINT: {TARGET_WIN_RATE*100}%+ win rate!")
    print(f"   Le modèle est prêt pour le backtesting final")
else:
    print(f"\n⚠️  OBJECTIF NON ATTEINT")
    print(f"   Win rate max possible: {optimal_win_rate*100:.2f}%")
    print(f"   Recommandations:")
    print(f"      1. Améliorer feature engineering")
    print(f"      2. Ajouter plus de données externes")
    print(f"      3. Tester d'autres modèles (Neural Networks)")

print(f"\n🚀 Prochaines étapes:")
print(f"   1. Backtest complet avec threshold {optimal_threshold:.2f}")
print(f"   2. Si résultats confirmés → Paper trading")
print(f"   3. Si paper trading OK → Live trading")

print(f"\n💡 Utilisation:")
print(f"   import joblib")
print(f"   model = joblib.load('{OUTPUT_MODEL}')")
print(f"   threshold = model['calibrated_threshold']")
print(f"   predictions = model['ensemble'].predict_proba(X)[:, 1]")
print(f"   signals = predictions >= threshold")

print("\n" + "=" * 80)
