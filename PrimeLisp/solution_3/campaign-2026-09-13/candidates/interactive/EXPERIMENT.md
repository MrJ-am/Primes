# Expérience interactive SBCL

Début : 2026-09-13 08:53:35 UTC. Budget : 30 minutes actives, attente effective
du verrou CPU exclue. Clone `experiment/interactive`, départ
`682c13d05b297a7e95c9d262bb13b389307ca242`.

Méthode : une image SBCL 2.6.8 persistante, CPU logique 0, terminal natif.
Le journal brut est `experiments/repl.typescript`. Toutes les évaluations,
compilations et mesures prennent `/tmp/primes-campaign-cpu.lock` ; acquisition
par une forme séparée avant l'envoi de la forme expérimentale. Le verrou est
relâché après l'opération. Le journal donne les attentes et leur cumul.

Les fichiers de résultat natifs sont sous `results/` (ignorés par Git) ; leurs
copies finales seront conservées sous `experiments/results/`. Le pilote commun
`bench.lisp`, `bootstrap.lisp` et `run.sh` ne sont pas modifiés.

## Itérations

- 08:54 : baseline inchangée, validation puis 3 × 5 secondes : médiane
  **1288,688 µs/crible** ; résultat `3998278482-277986140.sexp`.
- 08:55 : `01-word-basic.lisp`, bits impairs dans des mots 64 bits,
  marquage dynamique naïf, safety 0. Correct, mais exploration 1 seconde à
  **2032,248 µs/crible**. Rejeté. Le désassemblage
  `01-word-basic-disassembly.txt` montre de nombreux déplacements/décalages par
  multiple ; aucune allocation de bignum dans la boucle chaude.
- 08:57 : générateur de fonctions spécialisées pour les facteurs impairs
  3..129, inspiré du déroulage dense de la référence Rust. Première compilation
  interrompue sur erreur de parenthèse de la macro ; récupération au débogueur,
  même image conservée, aucune mesure attribuée à cette version non compilée.

## Provenance et admissibilité

Lecture de `CONTRIBUTING.md` et de
`PrimeRust/solution_1/prime-sieve-rust/src/unrolled.rs`, ainsi que du générateur
`PrimeRust/solution_1/helper-macros/src/lib.rs`. Les idées du déroulage dense,
de la période de 64 positions et du rétablissement du bit du facteur viennent
notamment du travail de Mike Barber avec GordonBGood, crédité dans ces sources.
Le Lisp est une réécriture ; aucune source Rust n'est compilée ni installée.
Les contributions Lisp de cette expérience sont proposées sous BSD-3-Clause,
conformément aux règles du dépôt.

Chaque passe alloue une nouvelle instance de classe et son tableau à la taille
reçue à l'exécution, puis crible les facteurs découverts dans ce tableau. Les
constantes de masques représentent les positions des multiples d'un seul
facteur, et non une liste ou un résultat de nombres premiers précalculés.
- 08:59 : `02-dense129.lisp` validé, **1019,285 µs** en exploration.
  Désassemblage de `dense-3` : 892 octets, beaucoup d'OR/BTS en chaîne.
- 09:00 : `03-dense129-fold.lisp`, une expression LOGIOR conserve les
  arguments constitués de masques à un seul bit ; SBCL replie les constantes.
  Le désassemblage de `dense-3` descend à 178 octets. Correct, exploration
  **789,304 µs**. Ce repliement compiler correspond à l'optimisation appliquée
  par LLVM au déroulage de la référence ; aucune union de différents facteurs.
- 09:01 : préparation du chemin clairsemé : huit fonctions suivant le résidu
  du facteur modulo 16, chacune marque huit multiples par tour. Accès octets
  au tableau de mots via un SAP protégé par `with-pinned-objects`.
  Redéfinition incrémentale des seules nouvelles fonctions dans l'image,
  au lieu de recompiler les 64 fonctions denses (environ 26 secondes).
- 09:01 : le premier chemin clairsemé live a donné **944,493 µs**. Son
  chargement incrémental n'avait pas redonné la politique d'optimisation du
  fichier compilé. Ce chiffre est celui de l'état live décrit dans le
  transcript, pas une mesure d'un chargement neuf du fichier canonique 04.
- 09:02 : `05-hybrid129-speed3.lisp` et delta explicitement optimisés.
  Validation et 3 × 5 secondes : **310,190 µs/crible** (313,651 et 302,813
  pour les deux autres échantillons). Premier gain confirmé conservé.
- 09:04 : VOP local `or-byte!`, vérifié sur un tableau vivant puis désassemblé :
  une instruction OR octet en mémoire. Aucun patch global des VOP SBCL.
  Documentation et syntaxe comparées à
  `PrimeLisp/solution_2/bitvector-set-2.0.0-2.1.8-snap.lisp` (mayerrobert),
  sans réutiliser son patch. Les déclarations de type bornent également les
  facteurs à `isqrt(most-positive-fixnum)` pour éviter l'arithmétique générique.
- 09:05 : une seconde erreur de parenthèse dans le remplacement textuel du
  générateur est récupérée au débogueur ; image conservée et verrou libéré.

## Temps

Au point 09:03 : attente cumulée des processus 57,044 secondes. Du travail
utile s'y superposait ; **aucune inactivité n'est déduite**. Échéance maintenue
à 09:23:35 UTC. Le temps des compilations, des mesures et de réflexion est
compté dans le budget.
- 09:05 : `06-hybrid129-vop.lisp`, correct, 3 × 5 secondes : médiane
  **252,090 µs/crible**, autres échantillons 242,983 et 265,379.
- 09:08 : `07-hybrid129-scaled.lisp`, adressage x86 indexé et pointeur avancé
  par groupe. Correct mais exploration initiale **566,270 µs** ; répétition
  2 × 2 secondes **302,704 µs**. Gain non retenu, forte variabilité signalée.
  Le profilage vivant (227 échantillons) attribue ~41 % aux fonctions sparse
  et ~14 % à l'allocation. Le transcript contient le rapport intégral.
- 09:12 : `08-hybrid129-kernel.lisp`, expérimentation d'un VOP qui déroule
  la seule boucle de huit marquages, sans changer la découverte des facteurs,
  les frontières ou la représentation. L'allocation et les objets restent Lisp.
- 09:12:53 UTC : **crash de l'image** à la validation du VOP noyau 08,
  défaut mémoire suivi d'entrées récursives dans LDB. Aucun résultat retenu
  pour 08. L'image compromise est arrêtée et la version confirmée 06 restaurée.
  L'essai 08 reste uniquement comme trace d'échec, jamais comme candidat final.
- 09:13–09:14 : redémarrage et recompilation des sources. DEFKNOWN doit
  accepter sa répétition aux phases compilation/chargement ; l'option
  `:overwrite-fndb-silently t` est ajoutée à la proposition reproductible.
  Le débogueur de démarrage a permis de reprendre le chargement en cours.
  Le verrou initial a été conservé trop longtemps pendant cette récupération,
  entraînant une attente de l'autre bras ; incident signalé au coordinateur.
- 09:14 : balayage des seuils denses 17,31,63,95,129, chacun 2 × 1 seconde,
  tous corrects. Médianes respectives : 820,247 ; 835,682 ; 685,916 ;
  666,968 ; 581,690 µs. Aucun gain retenu. Le dernier résultat ne reproduit
  pas encore les 252 µs de l'ancienne image ; vérification du code généré avant
  toute conclusion, et maintien du seuil 129 en attendant.
- 09:17 : `10-hybrid129-unboxed.lisp` supprime l'objet SAP transmis par
  facteur, conserve l'objet contenant le tableau pendant les accès, et borne
  les indices pour éviter l'arithmétique générique dans les fins de blocs.
  Validation et 3 × 5 secondes : **243,740 µs/crible** (257,698 ; 243,018 ;
  243,740), environ 62,5 ko alloués par passe. Proposition conservée.
- 09:18 : consolidation des sources, suppression du helper inutilisé et des
  déclarations de package dupliquées, commentaires et SPDX BSD-3-Clause.
  `11-final.lisp` est une copie du candidat canonique. Fin des explorations :
  priorité à la reproduction dans une image entièrement neuve.

## Résultat final et reproduction

Candidat gelé le **2026-09-13 à 09:20:12 UTC**, après **26 min 37 s**
écoulées depuis le début, sans aucune inactivité déduite. L'archivage et le
commit qui suivent comptent séparément dans le temps de livraison, sans nouvelle
optimisation ni nouvelle sélection de candidat.

Le lancement final `PRIMES_CPU=0 ./run.sh batch`, sous le verrou commun et dans
une image SBCL entièrement neuve, compile les seuls fichiers sauvegardés,
valide les indicateurs et produit trois échantillons de 5 secondes :

| Échantillon | Passes | Durée (s) | µs/crible |
|---|---:|---:|---:|
| 1 | 21 190 | 5,003984 | 236,148 |
| 2 | 20 629 | 5,003984 | 242,570 |
| 3 | 20 336 | 5,003985 | 246,065 |

**Médiane finale : 242,570 µs/crible, soit 4 122,5 cribles/s.**
La baseline contrôlée de cette expérience est 1288,688 µs ; le temps baisse de
**81,18 %**, débit multiplié par **5,31**. La dernière image live avait donné
243,740 µs : le candidat final reproduit ce résultat depuis les fichiers.
L'ancien écart observé pendant la récupération ne justifie donc aucun gain
supplémentaire revendiqué pour les essais 09.

Résultat natif : `experiments/results/3998280012-277986140.sexp`.
Journal du lancement final : `experiments/final-fresh.typescript`.
Empreinte SHA-256 du `sieve.lisp` final :
`c51f1976f446a6e3826b47174385afb733384183a1724489583867c2ab0f9def`.
Les trois fichiers de protocole n'ont pas été modifiés.

Deux images interactives ont été utilisées : **un redémarrage** après le crash
08, puis une image neuve distincte pour la validation finale obligatoire.
L'attente cumulée des acquisitions dans les images est **80,231624 s** ;
les trois acquisitions initiales de shell ajoutent environ **0,056324 s**,
soit **80,287948 s d'attente de processus mesurée**. Lecture, réflexion ou
édition se superposaient à ces attentes ; la déduction d'inactivité effective
reste **0 s**. L'attente du verrou a été comptabilisée mais n'a jamais étendu
l'échéance initiale 09:23:35 UTC.

Limites : le VOP local vise SBCL x86-64 ; le portage demanderait un autre
backend ou le fallback Lisp. Le code conserve une allocation et une instance
par passe, les candidats pairs implicites, et un seul bit par candidat impair.
Les constantes de déroulage concernent un facteur à la fois ; le crible
séquentiel découvre les facteurs dans l'état de la passe. Aucune comparaison
locale Rust n'a été effectuée et aucun résultat sur une autre machine ne permet
de revendiquer ici une victoire sur Rust. Les très courts essais et les états
interactifs non reproduits ne servent pas de résultat final.

Archivage achevé le 2026-09-13 à 09:22:38 UTC : **29 min 3 s de temps mural/actif total** avant commit local, déduction 0 s.
