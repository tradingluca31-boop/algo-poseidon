"""
Hyperparameter Tuning avec Optuna pour LightGBM
Optimisation automatique pour trouver les meilleurs paramètres
Version 1.0 - 2025-10-09

OBJECTIF:
- Tester 200 combinaisons de paramètres
- Maximiser l'AUC sur validation
- Sauvegarder le meilleur modèle
"""

import pandas as pd
import numpy as np
import lightgbm as lgb
import optuna
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import roc_auc_score
import joblib
import os
from datetime import datetime

print("=" * 80)
print("⚙️ HYPERPARAMETER TUNING - OPTUNA + LIGHTGBM")
print("=" * 80)

# ==================== CONFIGURATION ====================
INPUT_CSV = "XAUUSD_COMPLETE_ML_Data_20Y_ENGINEERED.csv"
MODEL_OUTPUT = "xauusd_lightgbm_optimized_model.pkl"
N_TRIALS = 200  # Nombre d'essais Optuna
N_SPLITS = 3    # Cross-validation folds

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

# ==================== FONCTION OBJECTIF ====================
def objective(trial):
    """
    Fonction objectif pour Optuna
    Teste une combinaison de paramètres et retourne l'AUC
    """

    # Paramètres à optimiser
    params = {
        'objective': 'binary',
        'metric': 'auc',
        'boosting_type': 'gbdt',
        'verbosity': -1,
        'random_state': 42,

        # Paramètres à optimiser
        'num_leaves': trial.suggest_int('num_leaves', 20, 100),
        'learning_rate': trial.suggest_float('learning_rate', 0.01, 0.3, log=True),
        'feature_fraction': trial.suggest_float('feature_fraction', 0.5, 1.0),
        'bagging_fraction': trial.suggest_float('bagging_fraction', 0.5, 1.0),
        'bagging_freq': trial.suggest_int('bagging_freq', 1, 10),
        'min_child_samples': trial.suggest_int('min_child_samples', 5, 100),
        'max_depth': trial.suggest_int('max_depth', 3, 12),
        'lambda_l1': trial.suggest_float('lambda_l1', 1e-8, 10.0, log=True),
        'lambda_l2': trial.suggest_float('lambda_l2', 1e-8, 10.0, log=True),
    }

    # Cross-validation temporelle
    tscv = TimeSeriesSplit(n_splits=N_SPLITS)
    auc_scores = []

    for train_idx, val_idx in tscv.split(X):
        X_train, X_val = X.iloc[train_idx], X.iloc[val_idx]
        y_train, y_val = y.iloc[train_idx], y.iloc[val_idx]

        train_data = lgb.Dataset(X_train, label=y_train)
        val_data = lgb.Dataset(X_val, label=y_val, reference=train_data)

        model = lgb.train(
            params,
            train_data,
            num_boost_round=500,
            valid_sets=[val_data],
            callbacks=[
                lgb.early_stopping(stopping_rounds=50, verbose=False),
                lgb.log_evaluation(period=0)
            ]
        )

        y_pred_proba = model.predict(X_val, num_iteration=model.best_iteration)
        auc = roc_auc_score(y_val, y_pred_proba)
        auc_scores.append(auc)

    return np.mean(auc_scores)

# ==================== OPTIMISATION ====================
print("\n" + "=" * 80)
print(f"🚀 LANCEMENT OPTIMISATION ({N_TRIALS} essais)")
print("=" * 80)
print(f"⏱️  Temps estimé: {N_TRIALS * N_SPLITS * 10 // 60} minutes")
print(f"💡 Vous pouvez interrompre avec CTRL+C, le meilleur modèle sera sauvegardé")

study = optuna.create_study(direction='maximize', study_name='lightgbm_tuning')

# Callback pour afficher la progression
def callback(study, trial):
    if trial.number % 10 == 0:
        print(f"\n📊 Essai {trial.number}/{N_TRIALS}")
        print(f"   Meilleur AUC: {study.best_value:.4f}")
        print(f"   AUC actuel: {trial.value:.4f}")

study.optimize(objective, n_trials=N_TRIALS, callbacks=[callback], show_progress_bar=True)

# ==================== RÉSULTATS ====================
print("\n" + "=" * 80)
print("✅ OPTIMISATION TERMINÉE")
print("=" * 80)

print(f"\n🏆 Meilleur AUC: {study.best_value:.4f}")
print(f"\n📊 Meilleurs paramètres:")
for key, value in study.best_params.items():
    print(f"   {key:<20} {value}")

# ==================== ENTRAÎNEMENT MODÈLE FINAL ====================
print("\n" + "=" * 80)
print("🏆 ENTRAÎNEMENT MODÈLE FINAL AVEC MEILLEURS PARAMÈTRES")
print("=" * 80)

best_params = study.best_params.copy()
best_params.update({
    'objective': 'binary',
    'metric': 'auc',
    'boosting_type': 'gbdt',
    'verbosity': -1,
    'random_state': 42
})

train_data = lgb.Dataset(X, label=y)

print("🚀 Entraînement en cours...")
final_model = lgb.train(
    best_params,
    train_data,
    num_boost_round=1000,
    valid_sets=[train_data],
    callbacks=[
        lgb.early_stopping(stopping_rounds=100, verbose=False),
        lgb.log_evaluation(period=100)
    ]
)

print(f"✅ Modèle final entraîné avec {final_model.best_iteration} arbres")

# ==================== SAUVEGARDE ====================
print("\n" + "=" * 80)
print("💾 SAUVEGARDE MODÈLE OPTIMISÉ")
print("=" * 80)

model_path = os.path.join(os.path.dirname(csv_path), MODEL_OUTPUT)

model_data = {
    'model': final_model,
    'feature_cols': feature_cols,
    'best_params': best_params,
    'best_auc': study.best_value,
    'n_trials': N_TRIALS,
    'training_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'n_samples': len(X),
    'n_features': len(feature_cols),
    'optimized': True
}

joblib.dump(model_data, model_path)
print(f"✅ Modèle sauvegardé: {model_path}")

file_size_mb = os.path.getsize(model_path) / (1024 * 1024)
print(f"📦 Taille: {file_size_mb:.2f} MB")

# ==================== RÉSUMÉ ====================
print("\n" + "=" * 80)
print("✅ HYPERPARAMETER TUNING TERMINÉ")
print("=" * 80)

print(f"\n📊 Résumé:")
print(f"   Essais: {N_TRIALS}")
print(f"   Meilleur AUC: {study.best_value:.4f}")
print(f"   Features: {len(feature_cols)}")
print(f"   Samples: {len(X)}")

print(f"\n🎯 Amélioration attendue vs modèle de base:")
print(f"   AUC: 0.9541 → {study.best_value:.4f} ({study.best_value - 0.9541:+.4f})")

print(f"\n🚀 Prochaines étapes:")
print(f"   1. Tester avec: python backtest_lightgbm.py")
print(f"      (modifiez INPUT pour utiliser {MODEL_OUTPUT})")
print(f"   2. Si bon → Ensemble Methods")
print(f"   3. Si excellent → Calibration 70%+")

print("\n" + "=" * 80)
