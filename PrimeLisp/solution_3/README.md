# Common Lisp — proposition optimisée et comparaison des méthodes

Deux méthodes ont été comparées pendant trente minutes au maximum, pour optimiser un crible d'Ératosthène avec SBCL :

- **Batch** : modifier les fichiers, démarrer une image vierge, compiler, tester,
  mesurer, puis recommencer.
- **Interactif** : conserver une image SBCL, y évaluer et recompiler des
  définitions, inspecter les objets et le code machine, utiliser le débogueur,
  puis reporter les changements retenus dans les sources.

L'objectif des itérations est de **réduire le temps par crible**. Le temps de
développement sera consigné séparément. Le crible initial simple est archivé dans
`campaign-2026-09-13/candidates/baseline`. `sieve.lisp` contient désormais la
proposition optimisée ensuite par introspection SBCL, avec noyaux assembleur
dense et clairsemé locaux.

## Résultat du prolongement par introspection SBCL

La version actuelle, `echologie-cl-kernels129`, économise **24,43 % de temps**
par rapport à la version précédemment publiée : **280,634 → 212,069 µs/crible**
dans la série de confirmation (cinq mesures de cinq secondes par version,
alternées dans des images neuves). La première série finale donnait 23,22 %.
Les 47 tailles du contrôle indépendant passent. La supériorité sur Rust reste
à démontrer.

Les noyaux machine suppriment des conversions d'indices et des opérations
intermédiaires identifiées au désassemblage. Le SIMD et deux autres seuils de
déroulage ont été testés et archivés sans être retenus. La compilation complète,
le chargement et le contrôle sont passés d'une observation de 26,13 s à 0,54 s.
La reprise avec cache, empreintes et contrôle prend environ 0,33 s.

[Rapport et mesures brutes](campaign-2026-09-13-followup/RAPPORT.md).
[Reprise interactive sans recopie et reproduction](campaign-2026-09-13-followup/README.md).

```sh
./campaign-2026-09-13-followup/resume.sh
```

Le lanceur compile les sources seulement si le cache manque ou si leur empreinte
ou la version SBCL change. Les modifications suivantes peuvent être enregistrées
et compilées individuellement avec `lab:apply-file` ; leur manifeste permet de
les recharger après fermeture de l'image.

## Résultat de la première campagne du 13 septembre 2026

| Version | Médiane µs/crible | Cribles/s | Temps économisé |
|---|---:|---:|---:|
| Départ commun | 1 225,263 | 816,2 | — |
| Classique | 262,842 | 3 804,6 | 78,55 % |
| Interactive, retenue | 257,287 | 3 886,7 | 79,00 % |

Trois mesures de cinq secondes par version, alternées dans des images neuves,
avec le pilote initial inchangé. Les deux candidats ont passé le contrôle
indépendant sur 47 tailles. L'écart de 2,1 % entre méthodes est inférieur à la
dispersion des observations : ce premier essai ne prouve pas la supériorité
d'une méthode. La supériorité sur Rust n'est pas démontrée.

[Rapport complet, résultats bruts et reproduction](campaign-2026-09-13/RAPPORT.md).
[Provenance du code](EXPERIMENT.md).

Exemple réellement mesuré pour le candidat actuel (contrôle final supplémentaire) :

```text
echologie-cl-kernels129;24316;5.003981;1;algorithm=base,faithful=yes,bits=1
```

## Exécution

Prérequis : Linux x86-64, **SBCL 2.6.8**, Python 3, `taskset` et `sha256sum`.
Le candidat utilise des interfaces internes SBCL ; les autres versions ne sont
pas validées par cette campagne. Aucune bibliothèque
Lisp supplémentaire n'est nécessaire. Le profilage et l'introspection fournis
avec SBCL peuvent être chargés avec `require`.

Si SBCL n'est pas dans `PATH`, définir `SBCL=/chemin/vers/sbcl` pour la commande,
ou enregistrer ce chemin sur une ligne dans `.sbcl-path` (fichier local ignoré
par Git).

```sh
./run.sh check           # vérification indépendante de la correction
./run.sh batch           # image vierge, compilation, 3 mesures de 5 secondes
./run.sh batch 5 1       # une seule mesure de 5 secondes
./run.sh repl            # ouvrir le REPL natif dans une image persistante
```

Dans le REPL :

```lisp
(prime-bench:check-candidate)
(prime-bench:measure)                  ; mêmes 3 mesures de 5 secondes
(prime-bench:measure :seconds 1d0 :repeats 1) ; exploration courte uniquement
(prime-bench:reload-candidate)         ; compiler/recharger sieve.lisp
(disassemble 'prime-candidate:run-sieve)
(require :sb-sprof)
(require :sb-introspect)
```

Une session de terminal persistante permet d'envoyer ces expressions à la même
image, d'examiner ses réponses et de dialoguer avec son débogueur. Il n'y a ni
serveur Slynk/Swank ni client réseau à installer. Une définition compilée peut
être remplacée directement au REPL ; les appelants ayant incorporé une ancienne
définition par inlining doivent également être recompilés.

## Mesures communes

Le pilote `bench.lisp` reste identique dans les deux expériences.

- Un seul thread de calcul, sur le même CPU logique (`PRIMES_CPU`, sinon le
  premier CPU autorisé), avec un espace dynamique SBCL de 1 Gio.
- Crible jusqu'à **1 000 000 inclus**, avec allocation et calcul d'un nouvel
  état à chaque passe. Le point de départ est `algorithm=base,faithful=yes,bits=1`.
- Compilation, validation et échauffement hors de la zone chronométrée.
  Un GC complet précède chaque échantillon ; allocations et GC survenant pendant
  le calcul sont inclus dans son temps.
- Validation des indicateurs sur de petites tailles par division d'essai,
  notamment aux frontières des mots mémoire et des carrés ; vérification de
  **78 498** nombres premiers après chaque échantillon à la taille officielle.
- Durée par défaut : **5 secondes par échantillon**, répétée **3 fois**.
  Les essais plus courts servent uniquement à l'exploration.
- Un verrou commun interdit deux mesures simultanées : une seconde tentative
  signale une erreur immédiatement. Ne pas modifier `PRIMES_BENCH_LOCK`
  séparément pour chaque expérience. Le coordinateur suspend également les
  compilations concurrentes pendant les mesures utilisées pour décider d'un gain.

Chaque appel enregistre tous les échantillons et leur médiane dans `results/`
(format Lisp lisible), avec version SBCL, machine, CPU, mode, allocations, temps
GC et empreintes des sources. La sortie standard respecte le format du projet ;
le résumé et les diagnostics sont envoyés sur la sortie d'erreur.

Le critère principal est la **médiane des microsecondes par crible**, à minimiser.
Le débit en cribles/seconde est également fourni. Le gain de temps relatif est
`1 - temps_nouveau / temps_référence`. Répéter une amélioration avant de la
retenir ; conserver la meilleure version reproductible, pas seulement le
meilleur échantillon isolé.

Un journal du REPL doit accompagner les essais interactifs : les empreintes des
fichiers sur disque ne décrivent pas les redéfinitions encore présentes seulement
dans l'image. La validation finale passe, dans les deux méthodes, par
`./run.sh batch` à partir des seuls fichiers enregistrés.

## Séparation des expériences

Pour créer une nouvelle campagne depuis l'état courant enregistré dans Git :

```sh
./prepare-experiments.sh /chemin/vers/experiences
```

Deux clones locaux sont créés au même commit, sans partage des objets Git par
liens physiques, sur les branches `experiment/batch` et `experiment/interactive`.
Chacun possède son propre `PrimeLisp/solution_3`, ses FASL et ses résultats.
Le binaire SBCL et le verrou de mesure sont communs.

Les deux développeurs/agents doivent recevoir le même état initial, les mêmes
informations et le même budget explicite. Chacun ne consulte que son expérience
et ne transmet ses découvertes à l'autre qu'après la comparaison. Ces copies
assurent une séparation du travail, pas un cloisonnement des droits d'accès.

Interface du candidat : `make-sieve`, `run-sieve`, `primep`, `count-primes` dans
le package `prime-candidate`. La représentation interne peut évoluer. Les
étiquettes `*name*` et `*tags*` doivent décrire la version réellement mesurée ;
les catégories `faithful=yes` et `faithful=no` restent distinctes. Les règles
de référence figurent dans `../../CONTRIBUTING.md`.

Rust n'est ni installé ni exécuté par ces outils. Les résultats publiés par le
projet servent de repère externe, notamment `mike-barber_bit-unrolled-hybrid`.
Une différence entre deux machines ne constitue pas à elle seule une preuve de
supériorité ; les gains des itérations sont établis sur les mesures Common Lisp
locales comparables.

## Installation utilisée pour la préparation

- SBCL **2.6.8**, binaire officiel Linux x86-64, installé dans un préfixe local.
- [Page officielle de téléchargement](https://www.sbcl.org/platform-table.html).
- Archive : `sbcl-2.6.8-x86-64-linux-binary.tar.bz2`.
- SHA-256 de l'archive téléchargée :
  `5391773774b94554a015db9f992370d06937fb6f0cdb0b2142281aebef9e96c1`.
- Installation reproductible après extraction :
  `sh install.sh --prefix=/chemin/vers/sbcl-2.6.8`.

Les exécutables et FASL ne font pas partie de la proposition source. Les sources
des deux candidats, les journaux et les mesures de la campagne sont archivés
dans `campaign-2026-09-13`. Pour rejouer exactement son point de départ et ses
deux propositions finales, utiliser le script `reproduce.py` documenté dans le
rapport.
