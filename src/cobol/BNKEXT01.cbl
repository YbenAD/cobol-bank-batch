       IDENTIFICATION DIVISION.
       PROGRAM-ID. BNKEXT01.
      *----------------------------------------------------------------*
      * EXTRACTION DE L'HISTORIQUE DB2 VERS VSAM POUR LE TRANSACTIONNEL*
      *                                                                *
      * ENTREE : TABLE DB2 MVT_HIST (CURSEUR EN LECTURE SEULE)         *
      * SORTIE : MVTHIST  VSAM KSDS (CPYHIS), RECREE A CHAQUE PASSAGE  *
      *                                                                *
      * LA REGION CICS N'ETANT PAS CONNECTEE A DB2, LA TRANSACTION     *
      * BNKH CONSULTE UNE COPIE VSAM DE L'HISTORIQUE, RAFRAICHIE PAR   *
      * CE BATCH. DB2 RESTE LA REFERENCE.                              *
      *                                                                *
      * LE CURSEUR EST TRIE DANS L'ORDRE DE LA CLE DU KSDS (COMPTE,    *
      * DATE DECROISSANTE, REFERENCE) : LE FICHIER EST ECRIT EN ACCES  *
      * SEQUENTIEL, CE QUI EXIGE DES CLES CROISSANTES.                 *
      *                                                                *
      * EXECUTION : IKJEFT01 / DSN RUN PROGRAM(BNKEXT01) PLAN(<TON ID>)*
      *                                                                *
      * CODES RETOUR : 0 = OK   12 = ERREUR SQL   16 = ERREUR FICHIER  *
      *----------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT F-MVTHIST ASSIGN TO MVTHIST
                  ORGANIZATION IS INDEXED
                  ACCESS MODE IS SEQUENTIAL
                  RECORD KEY IS HIS-CLE
                  FILE STATUS IS WS-FS-MVTHIST.

       DATA DIVISION.
       FILE SECTION.
       FD  F-MVTHIST.
           COPY CPYHIS.

       WORKING-STORAGE SECTION.
           EXEC SQL INCLUDE SQLCA   END-EXEC.
           EXEC SQL INCLUDE DCLMVTH END-EXEC.

      *    ORDRE = ORDRE DE LA CLE DU KSDS (DATE INVERSEE DANS LA CLE)
           EXEC SQL DECLARE CHIST CURSOR FOR
                SELECT NUM_CPT, REF_MVT, CHAR(DATE_MVT, ISO),
                       TYPE_MVT, MONTANT, LIBELLE
                  FROM MVT_HIST
                 ORDER BY NUM_CPT ASC, DATE_MVT DESC, REF_MVT ASC
                 FOR READ ONLY
           END-EXEC.

       01  WS-FS-MVTHIST               PIC X(02).
           88  MVTHIST-OK                        VALUE '00' '97'.
       01  WS-FIN-CURSEUR              PIC X(01) VALUE 'N'.
           88  FIN-CURSEUR                       VALUE 'O'.

       01  WS-DATE-ISO.
           05  ISO-AAAA                PIC X(04).
           05  FILLER                  PIC X(01).
           05  ISO-MM                  PIC X(02).
           05  FILLER                  PIC X(01).
           05  ISO-JJ                  PIC X(02).
       01  WS-DATE-NUM                 PIC 9(08).

       01  WS-NB-EXTRAITS              PIC 9(07) COMP-3 VALUE 0.
       01  WS-ED-NB                    PIC Z(6)9.
       01  WS-ED-SQLCODE               PIC -(9)9.

      *--- ZONE MESSAGE DSNTIAR ----------------------------------------
       01  WS-MSG-ERREUR.
           05  WS-MSG-LONGUEUR         PIC S9(4) COMP VALUE +720.
           05  WS-MSG-TEXTE            PIC X(72) OCCURS 10 TIMES
                                       INDEXED BY WS-IX-MSG.
       01  WS-MSG-LRECL                PIC S9(9) COMP VALUE +72.

       PROCEDURE DIVISION.
       0000-PRINCIPAL.
           PERFORM 1000-INITIALISER
           PERFORM 2000-EXTRAIRE-MOUVEMENT UNTIL FIN-CURSEUR
           PERFORM 3000-TERMINER
           GOBACK.

       1000-INITIALISER.
           OPEN OUTPUT F-MVTHIST
           IF NOT MVTHIST-OK
              DISPLAY 'BNKEXT01 - ERREUR OPEN MVTHIST FS=' WS-FS-MVTHIST
              MOVE 16 TO RETURN-CODE
              STOP RUN
           END-IF
           EXEC SQL OPEN CHIST END-EXEC
           IF SQLCODE NOT = 0
              PERFORM 9000-ERREUR-SQL
           END-IF
           PERFORM 8000-LIRE-CURSEUR.

      *----------------------------------------------------------------*
      * UNE LIGNE DB2 -> UN ENREGISTREMENT VSAM                        *
      *----------------------------------------------------------------*
       2000-EXTRAIRE-MOUVEMENT.
           INITIALIZE HIS-ENREG
           MOVE DATE-MVT          TO WS-DATE-ISO
           STRING ISO-AAAA ISO-MM ISO-JJ DELIMITED BY SIZE
                  INTO HIS-DATE
           MOVE HIS-DATE          TO WS-DATE-NUM
           COMPUTE HIS-DATE-INV = 99999999 - WS-DATE-NUM
           MOVE NUM-CPT           TO HIS-NUM-CPT
           MOVE REF-MVT           TO HIS-REF
           MOVE TYPE-MVT          TO HIS-TYPE
           MOVE MONTANT           TO HIS-MONTANT
           MOVE LIBELLE           TO HIS-LIBELLE
           WRITE HIS-ENREG
           IF WS-FS-MVTHIST NOT = '00'
              DISPLAY 'BNKEXT01 - ERREUR WRITE MVTHIST FS='
                      WS-FS-MVTHIST ' CLE=' HIS-CLE
              EXEC SQL CLOSE CHIST END-EXEC
              MOVE 16 TO RETURN-CODE
              STOP RUN
           END-IF
           ADD 1 TO WS-NB-EXTRAITS
           PERFORM 8000-LIRE-CURSEUR.

       3000-TERMINER.
           EXEC SQL CLOSE CHIST END-EXEC
           CLOSE F-MVTHIST
           DISPLAY 'BNKEXT01 - EXTRACTION DE L''HISTORIQUE TERMINEE'
           MOVE WS-NB-EXTRAITS TO WS-ED-NB
           DISPLAY '  MOUVEMENTS EXTRAITS : ' WS-ED-NB
           MOVE 0 TO RETURN-CODE.

       8000-LIRE-CURSEUR.
           EXEC SQL
                FETCH CHIST
                 INTO :NUM-CPT, :REF-MVT, :DATE-MVT,
                      :TYPE-MVT, :MONTANT, :LIBELLE
           END-EXEC
           EVALUATE SQLCODE
               WHEN 0
                   CONTINUE
               WHEN 100
                   SET FIN-CURSEUR TO TRUE
               WHEN OTHER
                   PERFORM 9000-ERREUR-SQL
           END-EVALUATE.

      *----------------------------------------------------------------*
      * ERREUR SQL : DIAGNOSTIC DSNTIAR ET ARRET RC=12                 *
      *----------------------------------------------------------------*
       9000-ERREUR-SQL.
           MOVE SQLCODE TO WS-ED-SQLCODE
           DISPLAY 'BNKEXT01 - ERREUR SQL, SQLCODE = ' WS-ED-SQLCODE
           CALL 'DSNTIAR' USING SQLCA WS-MSG-ERREUR WS-MSG-LRECL
           PERFORM VARYING WS-IX-MSG FROM 1 BY 1
                   UNTIL WS-IX-MSG > 10
              IF WS-MSG-TEXTE(WS-IX-MSG) NOT = SPACES
                 DISPLAY WS-MSG-TEXTE(WS-IX-MSG)
              END-IF
           END-PERFORM
           CLOSE F-MVTHIST
           MOVE 12 TO RETURN-CODE
           STOP RUN.
