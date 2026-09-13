# Bilan : noyaux SBCL et boucle interactive

Le candidat final `echologie-cl-kernels129` économise **24,43 % du temps par
crible** dans la série de confirmation : **280,634 → 212,069 µs**, soit environ
**4 715 cribles/s**. La première série finale donnait un gain de 23,22 %.
L'objectif de battre Rust reste ouvert : cette campagne démontre une progression
Common Lisp locale, pas une victoire interlangages sur une machine commune.

## Mesures du crible

Même Xeon Platinum 8370C, même CPU logique 0, SBCL 2.6.8, un seul thread, limite
1 000 000. Le pilote initial est inchangé ; allocation fraîche et GC sont inclus.
Les compilations ne tournent pas en parallèle des mesures. Chaque échantillon
dure cinq secondes, avec contrôle et échauffement hors chronométrage.

| Exploration dans l'image | Médiane µs/crible | Décision |
|---|---:|---|
| Version publiée au départ | 256,957 | Référence |
| Boucle clairsemée entièrement dans une VOP | 223,232 | Retenue |
| Boucles dense et clairsemée dans des VOP, seuil 129 | 204,053 | Retenues |
| SIMD AVX2 pour les facteurs 3, 5, 7 | 224,746 | Non retenu |
| Seuil dense 255 | 215,355 | Non retenu |
| Seuil dense 63 | 206,163 | Pas de gain net |

Trois échantillons par ligne. Ce tableau sert à choisir les pistes ; la
comparaison finale utilise exclusivement les sources consolidées, dans des
processus neufs. Le seuil 63 et le seuil 129 sont proches : les observations
ne prouvent pas que 129 est optimal sur toutes les machines ou toutes les tailles.

| Images neuves, mesures alternées | Ancienne version µs | Nouvelle version µs | Temps économisé |
|---|---:|---:|---:|
| Première série : 3 échantillons/version | 294,803 | 226,343 | 23,22 % |
| Confirmation : 5 échantillons/version | 280,634 | 212,069 | 24,43 % |

Les résultats sont des médianes. La dispersion est réelle : dans la confirmation,
l'ancienne version va de 261,510 à 297,485 µs et la nouvelle de 199,872 à
232,549 µs. Tous les résultats sont conservés, y compris ceux moins bons que
l'exploration. Les deux séries finales donnent un gain cohérent, sans fournir
une garantie de performance universelle. Aucune sélection du meilleur essai
isolé ne sert de résultat final.

## Pourquoi le code a progressé

Le désassemblage de la boucle clairsemée révélait de nombreuses conversions
entre entiers Lisp étiquetés et offsets machine, ainsi que des valeurs stockées
sur la pile. La nouvelle VOP conserve pointeur, pas et compteur dans des
registres machine. Sa boucle centrale effectue huit OR octet directement en
mémoire, puis avance le pointeur et décrémente le compteur. Le Lisp conserve
l'orchestration, l’allocation de l'état et la gestion bornée de la fin du tableau.
Les entrées de la VOP restent explicitement vivantes pendant la préparation des
registres temporaires : cela élimine un risque d'aliasage identifié dans le
travail assembleur antérieur, sans prétendre établir rétrospectivement la cause
exacte de l'ancien crash.

Le profil statistique après cette modification indiquait encore une part
substantielle dans les fonctions denses. Le second générateur produit leurs
boucles machine directement, en regroupant les masques d'un même mot et en
réutilisant les trois masques du facteur 3. Les masques représentent les
multiples d'un facteur ; ce ne sont ni une liste de nombres premiers, ni un
résultat de crible précalculé. Tous les facteurs impairs ont un cas généré et le
crible en cours détermine ceux qui sont premiers. L'objet et son tableau sont
alloués à chaque passe ; l'étiquette reste `algorithm=base,faithful=yes,bits=1`.

L'essai SIMD n'a pas amélioré le temps total. Son désassemblage montre des
contrôles de bornes répétés et des rechargements de masques à l'intérieur de la
boucle. Cela suggère une piste précise pour une future version vectorielle,
mais ne prouve pas que ces instructions expliquent à elles seules tout le recul.
Le candidat livré conserve les noyaux scalaires et ne dépend pas de SB-SIMD.

Le profil SB-SPROF est un échantillonnage limité, utile pour orienter le travail,
non une attribution exacte des coûts. Les désassemblages et l'introspection des
arguments sont archivés ; les compteurs d'allocations et de GC figurent dans les
mesures brutes du pilote.

## Coût de la méthode

| Opération observée | Temps réel |
|---|---:|
| Compiler le fichier de modification clairsemée | 0,152 s |
| Compiler le fichier de modification dense | 0,204 s |
| Image enfant : démarrer, compiler/charger/contrôler la modification clairsemée | 0,279 s |
| Image enfant : reprendre puis compiler/charger/contrôler la modification dense | 0,375 s |
| Reprise directe depuis cache, avec les deux modifications et contrôle | 0,171 s |
| Lanceur final avec empreintes, reprise et contrôle : médiane de 3 démarrages | 0,329 s |
| Construction complète ancienne source, chargement et contrôle | 26,125 s |
| Construction complète nouvelle source, chargement et contrôle | 0,540 s |
| Contrôle indépendant complet, processus compris | 1,347 s |

Sauf le lanceur final, ces temps sont des observations individuelles, pas des
moyennes garanties. Le lanceur final inclut Python, la vérification de version et
les empreintes ; ses trois temps vont de 0,273 à 0,355 seconde. Les constructions
complètes de cette table réutilisent le pilote déjà compilé. La comparaison qui
recompile aussi le pilote a observé 33,123 et 0,777 seconde respectivement.

L'introspection finale (arguments et deux désassemblages) a consommé environ
1,4 ms CPU ; le compteur de temps réel n'a pas résolu sa durée. La compilation
SIMD a pris 0,288 seconde, mais le premier chargement du module a ajouté
1,212 seconde. L'essai isolé du seuil 255 a coûté 1,746 seconde en incluant la
reprise historique du module SIMD, pourtant inutile au candidat retenu.

Les temps de rédaction, réflexion et transport des commandes ne sont pas inclus.
Les trois mesures de performance prennent à elles seules environ quinze secondes
par variante. Ainsi la persistance n'impose pas ici des recopies incessantes ni
une reconstruction complète à chaque essai. En revanche, avec le nouveau
générateur, la compilation complète est elle-même rapide : cette campagne ne
démontre pas que l'interactivité est toujours plus rapide que le batch. Elle
permet de conserver l'état inspectable tout en réduisant le coût de sa reprise.

## Correction, incidents et traçabilité

Le contrôle indépendant existant a vérifié chaque indicateur de primalité sur
47 tailles, de 0 à 2 000 003, avec des frontières de mots mémoire et de carrés.
Il vérifie aussi que créer et utiliser un autre crible ne modifie pas le premier.
Tous les contrôles ont réussi dans une image neuve. Une exécution finale par
`run.sh batch 5 1` vérifie également le chemin normal de livraison ; elle reste
un contrôle supplémentaire, hors des séries comparatives ci-dessus.

Aucun nouveau noyau assembleur n'a tué l'image. Le module `sb-simd` installé
était tronqué (3 784 704 octets au lieu de 12 398 835). Il a été restauré depuis
l'archive officielle déjà disponible, puis l'image a été redémarrée. Lors de la
finalisation du journal, un nom d'API de renommage inexistant a déclenché une
erreur Lisp ordinaire ; le lanceur et l'écriture du manifeste ont été corrigés
et vérifiés. Ces incidents figurent dans les transcripts et n'ont pas été
comptés comme des résultats de performance des candidats.

Source finale SHA-256 :
`cf38be9a260a07640021d4f4eb7883f627d5f5ac455b5637c75bda4c7816749d`.
Les trois fichiers du pilote sont inchangés depuis la campagne précédente.
La campagne précédente, ses candidats et son rapport restent intégralement
conservés. Les mécanismes internes SBCL employés ici sont validés uniquement
avec SBCL 2.6.8 sur Linux x86-64.

## Repère Rust

La référence publiée du projet, archivée dans
`../campaign-2026-09-13/rust-reference.json`, donne notamment 10 882,136 cribles/s
pour `mike-barber_bit-unrolled-hybrid` sur Core i7-9750H dans la
[session 9608](https://primes.marghidanu.com/v1/sessions/9608/results).
Notre débit local n'atteint pas ce chiffre, et les processeurs sont différents.
Il serait donc incorrect d'annoncer « Rust battu ». Le déroulage dense/clairsemé
reprend la stratégie attribuée à Mike Barber et GordonBGood dans le code Rust du
dépôt ; la génération machine et l'inspection sont spécifiques à SBCL.

[Commandes de reprise et reproduction](README.md), [mesures finales](confirmation/summary.json),
[coûts des processus](process-costs.jsonl), [journal des opérations Lisp](costs.sexp).
