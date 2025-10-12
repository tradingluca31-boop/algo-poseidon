# -*- coding: utf-8 -*-
"""
Merge CSV MT5 (XAUUSD avec indicateurs) avec données macro (DXY/VIX/US10Y/SP500/NASDAQ/DOW)
"""

import pandas as pd
import os
from datetime import datetime

print("="*80)
print("MERGE MT5 + MACRO INDICATORS")
print("="*80)

# Chemins des fichiers
BASE_PATH = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
MT5_FILE = os.path.join(BASE_PATH, "XAUUSD_ML_Data_V3_FINAL_20Y.csv")
MACRO_FILE = r"C:\Users\lbye3\algo-poseidon\algo-poseidon\macro_data\ALL_MACRO_INDICATORS.csv"

OUTPUT_FILE = os.path.join(BASE_PATH, "XAUUSD_ML_Data_V3_FINAL_WITH_MACRO_20Y.csv")

print(f"\nFichier MT5: {MT5_FILE}")
print(f"Fichier Macro: {MACRO_FILE}")
print(f"Fichier output: {OUTPUT_FILE}")

# Vérifier que les fichiers existent
if not os.path.exists(MT5_FILE):
    print(f"\nERREUR: Fichier MT5 introuvable!")
    print(f"Verifie que tu as bien execute le script MQ5 dans MT5")
    exit(1)

if not os.path.exists(MACRO_FILE):
    print(f"\nERREUR: Fichier macro introuvable!")
    print(f"Verifie que export_macro_indicators_yahoo.py a bien fonctionne")
    exit(1)

print("\n" + "="*80)
print("CHARGEMENT DONNEES MT5")
print("="*80)

# Charger données MT5
df_mt5 = pd.read_csv(MT5_FILE)
df_mt5['time'] = pd.to_datetime(df_mt5['time'])

print(f"\nLignes MT5: {len(df_mt5)}")
print(f"Periode: {df_mt5['time'].min()} a {df_mt5['time'].max()}")
print(f"Colonnes: {list(df_mt5.columns)}")

print("\n" + "="*80)
print("CHARGEMENT DONNEES MACRO")
print("="*80)

# Charger données macro
df_macro = pd.read_csv(MACRO_FILE)
df_macro['Date'] = pd.to_datetime(df_macro['Date'])
df_macro.rename(columns={'Date': 'date'}, inplace=True)

print(f"\nLignes Macro: {len(df_macro)}")
print(f"Periode: {df_macro['date'].min()} a {df_macro['date'].max()}")
print(f"Colonnes: {list(df_macro.columns)}")

print("\n" + "="*80)
print("PREPARATION MERGE")
print("="*80)

# Normaliser les dates à minuit et retirer les timezones
df_mt5['date'] = df_mt5['time'].dt.normalize()
df_macro['date'] = pd.to_datetime(df_macro['date']).dt.tz_localize(None).dt.normalize()

# Garder uniquement les colonnes nécessaires du macro (DXY, VIX, US10Y, SP500, NASDAQ, DOW)
macro_cols = ['date', 'DXY', 'VIX', 'US10Y', 'SP500', 'NASDAQ', 'DOW']
df_macro_clean = df_macro[macro_cols].copy()

# Supprimer les doublons de dates dans macro (garder la dernière valeur du jour)
df_macro_clean = df_macro_clean.drop_duplicates(subset=['date'], keep='last')

print(f"\nDonnees macro apres nettoyage: {len(df_macro_clean)} jours uniques")

print("\n" + "="*80)
print("MERGE PAR DATE")
print("="*80)

# Merge par date (left join pour garder toutes les lignes MT5)
df_merged = df_mt5.merge(df_macro_clean, on='date', how='left')

print(f"\nLignes apres merge: {len(df_merged)}")

# Verifier les valeurs manquantes
missing_before = df_merged[['DXY', 'VIX', 'US10Y', 'SP500', 'NASDAQ', 'DOW']].isnull().sum()
print(f"\nValeurs manquantes AVANT forward fill:")
print(missing_before)

# Forward fill pour combler les jours manquants (weekends, jours fériés)
df_merged[['DXY', 'VIX', 'US10Y', 'SP500', 'NASDAQ', 'DOW']] = \
    df_merged[['DXY', 'VIX', 'US10Y', 'SP500', 'NASDAQ', 'DOW']].ffill()

# Backward fill pour les premières lignes si nécessaire
df_merged[['DXY', 'VIX', 'US10Y', 'SP500', 'NASDAQ', 'DOW']] = \
    df_merged[['DXY', 'VIX', 'US10Y', 'SP500', 'NASDAQ', 'DOW']].bfill()

missing_after = df_merged[['DXY', 'VIX', 'US10Y', 'SP500', 'NASDAQ', 'DOW']].isnull().sum()
print(f"\nValeurs manquantes APRES forward/backward fill:")
print(missing_after)

# Supprimer la colonne 'date' temporaire
df_merged = df_merged.drop(columns=['date'])

print("\n" + "="*80)
print("VERIFICATION FINALE")
print("="*80)

print(f"\nDimensions finales: {df_merged.shape[0]} lignes x {df_merged.shape[1]} colonnes")
print(f"\nColonnes finales:")
for i, col in enumerate(df_merged.columns, 1):
    print(f"   {i}. {col}")

print(f"\nApercu des 5 premieres lignes:")
print(df_merged.head())

print(f"\nStatistiques indicateurs macro:")
print(df_merged[['DXY', 'VIX', 'US10Y', 'SP500', 'NASDAQ', 'DOW']].describe())

print("\n" + "="*80)
print("SAUVEGARDE")
print("="*80)

# Sauvegarder
df_merged.to_csv(OUTPUT_FILE, index=False)

size_mb = os.path.getsize(OUTPUT_FILE) / (1024 * 1024)
print(f"\nFichier sauvegarde: {OUTPUT_FILE}")
print(f"Taille: {size_mb:.2f} MB")

print("\n" + "="*80)
print("MERGE TERMINE AVEC SUCCES!")
print("="*80)

print(f"\nProchaine etape: Re-entrainer le modele ML avec:")
print(f"   {OUTPUT_FILE}")
print(f"\nNouveaux features ajoutes:")
print(f"   - DXY (Dollar Index)")
print(f"   - VIX (Volatilite)")
print(f"   - US10Y (Taux 10 ans)")
print(f"   - SP500 (S&P 500)")
print(f"   - NASDAQ (NASDAQ Composite)")
print(f"   - DOW (Dow Jones)")
