      *----------------------------------------------------------------*
      * CPYCPT : FICHIER MAITRE DES COMPTES   VSAM KSDS   LRECL 100    *
      *          CLE = CPT-NUM (POSITION 1, LONGUEUR 11)               *
      *----------------------------------------------------------------*
       01  CPT-ENREG.
           05  CPT-NUM                 PIC X(11).
           05  CPT-TITULAIRE           PIC X(30).
           05  CPT-SOLDE               PIC S9(11)V99 COMP-3.
           05  CPT-DECOUVERT-AUT       PIC 9(07)V99  COMP-3.
           05  CPT-STATUT              PIC X(01).
               88  CPT-ACTIF                     VALUE 'A'.
               88  CPT-BLOQUE                    VALUE 'B'.
           05  CPT-DATE-MAJ            PIC X(08).
           05  FILLER                  PIC X(38).
