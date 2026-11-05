      *----------------------------------------------------------------*
      * CPYREJ : MOUVEMENT REJETE                   LRECL 120 RECFM FB *
      *----------------------------------------------------------------*
      * CODES REJET VALIDATION (BNKVAL01)                              *
      *   R01 REFERENCE ABSENTE        R05 MONTANT NUL                 *
      *   R02 COMPTE NON NUMERIQUE     R06 DATE NON NUMERIQUE          *
      *   R03 TYPE INVALIDE            R07 DATE INVALIDE               *
      *   R04 MONTANT NON NUMERIQUE    R08 DATE POSTERIEURE AU TRT     *
      * CODES REJET MISE A JOUR (BNKMAJ01)                             *
      *   R10 COMPTE INEXISTANT        R12 DECOUVERT AUTORISE DEPASSE  *
      *   R11 COMPTE BLOQUE                                            *
      *----------------------------------------------------------------*
       01  REJ-ENREG.
           05  REJ-MVT                 PIC X(80).
           05  REJ-CODE                PIC X(03).
           05  REJ-MOTIF               PIC X(37).
