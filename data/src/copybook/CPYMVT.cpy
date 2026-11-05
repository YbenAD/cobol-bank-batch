      *----------------------------------------------------------------*
      * CPYMVT : MOUVEMENT BANCAIRE                  LRECL 80 RECFM FB *
      *----------------------------------------------------------------*
      * POS  1-12  REFERENCE UNIQUE DU MOUVEMENT                       *
      * POS 13-23  NUMERO DE COMPTE (11 CHIFFRES)                      *
      * POS 24     TYPE : D = DEBIT  C = CREDIT                        *
      * POS 25-35  MONTANT 9(9)V99 (SANS VIRGULE, EN CENTIMES)         *
      * POS 36-43  DATE DE VALEUR AAAAMMJJ                             *
      * POS 44-73  LIBELLE                                             *
      *----------------------------------------------------------------*
       01  MVT-ENREG.
           05  MVT-REF                 PIC X(12).
           05  MVT-NUM-CPT             PIC X(11).
           05  MVT-TYPE                PIC X(01).
               88  MVT-DEBIT                     VALUE 'D'.
               88  MVT-CREDIT                    VALUE 'C'.
           05  MVT-MONTANT-X           PIC X(11).
           05  MVT-MONTANT REDEFINES MVT-MONTANT-X
                                       PIC 9(09)V99.
           05  MVT-DATE.
               10  MVT-DATE-AAAA       PIC 9(04).
               10  MVT-DATE-MM         PIC 9(02).
               10  MVT-DATE-JJ         PIC 9(02).
           05  MVT-DATE-X REDEFINES MVT-DATE
                                       PIC X(08).
           05  MVT-LIBELLE             PIC X(30).
           05  FILLER                  PIC X(07).
