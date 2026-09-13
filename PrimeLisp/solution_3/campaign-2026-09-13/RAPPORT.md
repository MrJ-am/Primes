# Campagne Common Lisp du 13 septembre 2026

La proposition retenue calcule le crible en **257,287 µs** en médiane, soit **4,76 fois** le débit du point de départ et **79,00 % de temps économisé**. Elle provient de la méthode interactive.

L'écart final avec le classique est de **2,11 % de temps**, et les plages d'échantillons se recouvrent. Ce premier essai ne démontre donc pas qu'une méthode de développement est supérieure. Le candidat interactif est sélectionné pour sa plus petite médiane observée ; les deux propositions restent disponibles séparément. **La supériorité sur Rust n'est pas démontrée.**

## Comparaison finale indépendante

| Version | Médiane µs/crible | Minimum–maximum µs | Cribles/s | Temps économisé |
|---|---:|---:|---:|---:|
| Départ commun | 1 225,263 | 1 221,079–1 278,152 | 816,2 | — |
| Classique | 262,842 | 242,018–272,429 | 3 804,6 | 78,55 % |
| Interactive | 257,287 | 247,256–262,590 | 3 886,7 | 79,00 % |

Chaque version reçoit trois échantillons de cinq secondes. Les neuf passages utilisent chacun une image SBCL neuve, dans l'ordre fixé avant les mesures : départ, classique, interactif, interactif, départ, classique, classique, interactif, départ. Le code a été figé avant cette série. Compilation, validation et échauffement sont hors chronométrage ; les allocations et le GC durant les passes sont inclus. Le pilote initial est inchangé.

Machine : Intel Xeon Platinum 8370C, Linux x86-64, SBCL 2.6.8, un thread de calcul fixé au CPU logique 0, espace dynamique de 1 Gio. Le verrou commun couvre les compilations et calculs Lisp pour éviter leur concurrence. La description matérielle est dans [environment.json](environment.json).

Les [neuf mesures brutes et leur résumé](final-comparison/results.json) comprennent durée, passes, temps CPU, allocations, GC, commits et empreintes des sources. Le minimum et le maximum sont des observations, pas un intervalle de confiance.

Les dernières mesures réalisées par les agents dans leur propre protocole étaient 239,196 µs pour le classique et 242,570 µs pour l'interactif. Leur ordre est inversé dans la comparaison commune ci-dessus : cela renforce la prudence sur les petits écarts. Les données de ces séries sont conservées, sans remplacer celles de la comparaison finale.

## Ce qui a été optimisé

Les deux agents ont indépendamment convergé vers des mots de 64 bits, un bit par candidat impair, des fonctions générées pour les petits facteurs jusqu'à 129, et huit marquages déroulés pour les facteurs plus grands. L'instruction OR directement en mémoire réduit le coût du marquage. Les bornes des indices et la suppression d'objets SAP intermédiaires évitent des opérations et allocations dans la boucle chaude.

Le candidat interactif utilise une VOP locale SBCL et le repliement de constantes de LOGIOR. Le classique installe aussi un peephole générique d'OR, adapté du travail de Robert Mayer dans `solution_2`. Les principes de déroulage dense et clairsemé sont issus de la lecture du travail de Mike Barber et GordonBGood dans la solution Rust du dépôt ; aucun Rust n'a été installé, compilé ou exécuté.

Chaque passe crée une instance CLOS et son propre tableau, dimensionné selon la limite reçue à l'exécution. Les facteurs sont découverts dans le crible courant. Les macros produisent les positions des multiples d'un seul facteur ; elles ne stockent aucune liste de premiers ni résultat de crible. Étiquettes utilisées : `algorithm=base,faithful=yes,bits=1`, un thread. Leur justification et la provenance détaillée se trouvent dans les journaux originaux.

Le code retenu dépend des interfaces internes de **SBCL 2.6.8 x86-64**. Cette campagne valide cette configuration ; elle ne valide pas la portabilité vers une autre implémentation ou version de Lisp.

## Exactitude

Le [contrôle indépendant](verify-final.lisp), préparé avant le gel et non communiqué aux agents, est réussi pour les deux candidats : **47 tailles**, de 0 à 2 000 003, tous les indicateurs comparés à un crible de référence distinct, frontières de mots mémoire et carrés, comptages et indépendance des instances. L'oracle est lui-même confronté à la division d'essai jusqu'à 2 048. Le contrôle initial du pilote vérifie aussi les petites tailles et les **78 498 premiers jusqu'à 1 000 000** ; ce comptage est contrôlé après chaque mesure.

Preuves : [classique](final-comparison/validation-batch.log) et [interactif](final-comparison/validation-interactive.log). L'inspection des sources confirme l'allocation indépendante et l'absence de résultats précalculés.

## Comparaison des méthodes

Deux agents ont reçu le même commit de départ, le même modèle, le même budget maximal de trente minutes et les mêmes sources de référence, dans deux clones indépendants. Aucune découverte d'optimisation n'a été transmise entre eux avant le gel. Les attentes de processus qui recouvraient lecture, édition ou réflexion restent comptées comme travail actif.

| Mesure | Classique | Interactive |
|---|---|---|
| Départ UTC | 08:52:55 | 08:53:35 |
| Gel du code UTC | 09:18:28 | 09:20:12 |
| Livraison et contrôle final UTC | 09:22:25 | 09:22:52 |
| Temps mural/actif comptabilisé | 29 min 30 s | 29 min 17 s |
| Attente cumulée des processus sur le verrou | 229,122 s | 80,288 s |
| Inactivité déduite | 0 s | 0 s |

Le classique compile et inspecte depuis une image neuve à chaque opération. Il a rencontré des difficultés de déclaration et d'enregistrement des VOP, puis a confirmé chaque amélioration retenue sur trois mesures longues.

L'interactif a pu recompiler seulement les fonctions modifiées et inspecter directement leur code machine ; certaines compilations complètes prenaient environ 26 secondes. Il a aussi dû expliciter la politique d'optimisation lors de chargements incrémentaux, récupérer des erreurs au débogueur et redémarrer une fois après le défaut mémoire d'un VOP expérimental rejeté. Deux images interactives ont été utilisées, puis une image distincte pour la validation finale. La dernière mesure live, 243,740 µs, a été reproduite depuis les seules sources à 242,570 µs.

Ces observations justifient de continuer l'exploration dans une image interactive, tout en faisant des images neuves l'arbitre des gains retenus. Un seul agent par méthode et une seule campagne de trente minutes ne permettent pas d'isoler un effet général de la méthode. La série indépendante finale est réalisée après le budget de développement.

Journaux et variantes : [classique](candidates/batch/EXPERIMENT.md), [interactif](candidates/interactive/EXPERIMENT.md). Le [protocole](protocol.json) conserve les commits et les empreintes. Les dossiers `raw-results` gardent aussi les journaux natifs ; les vérifications d'installation antérieures aux heures de départ ne font pas partie des résultats de la campagne.

## Repères Rust du projet

La référence retenue est `mike-barber_bit-unrolled-hybrid`, avec les mêmes étiquettes et un thread. Les résultats publiés ont été lus directement dans l'API de PrimeView, reliée au dépôt officiel du projet.

| Publication | Machine du projet | Rust, cribles/s |
|---|---|---:|
| 13 septembre 2026, session 9608 | Intel Core i7-9750H | 10 882,1 |
| 12 septembre 2026, session 9607 | AMD Threadripper PRO 9995WX | 23 804,4 |

Sources primaires : [session 9608](https://primes.marghidanu.com/v1/sessions/9608/results) et [session 9607](https://primes.marghidanu.com/v1/sessions/9607/results). Les lignes sélectionnées et les machines sont archivées dans [rust-reference.json](rust-reference.json).

Ces machines diffèrent du Xeon utilisé ici. Les chiffres sont des repères externes ; on ne peut en déduire un rapport de vitesse Lisp/Rust à matériel égal. Le débit local de 3 886,7 cribles/s n'apporte en tout cas aucune démonstration que l'objectif de battre Rust est atteint. La prochaine campagne peut partir du candidat conservé, puis faire évaluer la proposition sur les machines du projet.

## Reproduction

Depuis `PrimeLisp/solution_3`, avec le binaire SBCL 2.6.8 configuré :

```sh
./run.sh check
./run.sh batch 5 3
```

Pour reconstruire les trois candidats figés dans des répertoires temporaires indépendants et relancer les neuf mesures :

```sh
python3 campaign-2026-09-13/reproduce.py \
  --sbcl /chemin/vers/sbcl-2.6.8/bin/sbcl \
  --output campaign-2026-09-13/reproduction-01
```

Le dossier de sortie doit être nouveau. Le script vérifie les empreintes du pilote historique, sélectionne par défaut le premier CPU autorisé, puis exécute `compare-final.py`. Ajouter `--cpu 0` pour reproduire notre affinité lorsque ce CPU est disponible. Les mesures historiques sont dans `final-comparison` ; les sources figées sont dans `candidates`. Aucun binaire, FASL ou résultat précalculé n'est nécessaire.
