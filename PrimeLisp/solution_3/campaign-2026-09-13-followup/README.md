# Optimisation interactive, désassemblage et coût de reprise

Cette campagne prolonge la proposition publiée le 13 septembre 2026. Elle ne
relance pas le concours entre deux développeurs indépendants : une seule session
explore les variantes, avec des processus séparés pour les premiers noyaux
assembleur. Rust n'est ni installé ni exécuté.

## Boucle de travail reproductible

Depuis `PrimeLisp/solution_3` :

```sh
./campaign-2026-09-13-followup/resume.sh
```

Ce lanceur compile `sieve.lisp` et le pilote une fois, puis réutilise les FASL
si les sources et la version SBCL sont identiques. Il recharge le manifeste actif
et vérifie le candidat. Aucun binaire compilé n'est requis dans le dépôt.

Écrire une modification dans un nouveau fichier, puis envoyer au REPL :

```lisp
(lab:apply-file "campaign-2026-09-13-followup/variants/ma-modification.lisp")
(disassemble 'prime-candidate::sparse-3)
(lab:measure 5d0 3)
```

Le fichier est la source de vérité : il n'y a pas de recopie du REPL vers le
fichier après chaque essai. `apply-file` enregistre son empreinte, compile ce
fichier seul, le charge et contrôle la correction. Après succès, il remplace
atomiquement `active-manifest.sexp`. Conserver les fichiers ainsi référencés
sans les modifier ; créer un nouveau fichier pour l'itération suivante. La
restauration vérifie les empreintes et reconstruit les FASL absents dans l'ordre.
Les expressions exploratoires envoyées directement au REPL ne sont pas
automatiquement persistées. Une erreur au milieu d'un chargement peut laisser
l'image partiellement modifiée : reprendre une image vérifiée avant de mesurer.

`lab:cost` journalise les durées réelles et CPU. `process-cost.py` mesure également
le démarrage et la sortie du processus. Les mesures ne comprennent pas le temps
humain/de l'assistant pour concevoir et écrire le code, ni la latence de transport
des commandes. Une durée Lisp affichée à zéro signifie une durée inférieure à la
résolution observée du compteur, pas un travail gratuit.

Pour un essai susceptible de tuer l'image, utiliser une image enfant chargeant
le candidat et le manifeste, puis y compiler la nouvelle variante. Par exemple,
après création du fichier source :

```sh
python3 campaign-2026-09-13-followup/process-cost.py isolated-next \
  --load .build/sieve.fasl --load .build/bench.fasl \
  --load campaign-2026-09-13-followup/lab.lisp \
  --eval '(lab:restore)' \
  --eval '(assert (lab:apply-file "campaign-2026-09-13-followup/variants/ma-modification.lisp"))'
```

Cet exemple utilise les caches créés par `./run.sh check`, à exécuter une fois
avant le premier essai isolé. Le lanceur de reprise gère, lui, un cache nommé
par empreinte. Le pilote enfant applique un délai maximal de 120 secondes.
Le processus enfant n'isole pas les fichiers : les sources et le manifeste sont
partagés volontairement, l'espace mémoire Lisp est indépendant. Ne pas lancer
une compilation enfant pendant une mesure chronométrée. Après son succès,
`(lab:restore)` applique les fichiers acceptés dans l'image principale.

## Ce qui est conservé

- `baseline.lisp` : version publiée avant cette campagne, inchangée.
- `variants/01` et `02` : noyaux assembleur clairsemé puis dense, retenus.
- `variants/03` : SIMD AVX2 pour 3, 5 et 7, non retenu.
- `variants/04` et `05` : seuils denses 255 et 63, non retenus.
- `manifest.sexp` : historique des cinq variantes chargées pendant l'exploration.
  « Accepted » dans le journal signifie compilation et contrôle réussis, pas
  amélioration de performance ni sélection finale.
- `active-manifest.sexp` : nouvelles modifications au-dessus du candidat final ;
  vide à la clôture de cette campagne, puisque les noyaux retenus sont consolidés.
- `diagnostics/` : REPL, profil statistique, désassemblages et contrôles.
- `measurements/` : mesures exploratoires du pilote inchangé.
- `final/` et `confirmation/` : comparaison dans des images neuves et empreintes des deux sources.

Les empreintes du pilote pendant l'exploration désignent le fichier sur disque,
qui était encore l'ancienne version. Les variantes, le manifeste et le transcript
identifient les définitions réellement présentes dans l'image. Les mesures finales
utilisent des répertoires préparés une seule fois par candidat, où `sieve.lisp`
correspond exactement au code compilé et mesuré.

## Reproduction

```sh
python3 campaign-2026-09-13-followup/assemble-candidate.py
./run.sh check
./run.sh batch 5 3
python3 campaign-2026-09-13-followup/compare.py
```

`assemble-candidate.py` reconstruit le candidat retenu à partir des sources
archivées, sans les générateurs Lisp obsolètes. Cette consolidation n'a lieu
qu'à la sélection finale, pas à chaque essai interactif. `compare.py` compile
chaque version une fois, puis alterne six processus neufs, chacun chargé des
FASL correspondants. Allocation, calcul et GC sont inclus ; compilation,
contrôle et échauffement sont exclus du temps par crible. Le pilote historique
`bench.lisp`, `bootstrap.lisp` et `run.sh` reste inchangé.

La vérification indépendante complète se rejoue après compilation par :

```sh
SBCL=/chemin/vers/sbcl
"$SBCL" --no-sysinit --no-userinit --non-interactive \
  --load .build/sieve.fasl --load .build/bench.fasl \
  --load campaign-2026-09-13/verify-final.lisp
```

Le candidat final demande Linux x86-64 et SBCL 2.6.8. Il n'utilise pas SB-SIMD.
Rejouer l'historique SIMD demande en plus le module officiel `sb-simd` complet et
un processeur AVX2. Le module installé initialement était tronqué ; il a été
restauré depuis l'archive officielle, puis l'image a été redémarrée. Aucun des
nouveaux noyaux assembleur n'a tué l'image pendant cette campagne.

[Résultats et analyse des coûts](RAPPORT.md).
