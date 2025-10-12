# CLAUDE RULES - Protocole de travail strict

**Dépôt GitHub :** `https://github.com/tradingluca31-boop/algo-poseidon`

---

## 🚨 RÈGLES ABSOLUES

### 1. **GitHub UNIQUEMENT**
- ✅ **Toute modification** se fait exclusivement sur le dépôt GitHub
- ❌ **ZÉRO intervention en local** : pas d'ouverture, édition ou écrasement de fichiers sur `/Users/luca` ou tout autre répertoire local
- ✅ Workflow : Clone temporaire → Modification → Commit → Push → Nettoyage

### 2. **HORODATAGE SYSTÉMATIQUE**
- ✅ Chaque commit doit inclure `[YYYY-MM-DD HH:MM]` dans le message
- ✅ Format : `[2025-10-01 14:30] Description du changement`

### 3. **DUPLICATION DE SÉCURITÉ**
- ✅ Créer une copie de sauvegarde avant toute grosse modification
- ✅ À la demande explicite de l'utilisateur
- ✅ Format : `fichier_YYYY-MM-DD_HHMM_backup.ext`
- ❌ Ne JAMAIS écraser l'original

### 4. **DONNÉES RÉELLES UNIQUEMENT**
- ✅ Utiliser **exclusivement des données réelles** (pas d'estimations)
- ✅ Vérifier systématiquement la base des calculs :
  - Formule
  - Unités
  - Périmètre
  - Fréquence
  - Timezone
  - NaN / Outliers
- ✅ Contrôle croisé quand pertinent

### 5. **SOURCES OFFICIELLES PRIORITAIRES**
- ✅ Priorité aux sources officielles et peer-reviewed
- ✅ Les liens communautaires servent au recoupement, pas à remplacer la documentation de référence
- ✅ Vérifier toujours sur le site **OFFICIEL MQL5** pour le code MT5

---

## 📚 RÉFÉRENCES GÉNÉRALES OBLIGATOIRES

- **MQL5 CodeBase** : https://www.mql5.com/fr/code/mt5
- **MetaTrader5 pour Python** : https://www.mql5.com/en/docs/python_metatrader5
- **Python (référence officielle)** : https://www.python.org/
- **MathsGPT** : https://mathsgpt.fr/

---

## 📊 1. STATS & SÉRIES TEMPORELLES

- **ISLR** (*An Introduction to Statistical Learning*) : https://www.statlearning.com/
- **Hyndman** – *Forecasting: Principles & Practice* : https://otexts.com/fpp3/
- **MIT 18.650** (Statistics for Applications) : https://ocw.mit.edu/courses/18-650-statistics-for-applications-fall-2016/

---

## 📈 2. ÉCONOMÉTRIE / SÉRIES EN PYTHON

- **statsmodels** (State Space) : https://www.statsmodels.org/stable/statespace.html
- **arch** (GARCH & volatilité) : https://arch.readthedocs.io/

---

## 🎲 3. STOCHASTIQUE & DÉRIVÉS

- **CMU** – Stochastic Calculus (Itô, Girsanov, Black–Scholes) : https://www.math.cmu.edu/~gautam/sj/teaching/2021-22/944-scalc-finance1/
- **Carr & Madan** (FFT pricing) : https://engineering.nyu.edu/sites/default/files/2018-08/CarrMadan2_0.pdf
- **QuantLib** (moteurs de pricing, courbes, modèles) : https://www.quantlib.org/
  - Docs Python : https://quantlib-python-docs.readthedocs.io/

---

## 🔧 4. OPTIMISATION & PORTEFEUILLE

- **CVXPY** : https://www.cvxpy.org/
- **SciPy Optimize** : https://docs.scipy.org/doc/scipy/reference/optimize.html
- **Ledoit–Wolf** (shrinkage covariance) : https://www.ledoit.net/honey.pdf

---

## ✅ 5. VALIDATION DE BACKTESTS & SUR-APPRENTISSAGE

- **Deflated Sharpe Ratio** : https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2460551
- **Probability of Backtest Overfitting (PBO)** : https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2326253
- **White (2000) Reality Check** : https://www.ssc.wisc.edu/~bhansen/teaching/WhiteRealityCheck.pdf
- **Hansen (SPA)** : https://www.ssc.wisc.edu/~bhansen/jae_2005_20_2.pdf
- **Stationary Bootstrap** (Politis & White, 2004) : https://public.econ.duke.edu/~ap172/Politis_White_2004.pdf
- **HAC / Newey–West** : https://cowles.yale.edu/sites/default/files/2022-08/d0877.pdf

---

## 🌐 6. VEILLE / COMMUNAUTÉS

- **Quantitative Finance StackExchange** : https://quant.stackexchange.com/
- **Quantocracy** : https://quantocracy.com/
- **SSRN** – Financial Economics Network : https://www.ssrn.com/en/fen/

---

## 🇫🇷 7. RESSOURCES FR (COURS/NOTES)

- **ENSAI** (poly de séries temporelles) : https://ensai.fr/wp-content/uploads/2019/06/Polyseriestemp.pdf
- **ENSAE** (cours séries) : https://www.ensae.fr/courses/146
- **Charpentier** – VAR, cointégration, ARCH/GARCH : https://www.jonathanbenchimol.com/data/teaching/eviews-training/charpentier2.pdf

---

## 📉 8. ANALYSE DE PERFORMANCE (OUTILS)

- **QuantStats** : https://github.com/ranaroussi/quantstats
- **PyFolio** : https://pyfolio.ml4trading.io/
- **Empyrical** : https://quantopian.github.io/empyrical/

---

## 🔄 WORKFLOW TYPE

```
1. Clone temporaire du dépôt GitHub dans /tmp
2. [Si demandé/grosse modif] Duplication du fichier → commit backup horodaté
3. Modification du fichier principal
4. Commit avec message horodaté : "[2025-10-01 14:30] Description du changement"
5. Push vers GitHub
6. Nettoyage du répertoire temporaire
```

---

## ⚠️ CONTRAINTES FINALES

- ❌ Aucune action en dehors du dépôt `tradingluca31-boop/Roles_claude`
- ✅ Historique clair et réversible via GitHub
- ✅ Traçabilité complète de tous les changements
- ✅ Possibilité de restaurer rapidement l'état précédent

---

**Dernière mise à jour :** 2025-10-01
