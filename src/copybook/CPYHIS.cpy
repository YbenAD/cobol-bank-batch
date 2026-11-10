      *----------------------------------------------------------------*
      * CPYHIS : HISTORIQUE DES MOUVEMENTS POUR LE TRANSACTIONNEL      *
      *          VSAM KSDS BANK.MVTHIST   LRECL 80                     *
      *          CLE = HIS-CLE (POSITION 1, LONGUEUR 31)               *
      *                                                                *
      * ALIMENTE PAR LE BATCH BNKEXT01 A PARTIR DE LA TABLE DB2        *
      * MVT_HIST, LU PAR LA TRANSACTION CICS BNKH (BROWSE).            *
      *                                                                *
      * DATE INVERSEE DANS LA CLE (99999999 - AAAAMMJJ) : L'ORDRE      *
      * CROISSANT DES CLES DONNE, POUR UN COMPTE, LES MOUVEMENTS DU    *
      * PLUS RECENT AU PLUS ANCIEN (A DATE EGALE : PAR REFERENCE).     *
      *----------------------------------------------------------------*
       01  HIS-ENREG.
           05  HIS-CLE.
               10  HIS-NUM-CPT         PIC X(11).
               10  HIS-DATE-INV        PIC 9(08).
               10  HIS-REF             PIC X(12).
           05  HIS-DATE                PIC X(08).
           05  HIS-TYPE                PIC X(01).
               88  HIS-DEBIT                     VALUE 'D'.
               88  HIS-CREDIT                    VALUE 'C'.
           05  HIS-MONTANT             PIC S9(9)V99 COMP-3.
           05  HIS-LIBELLE             PIC X(30).
           05  FILLER                  PIC X(04).
