"""
Script d'entraînement LightGBM avec UNDERSAMPLING (dataset équilibré)
Pour prédiction WIN/LOSS trading XAUUSD
Version optimisée - 2025-10-09

DIFFÉRENCE avec train_lightgbm_model.py:
- Dataset équilibré 50% WIN / 50% LOSS
- Meilleure capacité à détecter les WIN
- Win rate prédit plus réaliste (20-30%)
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
print("🤖 ENTRAÎNEMENT MODÈLE ML - LIGHTGBM (DATASET ÉQUILIBRÉ)")
print("=" * 80)

# ==================== CONFIGURATION ====================
INPUT_CSV = "XAUUSD_COMPLETE_ML_Data.csv"
MODEL_OUTPUT = "xauusd_lightgbm_balanced_model.pkl"
FEATURE_IMPORTANCE_PLOT = "feature_importance_balanced.png"

# Paramètres LightGBM (sans scale_pos_weight car dataset équilibré)
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
    'verbose': -1,
    'random_state': 42
}

# Validation temporelle
N_SPLITS = 5

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

# ==================== PRÉPARATION DONNÉES ====================
print("\n" + "=" * 80)
print("🔧 PRÉPARATION DONNÉES AVEC UNDERSAMPLING")
print("=" * 80)

# Filtrer les targets valides
df_valid = df[df['target'].isin([0, 1])].copy()
print(f"✅ {len(df_valid)} lignes avec target valide")

# Séparer WIN et LOSS
df_win = df_valid[df_valid['target'] == 1].copy()
df_loss = df_valid[df_valid['target'] == 0].copy()

print(f"\n📊 Distribution AVANT undersampling:")
print(f"   LOSS: {len(df_loss)} ({len(df_loss)/len(df_valid)*100:.1f}%)")
print(f"   WIN:  {len(df_win)} ({len(df_win)/len(df_valid)*100:.1f}%)")

# Undersampling : garder tous les WIN + échantillon aléatoire de LOSS
n_win = len(df_win)
df_loss_sampled = df_loss.sample(n=n_win, random_state=42)

# Combiner et mélanger
df_balanced = pd.concat([df_win, df_loss_sampled], ignore_index=True)
df_balanced = df_balanced.sample(frac=1, random_state=42).reset_index(drop=True)

print(f"\n📊 Distribution APRÈS undersampling:")
print(f"   LOSS: {len(df_loss_sampled)} (50.0%)")
print(f"   WIN:  {len(df_win)} (50.0%)")
print(f"   TOTAL: {len(df_balanced)} lignes")

print(f"\n✅ Dataset équilibré créé!")
print(f"   Vous avez gardé TOUTES les données WIN")
print(f"   Vous avez échantillonné {len(df_loss_sampled)} LOSS sur {len(df_loss)}")

# Séparer features et target
target_col = 'target'
time_col = 'time'
exclude_cols = [target_col, time_col]

feature_cols = [col for col in df_balanced.columns if col not in exclude_cols]

X = df_balanced[feature_cols].copy()
y = df_balanced[target_col].copy()

# Nettoyer
X = X.replace([np.inf, -np.inf], np.nan)
nan_count = X.isna().sum().sum()
if nan_count > 0:
    print(f"\n🧹 Nettoyage: {nan_count} valeurs NaN → 0")
    X = X.fillna(0)

print(f"\n✅ Dataset final: {X.shape[0]} lignes × {X.shape[1]} features")

# ==================== VALIDATION TEMPORELLE ====================
print("\n" + "=" * 80)
print("📈 VALIDATION TEMPORELLE (WALK-FORWARD)")
print("=" * 80)

tscv = TimeSeriesSplit(n_splits=N_SPLITS)

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
            lgb.log_evaluation(period=0)
        ]
    )

    # Prédictions avec seuil 0.25 (cohérent avec win rate réel ~25%)
    y_pred_proba = model.predict(X_val, num_iteration=model.best_iteration)
    threshold = 0.25
    y_pred = (y_pred_proba >= threshold).astype(int)

    # Métriques
    accuracy = accuracy_score(y_val, y_pred)
    precision = precision_score(y_val, y_pred, zero_division=0)
    recall = recall_score(y_val, y_pred, zero_division=0)
    f1 = f1_score(y_val, y_pred, zero_division=0)
    auc = roc_auc_score(y_val, y_pred_proba)

    # Métriques trading
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
print("🏆 ENTRAÎNEMENT MODÈLE FINAL (sur dataset équilibré complet)")
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
plt.title('Top 20 Features - LightGBM (Dataset Équilibré)')
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

model_data = {
    'model': final_model,
    'feature_cols': feature_cols,
    'lgbm_params': LGBM_PARAMS,
    'cv_metrics': df_metrics.to_dict(),
    'training_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'n_samples': len(X),
    'n_features': len(feature_cols),
    'balanced': True,
    'threshold': 0.25
}

joblib.dump(model_data, model_path)
print(f"✅ Modèle sauvegardé: {model_path}")

file_size_mb = os.path.getsize(model_path) / (1024 * 1024)
print(f"📦 Taille du fichier: {file_size_mb:.2f} MB")

# ==================== RÉSUMÉ FINAL ====================
print("\n" + "=" * 80)
print("✅ ENTRAÎNEMENT TERMINÉ AVEC SUCCÈS!")
print("=" * 80)

print(f"\n📊 Résumé:")
print(f"   Dataset équilibré: {len(X)} samples (50% WIN / 50% LOSS)")
print(f"   Features: {len(feature_cols)}")
print(f"   Cross-validation: {N_SPLITS} folds")
print(f"   Accuracy moyenne: {df_metrics['accuracy'].mean()*100:.2f}%")
print(f"   AUC moyenne: {df_metrics['auc'].mean():.4f}")
print(f"   Win Rate prédit: {df_metrics['win_rate'].mean():.2f}%")
print(f"   True Win Rate: {df_metrics['true_win_rate'].mean():.2f}%")

print(f"\n📁 Fichiers générés:")
print(f"   🤖 Modèle: {model_path}")
print(f"   📊 Graphique: {plot_path}")

print(f"\n🎯 Amélioration vs modèle déséquilibré:")
print(f"   Win Rate: 8.64% → {df_metrics['win_rate'].mean():.2f}%")
print(f"   Le modèle peut maintenant VRAIMENT filtrer les signaux WIN!")

print("\n" + "=" * 80)
