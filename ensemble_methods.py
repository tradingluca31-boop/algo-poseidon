"""
Ensemble Methods pour améliorer les prédictions ML
Combine LightGBM + XGBoost + CatBoost via Voting Classifier
Version 1.0 - 2025-10-09

OBJECTIF:
- Combiner 3 modèles de gradient boosting
- Voting majoritaire pondéré
- Améliorer robustesse et généralisation
"""

import pandas as pd
import numpy as np
import lightgbm as lgb
import xgboost as xgb
import catboost as cb
from sklearn.model_selection import TimeSeriesSplit
from sklearn.ensemble import VotingClassifier
from sklearn.metrics import roc_auc_score, classification_report, confusion_matrix
import joblib
import os
from datetime import datetime

print("=" * 80)
print("🎯 ENSEMBLE METHODS - LIGHTGBM + XGBOOST + CATBOOST")
print("=" * 80)

# ==================== CONFIGURATION ====================
INPUT_CSV = "XAUUSD_COMPLETE_ML_Data_20Y_ENGINEERED.csv"
MODEL_OUTPUT = "xauusd_ensemble_model.pkl"
N_SPLITS = 3  # Cross-validation folds

# ==================== CHARGEMENT ====================
print("\n📂 Chargement des données...")
csv_path = os.path.join(r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files", INPUT_CSV)

if not os.path.exists(csv_path):
    print(f"❌ Fichier introuvable: {csv_path}")
    print(f"Lancez d'abord: python feature_engineering_advanced.py")
    exit(1)

df = pd.read_csv(csv_path)
print(f"✅ {len(df)} lignes chargées")

# Préparer les données
df_valid = df[df['target'].isin([0, 1])].copy()
print(f"✅ {len(df_valid)} lignes avec target valide")

# Undersampling pour équilibrer
df_win = df_valid[df_valid['target'] == 1].copy()
df_loss = df_valid[df_valid['target'] == 0].copy()
df_loss_sampled = df_loss.sample(n=len(df_win), random_state=42)
df_balanced = pd.concat([df_win, df_loss_sampled], ignore_index=True)
df_balanced = df_balanced.sample(frac=1, random_state=42).reset_index(drop=True)

print(f"✅ Dataset équilibré: {len(df_balanced)} lignes")

# Séparer X et y
exclude_cols = ['target', 'time']
feature_cols = [col for col in df_balanced.columns if col not in exclude_cols]

X = df_balanced[feature_cols].copy()
y = df_balanced['target'].copy()

X = X.replace([np.inf, -np.inf], np.nan).fillna(0)

print(f"✅ {X.shape[0]} lignes × {X.shape[1]} features")

# ==================== CONFIGURATION MODÈLES ====================
print("\n" + "=" * 80)
print("⚙️ CONFIGURATION DES 3 MODÈLES")
print("=" * 80)

# LightGBM - Rapide et efficace
lgbm_params = {
    'objective': 'binary',
    'metric': 'auc',
    'boosting_type': 'gbdt',
    'num_leaves': 50,
    'learning_rate': 0.05,
    'feature_fraction': 0.8,
    'bagging_fraction': 0.8,
    'bagging_freq': 5,
    'min_child_samples': 20,
    'max_depth': 7,
    'lambda_l1': 0.1,
    'lambda_l2': 0.1,
    'verbosity': -1,
    'random_state': 42,
    'n_estimators': 500
}

# XGBoost - Puissant et précis
xgb_params = {
    'objective': 'binary:logistic',
    'eval_metric': 'auc',
    'max_depth': 7,
    'learning_rate': 0.05,
    'subsample': 0.8,
    'colsample_bytree': 0.8,
    'min_child_weight': 20,
    'reg_alpha': 0.1,
    'reg_lambda': 0.1,
    'random_state': 42,
    'n_estimators': 500,
    'tree_method': 'hist'
}

# CatBoost - Gère bien les features catégorielles
cat_params = {
    'iterations': 500,
    'learning_rate': 0.05,
    'depth': 7,
    'l2_leaf_reg': 0.1,
    'subsample': 0.8,
    'random_seed': 42,
    'verbose': False,
    'loss_function': 'Logloss',
    'eval_metric': 'AUC'
}

print("✅ LightGBM configuré")
print("✅ XGBoost configuré")
print("✅ CatBoost configuré")

# ==================== ENTRAÎNEMENT INDIVIDUEL ====================
print("\n" + "=" * 80)
print("🚀 ENTRAÎNEMENT DES 3 MODÈLES INDIVIDUELS")
print("=" * 80)

# Split train/test temporel
split_idx = int(len(X) * 0.8)
X_train, X_test = X.iloc[:split_idx], X.iloc[split_idx:]
y_train, y_test = y.iloc[:split_idx], y.iloc[split_idx:]

print(f"\n📊 Split temporel:")
print(f"   Train: {len(X_train)} lignes ({len(X_train)/len(X)*100:.1f}%)")
print(f"   Test:  {len(X_test)} lignes ({len(X_test)/len(X)*100:.1f}%)")

# 1. LightGBM
print("\n🔵 Entraînement LightGBM...")
lgbm_model = lgb.LGBMClassifier(**lgbm_params)
lgbm_model.fit(
    X_train, y_train,
    eval_set=[(X_test, y_test)],
    callbacks=[lgb.early_stopping(stopping_rounds=50, verbose=False)]
)
lgbm_pred = lgbm_model.predict_proba(X_test)[:, 1]
lgbm_auc = roc_auc_score(y_test, lgbm_pred)
print(f"   ✅ LightGBM AUC: {lgbm_auc:.4f}")

# 2. XGBoost
print("\n🟠 Entraînement XGBoost...")
xgb_model = xgb.XGBClassifier(**xgb_params)
xgb_model.fit(
    X_train, y_train,
    eval_set=[(X_test, y_test)],
    early_stopping_rounds=50,
    verbose=False
)
xgb_pred = xgb_model.predict_proba(X_test)[:, 1]
xgb_auc = roc_auc_score(y_test, xgb_pred)
print(f"   ✅ XGBoost AUC: {xgb_auc:.4f}")

# 3. CatBoost
print("\n🟢 Entraînement CatBoost...")
cat_model = cb.CatBoostClassifier(**cat_params)
cat_model.fit(
    X_train, y_train,
    eval_set=(X_test, y_test),
    early_stopping_rounds=50,
    verbose=False
)
cat_pred = cat_model.predict_proba(X_test)[:, 1]
cat_auc = roc_auc_score(y_test, cat_pred)
print(f"   ✅ CatBoost AUC: {cat_auc:.4f}")

# ==================== ENSEMBLE VOTING ====================
print("\n" + "=" * 80)
print("🎯 CRÉATION ENSEMBLE VOTING CLASSIFIER")
print("=" * 80)

# Pondération basée sur les performances individuelles
total_auc = lgbm_auc + xgb_auc + cat_auc
lgbm_weight = lgbm_auc / total_auc
xgb_weight = xgb_auc / total_auc
cat_weight = cat_auc / total_auc

print(f"\n📊 Poids calculés:")
print(f"   LightGBM: {lgbm_weight:.3f}")
print(f"   XGBoost:  {xgb_weight:.3f}")
print(f"   CatBoost: {cat_weight:.3f}")

# Créer l'ensemble
ensemble = VotingClassifier(
    estimators=[
        ('lgbm', lgbm_model),
        ('xgb', xgb_model),
        ('cat', cat_model)
    ],
    voting='soft',  # Moyenne des probabilités
    weights=[lgbm_weight, xgb_weight, cat_weight]
)

# Fit sur les modèles déjà entraînés (voting se base sur predict_proba)
print("\n🔄 Création de l'ensemble...")
ensemble.estimators_ = [lgbm_model, xgb_model, cat_model]
ensemble.classes_ = np.array([0, 1])

# Prédictions ensemble
ensemble_pred = ensemble.predict_proba(X_test)[:, 1]
ensemble_auc = roc_auc_score(y_test, ensemble_pred)

print(f"\n🏆 RÉSULTATS ENSEMBLE:")
print(f"   AUC Ensemble: {ensemble_auc:.4f}")

# Comparaison
print(f"\n📊 Comparaison avec modèles individuels:")
print(f"   LightGBM: {lgbm_auc:.4f}")
print(f"   XGBoost:  {xgb_auc:.4f}")
print(f"   CatBoost: {cat_auc:.4f}")
print(f"   Ensemble: {ensemble_auc:.4f} {'✅ MEILLEUR' if ensemble_auc > max(lgbm_auc, xgb_auc, cat_auc) else ''}")

# ==================== MÉTRIQUES DÉTAILLÉES ====================
print("\n" + "=" * 80)
print("📊 MÉTRIQUES DÉTAILLÉES ENSEMBLE")
print("=" * 80)

ensemble_pred_binary = (ensemble_pred >= 0.5).astype(int)

print("\n📋 Classification Report:")
print(classification_report(y_test, ensemble_pred_binary, target_names=['LOSS', 'WIN']))

print("\n📊 Confusion Matrix:")
cm = confusion_matrix(y_test, ensemble_pred_binary)
print(f"   True Negatives:  {cm[0, 0]}")
print(f"   False Positives: {cm[0, 1]}")
print(f"   False Negatives: {cm[1, 0]}")
print(f"   True Positives:  {cm[1, 1]}")

win_rate = cm[1, 1] / (cm[1, 1] + cm[0, 1]) if (cm[1, 1] + cm[0, 1]) > 0 else 0
print(f"\n🎯 Win Rate (sur signaux prédits WIN): {win_rate*100:.2f}%")

# ==================== SAUVEGARDE ====================
print("\n" + "=" * 80)
print("💾 SAUVEGARDE MODÈLE ENSEMBLE")
print("=" * 80)

model_path = os.path.join(os.path.dirname(csv_path), MODEL_OUTPUT)

model_data = {
    'ensemble': ensemble,
    'lgbm_model': lgbm_model,
    'xgb_model': xgb_model,
    'cat_model': cat_model,
    'feature_cols': feature_cols,
    'weights': [lgbm_weight, xgb_weight, cat_weight],
    'individual_aucs': {
        'lgbm': lgbm_auc,
        'xgb': xgb_auc,
        'cat': cat_auc
    },
    'ensemble_auc': ensemble_auc,
    'training_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'n_samples': len(X),
    'n_features': len(feature_cols),
    'ensemble_method': 'soft_voting'
}

joblib.dump(model_data, model_path)
print(f"✅ Modèle sauvegardé: {model_path}")

file_size_mb = os.path.getsize(model_path) / (1024 * 1024)
print(f"📦 Taille: {file_size_mb:.2f} MB")

# ==================== RÉSUMÉ ====================
print("\n" + "=" * 80)
print("✅ ENSEMBLE METHODS TERMINÉ")
print("=" * 80)

print(f"\n📊 Résumé:")
print(f"   Modèles combinés: 3 (LightGBM, XGBoost, CatBoost)")
print(f"   Méthode: Soft Voting (moyenne pondérée des probabilités)")
print(f"   AUC Final: {ensemble_auc:.4f}")
print(f"   Features: {len(feature_cols)}")
print(f"   Samples: {len(X)}")

improvement = ensemble_auc - max(lgbm_auc, xgb_auc, cat_auc)
print(f"\n🎯 Amélioration vs meilleur modèle seul:")
print(f"   {improvement:+.4f} AUC")
print(f"   {improvement*100:+.2f}% d'amélioration" if improvement > 0 else f"   Pas d'amélioration")

print(f"\n🚀 Prochaines étapes:")
print(f"   1. Tester avec: python calibration_70_percent.py")
print(f"   2. Calibrer pour obtenir 70%+ confidence threshold")
print(f"   3. Backtest final")

print("\n" + "=" * 80)
