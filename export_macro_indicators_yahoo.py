# -*- coding: utf-8 -*-
"""
Export DXY, VIX, US10Y, S&P500, NASDAQ, Dow Jones depuis Yahoo Finance
Période: 1er janvier 2008 à aujourd'hui
"""

import yfinance as yf
import pandas as pd
from datetime import datetime
import os

print("="*80)
print("EXPORT INDICATEURS MACRO DEPUIS YAHOO FINANCE")
print("="*80)

# Configuration
START_DATE = "2008-01-01"
END_DATE = datetime.now().strftime("%Y-%m-%d")

# Symboles Yahoo Finance
SYMBOLS = {
    "DXY": "DX-Y.NYB",      # Dollar Index
    "VIX": "^VIX",          # Volatilité
    "US10Y": "^TNX",        # Taux 10 ans US (en %)
    "SP500": "^GSPC",       # S&P 500
    "NASDAQ": "^IXIC",      # NASDAQ Composite
    "DOW": "^DJI"           # Dow Jones Industrial Average
}

print(f"\nPériode: {START_DATE} à {END_DATE}")
print(f"\nIndicateurs à télécharger:")
for name, symbol in SYMBOLS.items():
    print(f"   - {name}: {symbol}")

# Créer dossier output si n'existe pas
output_dir = os.path.join(os.path.dirname(__file__), "macro_data")
os.makedirs(output_dir, exist_ok=True)

print(f"\nDossier output: {output_dir}")
print("\n" + "="*80)

# Télécharger chaque indicateur
all_data = {}

for name, symbol in SYMBOLS.items():
    print(f"\nTéléchargement {name} ({symbol})...")

    try:
        # Télécharger les données
        ticker = yf.Ticker(symbol)
        df = ticker.history(start=START_DATE, end=END_DATE, interval="1d")

        if df.empty:
            print(f"   ERREUR: Aucune donnée pour {name}")
            continue

        # Garder uniquement Close et renommer
        df = df[['Close']].copy()
        df.rename(columns={'Close': name}, inplace=True)

        # Sauvegarder individuellement
        output_file = os.path.join(output_dir, f"{name}.csv")
        df.to_csv(output_file)

        print(f"   OK: {len(df)} lignes téléchargées")
        print(f"   Période: {df.index.min().date()} à {df.index.max().date()}")
        print(f"   Fichier: {output_file}")

        # Stocker pour merge
        all_data[name] = df

    except Exception as e:
        print(f"   ERREUR: {e}")

print("\n" + "="*80)

# Merger toutes les données dans un seul fichier
if all_data:
    print("\nMerge de tous les indicateurs...")

    # Combiner tous les DataFrames
    df_merged = pd.concat(all_data.values(), axis=1, join='outer')

    # Trier par date
    df_merged.sort_index(inplace=True)

    # Forward fill pour remplir les valeurs manquantes (jours non-ouvrés)
    df_merged.ffill(inplace=True)

    # Sauvegarder le fichier mergé
    merged_file = os.path.join(output_dir, "ALL_MACRO_INDICATORS.csv")
    df_merged.to_csv(merged_file)

    print(f"\nFichier mergé créé: {merged_file}")
    print(f"Dimensions: {df_merged.shape[0]} lignes x {df_merged.shape[1]} colonnes")
    print(f"\nAperçu des données:")
    print(df_merged.head())
    print("\n" + df_merged.tail())

    # Statistiques
    print(f"\nStatistiques:")
    print(df_merged.describe())

    # Valeurs manquantes
    missing = df_merged.isnull().sum()
    if missing.sum() > 0:
        print(f"\nValeurs manquantes après forward fill:")
        print(missing[missing > 0])
    else:
        print("\nAucune valeur manquante après forward fill")

print("\n" + "="*80)
print("EXPORT TERMINÉ")
print("="*80)

# Afficher les fichiers créés
print(f"\nFichiers créés dans: {output_dir}")
for file in os.listdir(output_dir):
    if file.endswith(".csv"):
        filepath = os.path.join(output_dir, file)
        size_kb = os.path.getsize(filepath) / 1024
        print(f"   - {file} ({size_kb:.1f} KB)")

print(f"\nProchaine étape: Merger avec le CSV exporté de MT5")
