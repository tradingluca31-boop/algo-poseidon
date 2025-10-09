"""
Script d'entraînement LightGBM pour prédiction WIN/LOSS trading XAUUSD
Version optimisée avec validation temporelle
Pour Anaconda - Version 1.0 - 2025-10-09

Dépendances:
pip install lightgbm scikit-learn matplotlib seaborn joblib
"""

import pandas as pd
import numpy as np
import lightgbm as lgb
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, roc_auc_score
import matplotlib.pyplot as plt
import seaborn as sns
import joblib
import os
from datetime import datetime

print("=" * 80)
print("🤖 ENTRAÎNEMENT MODÈLE ML - LIGHTGBM")
print("=" * 80)

# ==================== CONFIGURATION ====================
INPUT_CSV = "XAUUSD_COMPLETE_ML_Data.csv"
MODEL_OUTPUT = "xauusd_lightgbm_model.pkl"
FEATURE_IMPORTANCE_PLOT = "feature_importance.png"

# Paramètres LightGBM (optimisés pour classification trading)
# IMPORTANT: scale_pos_weight pour gérer le déséquilibre LOSS/WIN
# Calculé comme: ratio LOSS/WIN du dataset
LGBM_PARAMS = {
    'objective': 'binary',
    'metric': 'auc',
    'boosting_type': 'gbdt',
    'num_leaves': 31,
    'learning_rate': 0.05,
    'feature_fraction': 0.8,
    'bagging_fraction': 0.8,
    'bagging_freq': 5,
    'min_child_samples': 20,
    'scale_pos_weight': None,  # Sera calculé automatiquement
    'verbose': -1,
    'random_state': 42
}

# Validation temporelle
N_SPLITS = 5  # 5 folds pour walk-forward validation

# ==================== CHARGEMENT DONNÉES ====================
print("\n" + "=" * 80)
print("📂 CHARGEMENT DONNÉES")
print("=" * 80)

csv_path = os.path.join(r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files", INPUT_CSV)

if not os.path.exists(csv_path):
    print(f"❌ ERREUR: Fichier introuvable: {csv_path}")
    exit(1)

df = pd.read_csv(csv_path)
print(f"✅ {len(df)} lignes chargées")
print(f"📊 {len(df.columns)} colonnes")

# ==================== PRÉPARATION DONNÉES ====================
print("\n" + "=" * 80)
print("🔧 PRÉPARATION DONNÉES")
print("=" * 80)

# Filtrer les targets valides (0 ou 1, pas -1)
df_valid = df[df['target'].isin([0, 1])].copy()
print(f"✅ {len(df_valid)} lignes avec target valide (WIN/LOSS)")
print(f"❌ {len(df) - len(df_valid)} lignes ignorées (target = -1)")

# Séparer features et target
target_col = 'target'
time_col = 'time'
exclude_cols = [target_col, time_col]

feature_cols = [col for col in df_valid.columns if col not in exclude_cols]

X = df_valid[feature_cols].copy()
y = df_valid[target_col].copy()

print(f"\n📊 Distribution target:")
n_loss = (y == 0).sum()
n_win = (y == 1).sum()
print(f"   LOSS (0): {n_loss} ({n_loss / len(y) * 100:.1f}%)")
print(f"   WIN  (1): {n_win} ({n_win / len(y) * 100:.1f}%)")

# Calculer scale_pos_weight automatiquement
scale_pos_weight = n_loss / n_win
LGBM_PARAMS['scale_pos_weight'] = scale_pos_weight
print(f"\n⚖️  Scale pos weight calculé: {scale_pos_weight:.2f}")
print(f"   → Le modèle donnera {scale_pos_weight:.1f}x plus d'importance aux WIN")

# Gérer les valeurs infinies et NaN
print(f"\n🧹 Nettoyage des données:")
X = X.replace([np.inf, -np.inf], np.nan)
nan_count = X.isna().sum().sum()
if nan_count > 0:
    print(f"   ⚠️  {nan_count} valeurs NaN détectées - remplacement par 0")
    X = X.fillna(0)
else:
    print(f"   ✅ Aucune valeur NaN")

print(f"\n✅ Dataset final: {X.shape[0]} lignes × {X.shape[1]} features")

# ==================== VALIDATION TEMPORELLE ====================
print("\n" + "=" * 80)
print("📈 VALIDATION TEMPORELLE (WALK-FORWARD)")
print("=" * 80)

tscv = TimeSeriesSplit(n_splits=N_SPLITS)

# Métriques pour chaque fold
fold_metrics = []

for fold_idx, (train_idx, val_idx) in enumerate(tscv.split(X), 1):
    print(f"\n{'=' * 40}")
    print(f"🔄 FOLD {fold_idx}/{N_SPLITS}")
    print(f"{'=' * 40}")

    X_train, X_val = X.iloc[train_idx], X.iloc[val_idx]
    y_train, y_val = y.iloc[train_idx], y.iloc[val_idx]

    print(f"Train: {len(X_train)} samples | Val: {len(X_val)} samples")

    # Créer dataset LightGBM
    train_data = lgb.Dataset(X_train, label=y_train)
    val_data = lgb.Dataset(X_val, label=y_val, reference=train_data)

    # Entraîner
    print("🚀 Entraînement en cours...")
    model = lgb.train(
        LGBM_PARAMS,
        train_data,
        num_boost_round=500,
        valid_sets=[train_data, val_data],
        valid_names=['train', 'val'],
        callbacks=[
            lgb.early_stopping(stopping_rounds=50, verbose=False),
            lgb.log_evaluation(period=0)  # Pas d'affichage pendant l'entraînement
        ]
    )

    # Prédictions avec seuil ajusté (0.25 au lieu de 0.5)
    # Cohérent avec win rate réel de Poseidon (~25%)
    y_pred_proba = model.predict(X_val, num_iteration=model.best_iteration)
    threshold = 0.25
    y_pred = (y_pred_proba >= threshold).astype(int)

    # Métriques
    accuracy = accuracy_score(y_val, y_pred)
    precision = precision_score(y_val, y_pred, zero_division=0)
    recall = recall_score(y_val, y_pred, zero_division=0)
    f1 = f1_score(y_val, y_pred, zero_division=0)
    auc = roc_auc_score(y_val, y_pred_proba)

    # Métriques de trading
    win_rate = (y_pred == 1).sum() / len(y_pred) * 100
    true_win_rate = ((y_pred == 1) & (y_val == 1)).sum() / max((y_pred == 1).sum(), 1) * 100

    fold_metrics.append({
        'fold': fold_idx,
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'f1': f1,
        'auc': auc,
        'win_rate': win_rate,
        'true_win_rate': true_win_rate
    })

    print(f"\n📊 Résultats Fold {fold_idx}:")
    print(f"   Accuracy:        {accuracy:.4f} ({accuracy*100:.2f}%)")
    print(f"   Precision:       {precision:.4f}")
    print(f"   Recall:          {recall:.4f}")
    print(f"   F1-Score:        {f1:.4f}")
    print(f"   AUC:             {auc:.4f}")
    print(f"   Win Rate (pred): {win_rate:.2f}% (seuil={threshold})")
    print(f"   True Win Rate:   {true_win_rate:.2f}%")

# ==================== RÉSULTATS CROSS-VALIDATION ====================
print("\n" + "=" * 80)
print("📊 RÉSULTATS CROSS-VALIDATION")
print("=" * 80)

df_metrics = pd.DataFrame(fold_metrics)

print(f"\n{'Métrique':<20} {'Moyenne':<12} {'Écart-type':<12}")
print("-" * 44)
for col in ['accuracy', 'precision', 'recall', 'f1', 'auc']:
    mean = df_metrics[col].mean()
    std = df_metrics[col].std()
    print(f"{col.capitalize():<20} {mean:.4f} ({mean*100:.2f}%)  ± {std:.4f}")

print(f"\n{'Win Rate (pred)':<20} {df_metrics['win_rate'].mean():.2f}%      ± {df_metrics['win_rate'].std():.2f}%")
print(f"{'True Win Rate':<20} {df_metrics['true_win_rate'].mean():.2f}%      ± {df_metrics['true_win_rate'].std():.2f}%")

# ==================== ENTRAÎNEMENT MODÈLE FINAL ====================
print("\n" + "=" * 80)
print("🏆 ENTRAÎNEMENT MODÈLE FINAL (sur toutes les données)")
print("=" * 80)

train_data_full = lgb.Dataset(X, label=y)

print("🚀 Entraînement en cours...")
final_model = lgb.train(
    LGBM_PARAMS,
    train_data_full,
    num_boost_round=500,
    valid_sets=[train_data_full],
    valid_names=['train'],
    callbacks=[lgb.log_evaluation(period=100)]
)

print(f"✅ Modèle final entraîné avec {final_model.best_iteration} arbres")

# ==================== FEATURE IMPORTANCE ====================
print("\n" + "=" * 80)
print("🔍 IMPORTANCE DES FEATURES")
print("=" * 80)

importance = final_model.feature_importance(importance_type='gain')
feature_importance_df = pd.DataFrame({
    'feature': feature_cols,
    'importance': importance
}).sort_values('importance', ascending=False)

print(f"\n🏆 TOP 20 FEATURES LES PLUS IMPORTANTES:")
print(feature_importance_df.head(20).to_string(index=False))

# Graphique
plt.figure(figsize=(10, 8))
top_20 = feature_importance_df.head(20)
plt.barh(range(len(top_20)), top_20['importance'].values)
plt.yticks(range(len(top_20)), top_20['feature'].values)
plt.xlabel('Importance (Gain)')
plt.title('Top 20 Features - LightGBM')
plt.gca().invert_yaxis()
plt.tight_layout()

plot_path = os.path.join(os.path.dirname(csv_path), FEATURE_IMPORTANCE_PLOT)
plt.savefig(plot_path, dpi=150, bbox_inches='tight')
print(f"\n💾 Graphique sauvegardé: {plot_path}")
plt.close()

# ==================== SAUVEGARDE MODÈLE ====================
print("\n" + "=" * 80)
print("💾 SAUVEGARDE MODÈLE")
print("=" * 80)

model_path = os.path.join(os.path.dirname(csv_path), MODEL_OUTPUT)

# Sauvegarder avec joblib (plus compact)
model_data = {
    'model': final_model,
    'feature_cols': feature_cols,
    'lgbm_params': LGBM_PARAMS,
    'cv_metrics': df_metrics.to_dict(),
    'training_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'n_samples': len(X),
    'n_features': len(feature_cols)
}

joblib.dump(model_data, model_path)
print(f"✅ Modèle sauvegardé: {model_path}")

# Taille du fichier
file_size_mb = os.path.getsize(model_path) / (1024 * 1024)
print(f"📦 Taille du fichier: {file_size_mb:.2f} MB")

# ==================== RÉSUMÉ FINAL ====================
print("\n" + "=" * 80)
print("✅ ENTRAÎNEMENT TERMINÉ AVEC SUCCÈS!")
print("=" * 80)

print(f"\n📊 Résumé:")
print(f"   Dataset: {len(X)} samples × {len(feature_cols)} features")
print(f"   Target distribution: {(y==0).sum()} LOSS / {(y==1).sum()} WIN")
print(f"   Cross-validation: {N_SPLITS} folds")
print(f"   Accuracy moyenne: {df_metrics['accuracy'].mean()*100:.2f}%")
print(f"   AUC moyenne: {df_metrics['auc'].mean():.4f}")
print(f"   Arbres: {final_model.best_iteration}")

print(f"\n📁 Fichiers générés:")
print(f"   🤖 Modèle: {model_path}")
print(f"   📊 Graphique: {plot_path}")

print(f"\n🚀 Prochaines étapes:")
print(f"   1. Analyser le graphique de feature importance")
print(f"   2. Tester le modèle en backtest")
print(f"   3. Optimiser les hyperparamètres avec Optuna (optionnel)")
print(f"   4. Intégrer le modèle dans votre EA MT5")

print("\n" + "=" * 80)
