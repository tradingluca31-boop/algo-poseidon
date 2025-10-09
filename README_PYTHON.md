# 🐍 Script Python - Enrichissement Données ML

## 📋 Description

Ce script Python enrichit les données XAUUSD exportées depuis MetaTrader 5 avec des données de marché supplémentaires depuis Yahoo Finance :

- **DXY** : Dollar Index (corrélation inverse avec l'or)
- **VIX** : Volatility Index (sentiment de marché)
- **US10Y** : Rendement obligations US 10 ans (taux d'intérêt)

Pour chaque actif, le script calcule **tous les indicateurs techniques** (EMA, RSI, MACD, ATR, ADX, Stochastic, Bollinger Bands, CCI, Volatilité).

---

## 🚀 Installation (Anaconda)

### Étape 1 : Ouvrir Anaconda Prompt

Rechercher "Anaconda Prompt" dans Windows et l'ouvrir.

### Étape 2 : Naviguer vers le dossier

```bash
cd C:\Users\lbye3\algo-poseidon\algo-poseidon
```

### Étape 3 : Installer les dépendances

```bash
pip install -r requirements.txt
```

**Note :** Si TA-Lib ne s'installe pas, c'est normal. Le script utilisera `pandas-ta` automatiquement.

---

## ▶️ Utilisation

### 1. Exécuter le script MQL5 dans MetaTrader 5

Le script `XAUUSD_ML_DataExport.mq5` doit d'abord générer le fichier CSV de base.

### 2. Lancer le script Python

Dans Anaconda Prompt :

```bash
python merge_yahoo_data.py
```

### 3. Résultat

Le script génère un fichier **`XAUUSD_COMPLETE_ML_Data.csv`** dans :

```
C:\Users\lbye3\AppData\Roaming\MetaQuotes\Terminal\Common\Files\
```

---

## 📊 Structure du fichier final

### Colonnes XAUUSD (originales)
- OHLCV, indicateurs techniques, signaux, features temporelles, target ML

### Colonnes DXY
- `dxy_ema21`, `dxy_ema55`, `dxy_rsi14`, `dxy_macd`, `dxy_atr14`, `dxy_adx14`, etc.

### Colonnes VIX
- `vix_ema21`, `vix_rsi14`, `vix_macd`, `vix_atr14`, `vix_bb_width`, etc.

### Colonnes US10Y
- `us10y_ema21`, `us10y_rsi14`, `us10y_macd`, `us10y_volatility`, etc.

**Total :** ~150+ colonnes prêtes pour le Machine Learning

---

## ⚙️ Configuration

Pour modifier les symboles ou périodes, éditez les variables au début du script :

```python
INPUT_CSV = "XAUUSD_ML_Data_10Y_2025.10.09.csv"
OUTPUT_CSV = "XAUUSD_COMPLETE_ML_Data.csv"

YAHOO_SYMBOLS = {
    'DXY': 'DX-Y.NYB',
    'VIX': '^VIX',
    'US10Y': '^TNX'
}
```

---

## 🐛 Dépannage

### Erreur : "Fichier introuvable"
→ Vérifiez que le script MQL5 a bien été exécuté et a généré le CSV

### Erreur : "No module named 'yfinance'"
→ Réinstallez : `pip install yfinance`

### Erreur : "TA-Lib compilation failed"
→ C'est normal, le script utilisera `pandas-ta` automatiquement

### Données Yahoo manquantes
→ Vérifiez votre connexion internet et que les symboles sont corrects

---

## 📈 Prochaines étapes ML

Une fois le fichier généré, vous pouvez :

1. Charger dans Jupyter Notebook / Google Colab
2. Entraîner un modèle de classification (RandomForest, XGBoost, LightGBM, Neural Network)
3. Prédire la colonne `target` (0=LOSS, 1=WIN)
4. Optimiser avec GridSearch / Optuna
5. Valider avec cross-validation temporelle

---

## 🤖 Auteur

Généré avec [Claude Code](https://claude.com/claude-code)
Date : 2025-10-09
