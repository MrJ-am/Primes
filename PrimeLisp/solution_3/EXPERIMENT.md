# Provenance de la proposition retenue

Le candidat `sieve.lisp` prolonge la proposition interactive de la première
campagne du 13 septembre 2026. Ses noyaux dense et clairsemé sont maintenant
générés directement avec des VOP locales SBCL. L'interface, la représentation
et le pilote de mesure sont conservés.

- [Optimisation par introspection, coûts et contrôles](campaign-2026-09-13-followup/RAPPORT.md).
- [Sources exactes de départ](campaign-2026-09-13-followup/baseline.lisp).
- [Reconstruction du candidat final](campaign-2026-09-13-followup/assemble-candidate.py).

La première campagne reste archivée sans modification :

- [Bilan comparatif et contrôles indépendants](campaign-2026-09-13/RAPPORT.md).
- [Journal original interactif, provenance et licence](campaign-2026-09-13/candidates/interactive/EXPERIMENT.md).
- [Journal original classique et variante conservée](campaign-2026-09-13/candidates/batch/EXPERIMENT.md).

Les variantes et journaux mentionnés dans les comptes rendus originaux sont conservés à côté de ces comptes rendus. Les macros de déroulage s'inspirent du travail de Mike Barber et GordonBGood cité dans la solution Rust du dépôt. La VOP d'OR octet est locale à cette proposition SBCL ; les détails figurent dans le journal interactif.
