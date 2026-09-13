# Traces de l’expérience interactive

Le candidat à compiler est `../sieve.lisp`, identique à `11-final.lisp`.
`RESULTS.md` indexe les résultats natifs conservés sous `results/`.
`repl.typescript` contient la première image, `repl-recovery.typescript` la
seconde, et `final-fresh.typescript` le lancement final autonome.

Les fichiers numérotés 00 à 10 sont les variantes historiques. Les fichiers
`*-delta.lisp` décrivent les redéfinitions chargées dans l'image au cours de la
session ; un delta seul ne constitue pas un candidat autonome. Les générateurs
intermédiaires sont également conservés pour relier le transcript aux sources.

La variante **08** et `sparse-loop-vop.lisp` sont **rejetés : défaut mémoire à
la validation**. Ils n'ont aucun résultat de performance admissible. Les essais
04 et le redémarrage de 06 comportent des différences de chargement explicitées
dans `../EXPERIMENT.md`. Seule la finale est proposée comme reproductible.
