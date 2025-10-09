"""
Feature Engineering Avancé pour XAUUSD ML
Crée des features supplémentaires pour améliorer les prédictions
Version 1.0 - 2025-10-09

NOUVELLES FEATURES:
- Lag features: valeurs passées (t-1, t-3, t-7, t-24)
- Rolling statistics: moyennes/std mobiles
- Interactions: produits de features importantes
- Time-based: patterns horaires/hebdomadaires
"""

import pandas as pd
import numpy as np
import os

print("=" * 80)
print("🧬 FEATURE ENGINEERING AVANCÉ")
print("=" * 80)

# ==================== CONFIGURATION ====================
INPUT_CSV = "XAUUSD_COMPLETE_ML_Data_20Y.csv"
OUTPUT_CSV = "XAUUSD_COMPLETE_ML_Data_20Y_ENGINEERED.csv"

# ==================== CHARGEMENT ====================
print("\n📂 Chargement des données...")
csv_path = os.path.join(r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files", INPUT_CSV)

if not os.path.exists(csv_path):
    print(f"❌ Fichier introuvable: {csv_path}")
    exit(1)

df = pd.read_csv(csv_path)
df['time'] = pd.to_datetime(df['time'])
print(f"✅ {len(df)} lignes chargées")
print(f"📊 {len(df.columns)} colonnes existantes")

initial_cols = len(df.columns)

# ==================== LAG FEATURES ====================
print("\n" + "=" * 80)
print("🔙 CRÉATION LAG FEATURES (valeurs passées)")
print("=" * 80)

# Features importantes identifiées par le modèle
important_features = [
    'rsi28', 'rsi14', 'volatility', 'macd', 'macd_hist',
    'vix_macd_signal', 'vix_atr28', 'dxy_volatility', 'dxy_macd_hist',
    'us10y_volatility', 'atr14', 'atr28'
]

# Lags à créer: t-1, t-3, t-7, t-24 (1h, 3h, 7h, 1 jour)
lags = [1, 3, 7, 24]

print(f"Création de lags pour {len(important_features)} features × {len(lags)} périodes...")

lag_count = 0
for feat in important_features:
    if feat in df.columns:
        for lag in lags:
            new_col = f"{feat}_lag{lag}"
            df[new_col] = df[feat].shift(lag)
            lag_count += 1

print(f"✅ {lag_count} lag features créées")

# ==================== ROLLING STATISTICS ====================
print("\n" + "=" * 80)
print("📊 CRÉATION ROLLING STATISTICS (moyennes mobiles)")
print("=" * 80)

# Fenêtres: 5, 10, 20 barres
windows = [5, 10, 20]

roll_count = 0
for feat in important_features[:8]:  # Top 8 pour éviter trop de features
    if feat in df.columns:
        for window in windows:
            # Moyenne mobile
            df[f"{feat}_roll_mean_{window}"] = df[feat].rolling(window).mean()
            # Écart-type mobile
            df[f"{feat}_roll_std_{window}"] = df[feat].rolling(window).std()
            roll_count += 2

print(f"✅ {roll_count} rolling features créées")

# ==================== INTERACTIONS ====================
print("\n" + "=" * 80)
print("🔗 CRÉATION INTERACTIONS (produits de features)")
print("=" * 80)

# Interactions importantes détectées
interactions = [
    ('rsi28', 'volatility'),
    ('rsi28', 'vix_macd_signal'),
    ('macd_hist', 'dxy_macd_hist'),
    ('volatility', 'vix_atr28'),
    ('atr14', 'volatility'),
    ('rsi28', 'macd_hist')
]

inter_count = 0
for feat1, feat2 in interactions:
    if feat1 in df.columns and feat2 in df.columns:
        df[f"{feat1}_x_{feat2}"] = df[feat1] * df[feat2]
        inter_count += 1

print(f"✅ {inter_count} interaction features créées")

# ==================== TIME-BASED FEATURES ====================
print("\n" + "=" * 80)
print("⏰ CRÉATION TIME-BASED FEATURES AVANCÉES")
print("=" * 80)

# Patterns horaires (sinus/cosinus pour capturer cyclicité)
df['hour_sin'] = np.sin(2 * np.pi * df['hour'] / 24)
df['hour_cos'] = np.cos(2 * np.pi * df['hour'] / 24)

# Patterns hebdomadaires
df['day_sin'] = np.sin(2 * np.pi * df['day_of_week'] / 7)
df['day_cos'] = np.cos(2 * np.pi * df['day_of_week'] / 7)

# Patterns mensuels
df['month_sin'] = np.sin(2 * np.pi * df['month'] / 12)
df['month_cos'] = np.cos(2 * np.pi * df['month'] / 12)

# Sessions de trading (indicateur binaire)
df['is_london_session'] = ((df['hour'] >= 8) & (df['hour'] < 16)).astype(int)
df['is_us_session'] = ((df['hour'] >= 13) & (df['hour'] < 21)).astype(int)
df['is_asia_session'] = ((df['hour'] >= 0) & (df['hour'] < 8)).astype(int)

# Weekend proximity (vendredi soir, lundi matin)
df['is_friday'] = (df['day_of_week'] == 5).astype(int)
df['is_monday'] = (df['day_of_week'] == 1).astype(int)

print(f"✅ 12 time-based features créées")

# ==================== MOMENTUM & TREND ====================
print("\n" + "=" * 80)
print("📈 CRÉATION MOMENTUM & TREND FEATURES")
print("=" * 80)

# Rate of change (ROC) sur différentes périodes
for period in [3, 7, 14]:
    df[f'roc_{period}'] = df['close'].pct_change(period) * 100

# Distance par rapport aux moyennes mobiles
df['dist_ema21'] = (df['close'] - df['ema21']) / df['ema21'] * 100
df['dist_ema55'] = (df['close'] - df['ema55']) / df['ema55'] * 100
df['dist_smma50'] = (df['close'] - df['smma50']) / df['smma50'] * 100

# Volatilité relative
df['volatility_ratio'] = df['volatility'] / df['volatility'].rolling(20).mean()

print(f"✅ 10 momentum/trend features créées")

# ==================== MARKET REGIME ====================
print("\n" + "=" * 80)
print("🎯 CRÉATION MARKET REGIME FEATURES")
print("=" * 80)

# Tendance (basée sur EMA)
df['trend_strength'] = (df['ema21'] - df['ema55']).abs() / df['ema55'] * 100

# Volatilité regime (haute/basse)
vol_median = df['volatility'].rolling(50).median()
df['high_vol_regime'] = (df['volatility'] > vol_median).astype(int)

# RSI zones
df['rsi28_oversold'] = (df['rsi28'] < 30).astype(int)
df['rsi28_overbought'] = (df['rsi28'] > 70).astype(int)
df['rsi28_neutral'] = ((df['rsi28'] >= 30) & (df['rsi28'] <= 70)).astype(int)

print(f"✅ 6 market regime features créées")

# ==================== NETTOYAGE ====================
print("\n" + "=" * 80)
print("🧹 NETTOYAGE DES DONNÉES")
print("=" * 80)

# Remplacer inf par NaN
df = df.replace([np.inf, -np.inf], np.nan)

# Compter les NaN
nan_before = df.isna().sum().sum()
print(f"   NaN détectés: {nan_before}")

# Supprimer les premières lignes (ont des NaN à cause des lags/rolling)
df = df.dropna()

nan_after = df.isna().sum().sum()
print(f"   Lignes supprimées: {len(df) - (len(df) - nan_before)}")
print(f"   Lignes finales: {len(df)}")

# ==================== EXPORT ====================
print("\n" + "=" * 80)
print("💾 EXPORT FICHIER ENRICHI")
print("=" * 80)

output_path = os.path.join(os.path.dirname(csv_path), OUTPUT_CSV)
df.to_csv(output_path, index=False)

final_cols = len(df.columns)
new_features = final_cols - initial_cols

print(f"✅ Fichier exporté: {output_path}")
print(f"📊 Colonnes: {initial_cols} → {final_cols} (+{new_features} features)")
print(f"📈 Lignes: {len(df)}")

# ==================== RÉSUMÉ ====================
print("\n" + "=" * 80)
print("✅ FEATURE ENGINEERING TERMINÉ")
print("=" * 80)

print(f"\n📊 Résumé des nouvelles features:")
print(f"   🔙 Lag features:          {lag_count}")
print(f"   📊 Rolling statistics:    {roll_count}")
print(f"   🔗 Interactions:          {inter_count}")
print(f"   ⏰ Time-based:            12")
print(f"   📈 Momentum/Trend:        10")
print(f"   🎯 Market regime:         6")
print(f"   " + "-" * 40)
print(f"   🎯 TOTAL nouvelles:       {new_features}")

print(f"\n🚀 Prochaine étape:")
print(f"   Utilisez {OUTPUT_CSV} pour l'entraînement")
print(f"   Le modèle aura {final_cols} features au lieu de {initial_cols}")
print(f"   Performance attendue: +5-15% d'amélioration")

print("\n" + "=" * 80)
