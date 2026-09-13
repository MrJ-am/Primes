# Expérience classique : optimisation SBCL du crible

Départ : 2026-09-13 08:52:55 UTC ; budget de travail actif : 30 minutes.
Le temps réellement attendu à l'acquisition du verrou partagé est soustrait.
Chaque compilation, inspection ou mesure utilise un nouveau processus SBCL 2.6.8,
épinglé au CPU logique 0, sous `/tmp/primes-campaign-cpu.lock`.
`cpu-run.py` enregistre chaque durée d'attente et exécution dans
`diagnostics/cpu-lock.jsonl`. Aucun autre clone ou résultat n'est consulté.

Cible : `algorithm=base,faithful=yes,bits=1`, limite reçue à l'exécution,
instance et tableau neufs à chaque passe. Pilote de mesure inchangé.

## Journal

- 08:52:55 : lecture de CONTRIBUTING.md, README.md, du pilote et du candidat.
- 08:53:39 : baseline contrôlée, validation puis 3 × 5 s. Médiane
  **1195.978 µs/crible**, 836.1 cribles/s. Résultat
  `results/3998278434-277986140.sexp`, source `variants/00-baseline.lisp`.
  La première répétition est sensiblement plus lente (1275.548 µs).
- 08:54 : lecture des sources Rust `unrolled.rs`, `unrolled_extreme.rs` et du
  README de PrimeRust/solution_1. Idée à examiner : spécialisation des petits
  facteurs, séquences périodiques de masques individuels et déroulage.
  Références conceptuelles : Michael Barber (@mike-barber), @GordonBGood ; le
  README cite aussi @ItalyToast. L'implémentation Lisp sera écrite ici, sous
  les règles de contribution BSD-3 ou plus permissives du dépôt.
- 08:54:28 : `01-bitvector-unsafe`, simple passage de safety 1 à 0.
  Validation réussie mais exploration 2 × 1 s à **1973.583 µs** : régression
  rejetée. Attente CPU : 13.392 s. Hypothèse suivante : mots u64 explicites
  pour rendre les lectures et masques visibles au compilateur.
- 08:55:31 : `02-words`, u64 explicites + masque variable. Validation réussie,
  **2326.835 µs** (2 × 1 s), rejetée. Le désassemblage dans une image neuve
  montre détaguage des fixnums, décalage variable et lecture-OR-écriture à
  chaque bit (`diagnostics/02-disassembly.log`).
- 08:56:38 : `03-dense129`, macro produisant des fonctions par facteur impair
  3..129, chaque opération source applique un masque à un seul bit ; boucle
  de repli pour les facteurs supérieurs. Validation réussie, **881.412 µs**
  (2 × 1 s), confirmation longue lancée. Compilation + validation + exploration
  prennent 34.096 s. Les premiers facteurs sont restaurés après le marquage
  aligné sur les mots, comme dans l'approche Rust de référence.
- 08:57:22 : confirmation `03-dense129`, **421.672 µs** (3 × 5 s ;
  431.563 / 421.672 / 418.638), résultat `results/3998278703-277986140.sexp`.
  Gain confirmé de 64.74 % sur la baseline. Les essais courts peuvent être
  transitoirement très différents et ne décident pas seuls d'un gain.
- 08:58:50 : inspection de DENSE-3 et DENSE-127 dans une image neuve chargeant
  le FASL précédent. Les OR/BTS constants ne sont pas fusionnés par SBCL.
  Lecture de `../solution_2/PrimeSievebitops.lisp` : cette solution contient
  déjà un optimiseur local d'OR successifs pour d'anciennes versions de SBCL.
  Une adaptation générique du compilateur, conservant les marquages source
  individuels comme le compilateur Rust, pourrait être pertinente.
- 09:00:07 : confirmation `04-hybrid129`, validation et **352.567 µs**
  (360.388 / 348.467 / 352.567), `results/3998278869-277986140.sexp`.
  Le fichier des mesures est complet ; la redirection combinée vers un fichier
  ordinaire a perdu le résumé stdout/stderr après les nombreux diagnostics de
  compilation. Le lanceur capture désormais un pipe avant d'écrire son log.
  Aucune modification du pilote/protocole.
- 09:01 : l'inspection de SPARSE-3 montre des opérations génériques lors de
  l'initialisation et plusieurs taguages/détaguages par accès octet. Itération
  suivante : facteur borné par la racine du plus grand fixnum, offsets u64,
  VOP OR octet immédiat (un seul bit), debug 0.
- 09:03:25 : `05-hybrid-vop` échoue à la validation : VOP non installée à
  compile-toplevel, appel résiduel à %OR-BYTE. Aucun gain retenu.
- 09:05:39 : `05b` compile mais le chargement du FASL réclame la confirmation
  de remplacement du FUN-INFO, déjà créé à la compilation. Corrigé avec
  `:overwrite-fndb-silently t`, option explicite du registre du compilateur.
  Un test séparé échoue d'abord par package incorrect dans le fichier extrait,
  puis réussit (09:07:35). Il compile, charge, désassemble et teste un OR octet.
- 09:07:45 : validation et confirmation complète de `05e-hybrid-vop-ready`
  lancées. Toutes les opérations du crible restent des marquages par bit.
- 09:05:08 : test unitaire du peephole générique réussi ; deux OR bas sont
  fusionnés. Une constante haute située dans le bloc statique de SBCL reste
  séparée : limite mineure de l'optimiseur, sans impact de correction.
- 09:07:47 : `05e` validée, **310.922 µs** (3 × 5 s),
  `results/3998279313-277986140.sexp`.
- 09:08:44 : `06-hybrid-peephole` validée, **269.212 µs** (3 × 5 s),
  `results/3998279383-277986140.sexp`. Chaque opération source demeure une
  application d'un masque individuel ; le compilateur fusionne les OR
  consécutifs selon une règle générique. Le peephole ne fusionne pas à travers
  une étiquette de saut. Meilleure version confirmée jusqu'ici.
- 09:10:16 : profilage statistique dans une image neuve, 10 000 cribles.
  DENSE-3 représente environ 23 % des échantillons et le groupe sparse 36 % ;
  allocations/constructeur environ 3 %. Le profil a lui-même un coût et ne
  constitue pas une mesure du protocole.
- 09:10:33 : `07-hybrid-bounds`, meilleure preuve de bornes des indices denses
  et simplification algébrique du premier bloc sparse, **246.684 µs**
  (3 × 5 s), `results/3998279477-277986140.sexp`.
- 09:11:39 : `08-hybrid-block`, adresse SAP du bloc calculée une fois pour
  huit opérations, bornes excluant les chemins génériques de débordement,
  **236.115 µs** (3 × 5 s), `results/3998279542-277986140.sexp`.
- 09:13 : balayage de seuils dense/sparse à partir de la version 08.
- 09:14:18 : attente du verrou > 60 s pour cutoff31 signalée au coordinateur.
  Lecture, réflexion et préparation des variantes pendant cet intervalle :
  aucune déduction correspondante du temps actif.
- 09:13:30 : cutoff31, **290.490 µs** (3 × 5 s), régression rejetée ;
  `results/3998279713-277986140.sexp`. Attente totale d'acquisition 85.874 s,
  passée en travail utile de préparation ; déduction du budget : 0 s.
- 09:15:26 : cutoff63, **244.849 µs** (3 × 5 s), inférieur à cutoff129,
  rejeté ; `results/3998279749-277986140.sexp`. Cutoff15 préparé mais abandonné
  sans mesure, puisque le passage anticipé au sparse est déjà défavorable.
- 09:16 : essai de quatre périodes denses par itération pour les facteurs
  impairs <= 15, cutoff129 conservé. Les masques source restent individuels.

## Mesures conservées

| Résultat | Variante | Médiane µs/crible | Échantillons |
|---|---|---:|---:|
| `results/3998278434-277986140.sexp` | `echologie-cl-baseline` | 1195.978 | 3 |
| `results/3998278484-277986140.sexp` | `echologie-cl-batch-bitvector-unsafe` | 1973.583 | 2 |
| `results/3998278534-277986140.sexp` | `echologie-cl-batch-words` | 2326.835 | 2 |
| `results/3998278632-277986140.sexp` | `echologie-cl-batch-dense129` | 881.412 | 2 |
| `results/3998278703-277986140.sexp` | `echologie-cl-batch-dense129` | 421.672 | 3 |
| `results/3998278784-277986140.sexp` | `echologie-cl-batch-hybrid129` | 919.473 | 2 |
| `results/3998278869-277986140.sexp` | `echologie-cl-batch-hybrid129` | 352.567 | 3 |
| `results/3998279313-277986140.sexp` | `echologie-cl-batch-hybrid-vop-ready` | 310.922 | 3 |
| `results/3998279383-277986140.sexp` | `echologie-cl-batch-hybrid-peephole` | 269.212 | 3 |
| `results/3998279477-277986140.sexp` | `echologie-cl-batch-hybrid-bounds` | 246.684 | 3 |
| `results/3998279542-277986140.sexp` | `echologie-cl-batch-hybrid-block` | 236.115 | 3 |
| `results/3998279713-277986140.sexp` | `echologie-cl-batch-cutoff31` | 290.490 | 3 |
| `results/3998279749-277986140.sexp` | `echologie-cl-batch-cutoff63` | 244.849 | 3 |
| `results/3998279838-277986140.sexp` | `echologie-cl-batch-unroll4` | 240.241 | 3 |

Les mesures à deux échantillons durent 1 s et servent seulement à explorer.
Toutes les décisions retenues reposent sur trois échantillons de 5 s avec
validation préalable. Les résultats contiennent les empreintes exactes du
candidat, du pilote et de bootstrap, ainsi que version, CPU, allocations et GC.
Les variantes gardent les sources, y compris les échecs. Le fichier non mesuré
`09-cutoff15.lisp` reste une préparation abandonnée.

## Conformité et limites

- La classe `sieve-state` contient la limite et son propre tableau. Chaque
  `make-sieve` crée un nouvel objet et alloue des mots selon la limite reçue.
- Recherche séquentielle des facteurs impairs dans le crible calculé courant ;
  pas de liste de nombres premiers préétablie, pas de tableau de résultats
  réutilisé entre les passes.
- Les macros génèrent des opérations source avec un seul bit par masque.
  La fusion ultérieure d'OR est un peephole générique du compilateur, analogue
  à l'optimisation que la solution Rust confie à LLVM. Le classement retenu est
  `algorithm=base,faithful=yes,bits=1`.
- L'alignement dense peut remarquer des multiples sous p² ; seul p est premier
  parmi eux et son bit est restauré. Le sparse commence après p lui-même.
- Les écritures SAP sont bornées par la taille allouée et l'objet est épinglé.
  Les bits de remplissage du dernier mot sont ignorés par le comptage.
- Le candidat final cible SBCL 2.6.8 x86-64 et dépend de ses interfaces internes
  de génération de code et de peephole. Il n'est pas présenté comme portable
  vers d'autres implémentations de Common Lisp ou versions de SBCL.
- Aucun Rust installé, compilé ni exécuté. Ces gains comparent uniquement les
  versions Lisp sur le CPU logique 0 de ce même environnement. Ils ne prouvent
  pas une supériorité sur Rust sur une autre machine.

## Provenance et licence

Les principes dense/sparse, les périodes de masques et la restauration du
facteur viennent de la lecture de `PrimeRust/solution_1/prime-sieve-rust/src/unrolled.rs`
et de son README : Michael Barber (@mike-barber) et @GordonBGood. Le README
crédite également @ItalyToast pour des travaux antérieurs sur le marquage dense.
L'algorithme a été réécrit en Common Lisp pour cette expérience.

Le peephole d'OR est adapté de Robert Mayer (@mayerrobert),
`PrimeLisp/solution_2/PrimeSievebitops.lisp`, avec les API de SBCL 2.6.8, un
traitement limité aux opérations qword et une garde sur les étiquettes.
L'expérience suit les termes BSD-3-Clause exigés par `CONTRIBUTING.md` ; le
nouveau candidat porte cet identifiant SPDX. Aucun fichier de licence séparé
n'accompagnait ces deux fichiers amont dans le clone. Cette provenance est
explicitée pour une éventuelle revue avant redistribution.

## Reproduction

Depuis `PrimeLisp/solution_3`, SBCL étant déjà configuré :

```sh
python3 cpu-run.py repeat-final ./run.sh batch
```

Ce lanceur acquiert le verrou CPU commun, impose CPU 0, puis `run.sh` ouvre une
image vierge, compile, valide et mesure trois fois cinq secondes. Le pilote,
bootstrap et run.sh n'ont pas été modifiés. Pour reproduire une variante,
la copier dans `sieve.lisp` avant d'exécuter la même commande avec un nom de log
inédit. Les scripts d'inspection et profilage chargent seulement un FASL produit
par le candidat courant ; les lancer eux aussi via `cpu-run.py` et un SBCL neuf.

## Consolidation finale

Le seuil 129 est conservé. Seuil 63 : 244.849 µs ; seuil 31 : 290.490 µs.
Le déroulage ×4 des petits facteurs, 240.241 µs, n'a pas amélioré les
236.115 µs de la version 08. La version finale rétablit cette version 08,
avec commentaire de provenance, invariant algébrique et mise en forme de LET.
Aucune optimisation supplémentaire après cette matérialisation.

Validation finale seule : réussie, image vierge, `diagnostics/11-final-check.log`.
Confirmation finale : **239.196 µs/crible**, soit 4180.7 cribles/s.
Échantillons : 252.192 / 239.196 / 228.775 µs, chacun >= 5 s.
Résultat exact : `results/3998280055-277986140.sexp` ; log `diagnostics/11-final-batch.log`.
Gain médian sur la baseline contrôlée : **80.00 %**,
accélération 5.000×. La dispersion entre répétitions justifie
la comparaison finale commune du coordinateur ; le meilleur essai de développement
(236.115 µs) n'est pas substitué à cette médiane finale (239.196 µs).

Empreinte finale de `sieve.lisp` :
`6f4dac70f83f8b75766044220c14bbdaae92c5e62794d9a265689dd7d7b23929`.
Elle correspond exactement à `variants/11-final.lisp`.

## Décompte du temps

- Départ : 2026-09-13 08:52:55 UTC.
- Gel du code : 09:18:28 UTC, après 25 min 33 s murales.
- Mesure finale terminée : 09:20:55.599 UTC.
- Bilan préparé : 2026-09-13T09:22:12.941844+00:00, soit 1757.942 s murales
  (29 min 17.942 s) avant le commit local.
- Attente cumulée d'acquisition des processus : **229.121882 s**.
  Cette somme inclut des intervalles de travail utile et une inspection en
  attente de la propre mesure du bras. Elle n'est pas un temps d'inactivité.
- Inactivité effectivement déduite : **0 s**. Le budget comptabilisé est donc
  conservateur et égal au temps mural ; aucune prolongation demandée.
- Tous les processus Lisp, compilations et inspections passent par le même
  verrou CPU et sont épinglés au CPU logique 0. Aucun REPL persistant utilisé.

Le code est gelé ; seuls le journal, les preuves et le commit local sont terminés
après les dernières mesures. Aucun push, PR ou publication.
