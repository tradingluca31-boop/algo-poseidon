"""
Script Python pour enrichir les données XAUUSD avec DXY, VIX, US10Y depuis Yahoo Finance
Pour Anaconda - Version 1.0 - 2025-10-09

Dépendances:
pip install yfinance pandas numpy ta-lib

Si ta-lib pose problème, utilisez:
pip install ta pandas-ta
"""

import pandas as pd
import numpy as np
import yfinance as yf
from datetime import datetime, timedelta
import os

print("=" * 80)
print("🚀 ENRICHISSEMENT DONNÉES ML - XAUUSD + DXY/VIX/US10Y")
print("=" * 80)

# ==================== CONFIGURATION ====================
# Détection automatique du fichier XAUUSD le plus récent
INPUT_CSV_PATTERN = "XAUUSD_ML_Data_*Y_*.csv"  # Pattern pour trouver le fichier
OUTPUT_CSV = "XAUUSD_COMPLETE_ML_Data_20Y.csv"  # Fichier final 20 ans

# Symboles Yahoo Finance
YAHOO_SYMBOLS = {
    'DXY': 'DX-Y.NYB',      # Dollar Index
    'VIX': '^VIX',          # Volatility Index
    'US10Y': '^TNX'         # US Treasury 10Y
}

# ==================== FONCTIONS INDICATEURS ====================

def calculate_indicators(df, prefix=''):
    """
    Calcule les indicateurs techniques pour un DataFrame de prix
    Compatible avec pandas-ta si ta-lib n'est pas disponible
    """
    print(f"   📊 Calcul des indicateurs pour {prefix}...")

    try:
        import talib as ta
        use_talib = True
        print(f"   ✅ Utilisation de TA-Lib")
    except ImportError:
        try:
            import pandas_ta as ta
            use_talib = False
            print(f"   ℹ️  Utilisation de pandas-ta (fallback)")
        except ImportError:
            print(f"   ⚠️  Aucune librairie d'indicateurs disponible!")
            return df

    # Nettoyer les colonnes existantes si rechargement
    cols_to_drop = [col for col in df.columns if col.startswith(prefix) and col != f'{prefix}close']
    df = df.drop(columns=cols_to_drop, errors='ignore')

    close = df['close'].values
    high = df['high'].values
    low = df['low'].values

    if use_talib:
        # TA-Lib
        df[f'{prefix}ema21'] = ta.EMA(close, timeperiod=21)
        df[f'{prefix}ema55'] = ta.EMA(close, timeperiod=55)
        df[f'{prefix}sma20'] = ta.SMA(close, timeperiod=20)
        df[f'{prefix}sma35'] = ta.SMA(close, timeperiod=35)
        df[f'{prefix}rsi14'] = ta.RSI(close, timeperiod=14)
        df[f'{prefix}rsi28'] = ta.RSI(close, timeperiod=28)
        df[f'{prefix}atr14'] = ta.ATR(high, low, close, timeperiod=14)
        df[f'{prefix}atr28'] = ta.ATR(high, low, close, timeperiod=28)

        # MACD custom (SMA-based)
        fast = ta.SMA(close, timeperiod=20)
        slow = ta.SMA(close, timeperiod=35)
        macd = fast - slow
        signal = ta.SMA(macd, timeperiod=15)
        df[f'{prefix}macd'] = macd
        df[f'{prefix}macd_signal'] = signal
        df[f'{prefix}macd_hist'] = macd - signal

        # ADX
        df[f'{prefix}adx14'] = ta.ADX(high, low, close, timeperiod=14)
        df[f'{prefix}di_plus'] = ta.PLUS_DI(high, low, close, timeperiod=14)
        df[f'{prefix}di_minus'] = ta.MINUS_DI(high, low, close, timeperiod=14)

        # Stochastic
        slowk, slowd = ta.STOCH(high, low, close, fastk_period=14, slowk_period=3, slowd_period=3)
        df[f'{prefix}stoch_k'] = slowk
        df[f'{prefix}stoch_d'] = slowd

        # Bollinger Bands
        upper, middle, lower = ta.BBANDS(close, timeperiod=20, nbdevup=2, nbdevdn=2)
        df[f'{prefix}bb_upper'] = upper
        df[f'{prefix}bb_middle'] = middle
        df[f'{prefix}bb_lower'] = lower
        df[f'{prefix}bb_width'] = upper - lower

        # CCI
        df[f'{prefix}cci20'] = ta.CCI(high, low, close, timeperiod=20)

    else:
        # pandas-ta
        df.ta.ema(length=21, append=True, col_names=(f'{prefix}ema21',))
        df.ta.ema(length=55, append=True, col_names=(f'{prefix}ema55',))
        df.ta.sma(length=20, append=True, col_names=(f'{prefix}sma20',))
        df.ta.sma(length=35, append=True, col_names=(f'{prefix}sma35',))
        df.ta.rsi(length=14, append=True, col_names=(f'{prefix}rsi14',))
        df.ta.rsi(length=28, append=True, col_names=(f'{prefix}rsi28',))
        df.ta.atr(length=14, append=True, col_names=(f'{prefix}atr14',))
        df.ta.atr(length=28, append=True, col_names=(f'{prefix}atr28',))

        # MACD custom
        fast = df['close'].rolling(20).mean()
        slow = df['close'].rolling(35).mean()
        macd = fast - slow
        signal = macd.rolling(15).mean()
        df[f'{prefix}macd'] = macd
        df[f'{prefix}macd_signal'] = signal
        df[f'{prefix}macd_hist'] = macd - signal

        df.ta.adx(length=14, append=True)
        df.ta.stoch(append=True)
        df.ta.bbands(length=20, std=2, append=True)
        df.ta.cci(length=20, append=True)

        # Renommer les colonnes pandas-ta
        rename_map = {
            'ADX_14': f'{prefix}adx14',
            'DMP_14': f'{prefix}di_plus',
            'DMN_14': f'{prefix}di_minus',
            'STOCHk_14_3_3': f'{prefix}stoch_k',
            'STOCHd_14_3_3': f'{prefix}stoch_d',
            'BBU_20_2.0': f'{prefix}bb_upper',
            'BBM_20_2.0': f'{prefix}bb_middle',
            'BBL_20_2.0': f'{prefix}bb_lower',
            'BBB_20_2.0': f'{prefix}bb_width',
            'CCI_20': f'{prefix}cci20'
        }
        df = df.rename(columns=rename_map)

    # Volatilité (écart-type annualisé des returns)
    returns = df['close'].pct_change()
    df[f'{prefix}volatility'] = returns.rolling(20).std() * np.sqrt(24 * 365)

    # Signaux
    df[f'{prefix}signal_ema'] = np.where(df[f'{prefix}ema21'] > df[f'{prefix}ema55'], 1,
                                          np.where(df[f'{prefix}ema21'] < df[f'{prefix}ema55'], -1, 0))
    df[f'{prefix}signal_macd'] = np.where(df[f'{prefix}macd_hist'] > 0, 1,
                                           np.where(df[f'{prefix}macd_hist'] < 0, -1, 0))

    # Signal price vs EMA21
    df[f'{prefix}signal_price'] = np.where(df['close'] > df[f'{prefix}ema21'], 1,
                                            np.where(df['close'] < df[f'{prefix}ema21'], -1, 0))

    return df


def download_yahoo_data(symbol, start_date, end_date, name):
    """
    Télécharge les données depuis Yahoo Finance
    IMPORTANT: Yahoo limite les données H1 à 730 jours (2 ans)
    On utilise donc les données journalières (1d) disponibles sur 10+ ans
    """
    print(f"\n📥 Téléchargement {name} ({symbol})...")

    try:
        # Utiliser interval='1d' au lieu de '1h' pour avoir 10 ans d'historique
        data = yf.download(symbol, start=start_date, end=end_date, interval='1d', progress=False)

        if data.empty:
            print(f"   ⚠️  Aucune donnée disponible pour {name}")
            return None

        # Nettoyer les colonnes (Yahoo retourne des multi-index parfois)
        if isinstance(data.columns, pd.MultiIndex):
            data.columns = data.columns.get_level_values(0)

        # Reset index pour avoir la colonne Date
        data = data.reset_index()

        # Normaliser les noms de colonnes
        data.columns = [col.lower() for col in data.columns]

        # Renommer Date/Datetime en time
        if 'date' in data.columns:
            data = data.rename(columns={'date': 'time'})
        elif 'datetime' in data.columns:
            data = data.rename(columns={'datetime': 'time'})

        # S'assurer que time est en datetime
        if 'time' in data.columns:
            data['time'] = pd.to_datetime(data['time'])
        else:
            print(f"   ⚠️  Colonne 'time' introuvable. Colonnes disponibles: {data.columns.tolist()}")
            return None

        print(f"   ✅ {len(data)} barres téléchargées pour {name}")
        return data

    except Exception as e:
        print(f"   ❌ Erreur lors du téléchargement de {name}: {e}")
        return None


# ==================== SCRIPT PRINCIPAL ====================

# 1. Charger le CSV XAUUSD depuis MQL5
print("\n" + "=" * 80)
print("📂 CHARGEMENT DONNÉES XAUUSD")
print("=" * 80)

# Trouver le fichier XAUUSD le plus récent
base_path = r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
import glob

# Chercher tous les fichiers XAUUSD_ML_Data
pattern = os.path.join(base_path, "XAUUSD_ML_Data_*Y_*.csv")
files = glob.glob(pattern)

if not files:
    print(f"❌ ERREUR: Aucun fichier XAUUSD trouvé dans {base_path}")
    print(f"Vérifiez que le script MQL5 a bien été exécuté.")
    exit(1)

# Prendre le plus récent
csv_path = max(files, key=os.path.getmtime)
print(f"📂 Fichier détecté: {os.path.basename(csv_path)}")

df_xauusd = pd.read_csv(csv_path)
df_xauusd['time'] = pd.to_datetime(df_xauusd['time'])
df_xauusd = df_xauusd.sort_values('time').reset_index(drop=True)

print(f"✅ {len(df_xauusd)} lignes chargées depuis {os.path.basename(csv_path)}")
print(f"Période: {df_xauusd['time'].min()} → {df_xauusd['time'].max()}")

# Extraire les dates
start_date = df_xauusd['time'].min() - timedelta(days=1)  # Marge de sécurité
end_date = df_xauusd['time'].max() + timedelta(days=1)

# 2. Télécharger les données Yahoo Finance
print("\n" + "=" * 80)
print("🌐 TÉLÉCHARGEMENT DONNÉES YAHOO FINANCE")
print("=" * 80)

yahoo_data = {}
for name, symbol in YAHOO_SYMBOLS.items():
    df = download_yahoo_data(symbol, start_date, end_date, name)
    if df is not None:
        yahoo_data[name] = df

if not yahoo_data:
    print("\n❌ ERREUR: Aucune donnée Yahoo Finance téléchargée!")
    print("Vérifiez votre connexion internet ou les symboles Yahoo.")
    exit(1)

# 3. Calculer les indicateurs pour chaque source Yahoo
print("\n" + "=" * 80)
print("📊 CALCUL INDICATEURS TECHNIQUES")
print("=" * 80)

for name, df in yahoo_data.items():
    yahoo_data[name] = calculate_indicators(df, prefix=f'{name.lower()}_')

# 4. Fusionner avec XAUUSD (merge asof pour alignement temporel)
print("\n" + "=" * 80)
print("🔗 FUSION DES DONNÉES")
print("=" * 80)

df_final = df_xauusd.copy()
df_final = df_final.sort_values('time')

for name, df in yahoo_data.items():
    print(f"\n🔄 Fusion avec {name}...")

    df = df.sort_values('time')

    # Merge asof: trouve la valeur la plus proche dans le temps
    # Les données Yahoo sont journalières, XAUUSD est H1
    # Chaque barre XAUUSD H1 récupère les valeurs du jour correspondant
    df_final = pd.merge_asof(
        df_final,
        df.drop(columns=['open', 'high', 'low', 'close', 'volume'], errors='ignore'),
        on='time',
        direction='backward',  # Utilise la dernière valeur journalière disponible
        tolerance=pd.Timedelta('2d')  # Max 2 jours d'écart (weekend)
    )

    print(f"   ✅ {name} fusionné (données journalières répliquées sur H1)")

# 5. Nettoyer les NaN
print(f"\n🧹 Nettoyage des valeurs manquantes...")
initial_rows = len(df_final)
df_final = df_final.dropna()
final_rows = len(df_final)
print(f"   Lignes supprimées: {initial_rows - final_rows}")
print(f"   Lignes finales: {final_rows}")

# 6. Exporter le fichier final
print("\n" + "=" * 80)
print("💾 EXPORT FICHIER FINAL")
print("=" * 80)

output_path = os.path.join(r"C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files", OUTPUT_CSV)
df_final.to_csv(output_path, index=False)

print(f"✅ Fichier exporté: {output_path}")
print(f"📊 Nombre de colonnes: {len(df_final.columns)}")
print(f"📈 Nombre de lignes: {len(df_final)}")

# 7. Résumé des colonnes
print("\n" + "=" * 80)
print("📋 COLONNES DU FICHIER FINAL")
print("=" * 80)

print("\n🔹 XAUUSD:")
xau_cols = [col for col in df_final.columns if not any(col.startswith(x) for x in ['dxy_', 'vix_', 'us10y_'])]
print(f"   {len(xau_cols)} colonnes")

for name in YAHOO_SYMBOLS.keys():
    prefix = f"{name.lower()}_"
    cols = [col for col in df_final.columns if col.startswith(prefix)]
    print(f"\n🔹 {name}:")
    print(f"   {len(cols)} colonnes: {', '.join(cols[:5])}...")

print("\n" + "=" * 80)
print("✅ ENRICHISSEMENT TERMINÉ AVEC SUCCÈS!")
print("=" * 80)
print(f"\n🎯 Fichier prêt pour le Machine Learning:")
print(f"   📁 {output_path}")
print(f"   📊 {len(df_final)} lignes × {len(df_final.columns)} colonnes")
print("\n🚀 Vous pouvez maintenant utiliser ce fichier pour entraîner votre modèle ML!")
