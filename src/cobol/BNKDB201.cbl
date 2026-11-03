       IDENTIFICATION DIVISION.
       PROGRAM-ID. BNKDB201.
      *----------------------------------------------------------------*
      * CHARGEMENT DES MOUVEMENTS APPLIQUES DANS L'HISTORIQUE DB2      *
      *                                                                *
      * ENTREE : MVTAPP   MOUVEMENTS APPLIQUES PAR BNKMAJ01    FB 80   *
      * SORTIE : TABLE DB2 MVT_HIST (DCLGEN DCLMVTH)                   *
      *                                                                *
      * PRINCIPES :                                                    *
      *   - COMMIT TOUS LES WS-FREQ-COMMIT MOUVEMENTS                  *
      *   - SQLCODE -803 (CLE EN DOUBLE) : MOUVEMENT DEJA CHARGE,      *
      *     IGNORE ET COMPTE. LE PROGRAMME EST DONC RELANCABLE APRES   *
      *     UN INCIDENT SANS CREER DE DOUBLONS.                        *
      *   - TOUT AUTRE SQLCODE NEGATIF : MESSAGE DSNTIAR, ROLLBACK     *
      *     ET ARRET RC=12                                             *
      *                                                                *
      * EXECUTION : IKJEFT01 / DSN RUN PROGRAM(BNKDB201) PLAN(BNKPLAN) *
      *                                                                *
      * CODES RETOUR : 0 = OK   4 = DOUBLONS IGNORES                   *
      *               12 = ERREUR SQL   16 = ERREUR FICHIER            *
      *----------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT F-MVTAPP  ASSIGN TO MVTAPP
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS IS WS-FS-MVTAPP.

       DATA DIVISION.
       FILE SECTION.
       FD  F-MVTAPP
           RECORDING MODE IS F.
           COPY CPYMVT.

       WORKING-STORAGE SECTION.
           EXEC SQL INCLUDE SQLCA   END-EXEC.
           EXEC SQL INCLUDE DCLMVTH END-EXEC.

       01  WS-FS-MVTAPP                PIC X(02).
       01  WS-FIN-MVTAPP               PIC X(01) VALUE 'N'.
           88  FIN-MVTAPP                        VALUE 'O'.

      *--- DATE AU FORMAT ISO POUR LA COLONNE DATE_MVT ----------------
       01  WS-DATE-ISO.
           05  WS-ISO-AAAA             PIC X(04).
           05  FILLER                  PIC X(01) VALUE '-'.
           05  WS-ISO-MM               PIC X(02).
           05  FILLER                  PIC X(01) VALUE '-'.
           05  WS-ISO-JJ               PIC X(02).

      *--- GESTION DES COMMITS -----------------------------------------
       01  WS-FREQ-COMMIT              PIC 9(05) COMP-3 VALUE 100.
       01  WS-NB-DEPUIS-COMMIT         PIC 9(05) COMP-3 VALUE 0.

      *--- COMPTEURS ---------------------------------------------------
       01  WS-COMPTEURS.
           05  WS-NB-LUS               PIC 9(07) COMP-3 VALUE 0.
           05  WS-NB-INSERES           PIC 9(07) COMP-3 VALUE 0.
           05  WS-NB-DOUBLONS          PIC 9(07) COMP-3 VALUE 0.
           05  WS-NB-COMMITS           PIC 9(07) COMP-3 VALUE 0.
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
           PERFORM 2000-CHARGER-MOUVEMENT UNTIL FIN-MVTAPP
           PERFORM 3000-TERMINER
           GOBACK.

       1000-INITIALISER.
           OPEN INPUT F-MVTAPP
           IF WS-FS-MVTAPP NOT = '00'
              DISPLAY 'BNKDB201 - ERREUR OPEN MVTAPP FS=' WS-FS-MVTAPP
              MOVE 16 TO RETURN-CODE
              STOP RUN
           END-IF
           PERFORM 8000-LIRE-MVTAPP.

      *----------------------------------------------------------------*
      * INSERTION D'UN MOUVEMENT DANS MVT_HIST                         *
      *----------------------------------------------------------------*
       2000-CHARGER-MOUVEMENT.
           MOVE MVT-REF        TO REF-MVT
           MOVE MVT-NUM-CPT    TO NUM-CPT
           MOVE MVT-TYPE       TO TYPE-MVT
           MOVE MVT-MONTANT    TO MONTANT
           MOVE MVT-LIBELLE    TO LIBELLE
           MOVE MVT-DATE-X(1:4) TO WS-ISO-AAAA
           MOVE MVT-DATE-X(5:2) TO WS-ISO-MM
           MOVE MVT-DATE-X(7:2) TO WS-ISO-JJ
           MOVE WS-DATE-ISO    TO DATE-MVT

           EXEC SQL
               INSERT INTO MVT_HIST
                      (REF_MVT, NUM_CPT, TYPE_MVT, MONTANT,
                       DATE_MVT, LIBELLE, TS_CHARGEMENT)
               VALUES (:REF-MVT, :NUM-CPT, :TYPE-MVT, :MONTANT,
                       :DATE-MVT, :LIBELLE, CURRENT TIMESTAMP)
           END-EXEC

           EVALUATE TRUE
               WHEN SQLCODE = 0
                   ADD 1 TO WS-NB-INSERES WS-NB-DEPUIS-COMMIT
               WHEN SQLCODE = -803
                   ADD 1 TO WS-NB-DOUBLONS
                   DISPLAY 'BNKDB201 - DEJA CHARGE, IGNORE : ' MVT-REF
               WHEN OTHER
                   PERFORM 9000-ERREUR-SQL
           END-EVALUATE

           IF WS-NB-DEPUIS-COMMIT >= WS-FREQ-COMMIT
              PERFORM 2500-VALIDER-UNITE-TRAVAIL
           END-IF
           PERFORM 8000-LIRE-MVTAPP.

       2500-VALIDER-UNITE-TRAVAIL.
           EXEC SQL COMMIT END-EXEC
           IF SQLCODE NOT = 0
              PERFORM 9000-ERREUR-SQL
           END-IF
           ADD 1 TO WS-NB-COMMITS
           MOVE 0 TO WS-NB-DEPUIS-COMMIT.

       3000-TERMINER.
           PERFORM 2500-VALIDER-UNITE-TRAVAIL
           CLOSE F-MVTAPP
           DISPLAY 'BNKDB201 - CHARGEMENT DE L''HISTORIQUE TERMINE'
           MOVE WS-NB-LUS      TO WS-ED-NB
           DISPLAY '  MOUVEMENTS LUS       : ' WS-ED-NB
           MOVE WS-NB-INSERES  TO WS-ED-NB
           DISPLAY '  LIGNES INSEREES      : ' WS-ED-NB
           MOVE WS-NB-DOUBLONS TO WS-ED-NB
           DISPLAY '  DOUBLONS IGNORES     : ' WS-ED-NB
           MOVE WS-NB-COMMITS  TO WS-ED-NB
           DISPLAY '  COMMITS EFFECTUES    : ' WS-ED-NB
           IF WS-NB-DOUBLONS > 0
              MOVE 4 TO RETURN-CODE
           ELSE
              MOVE 0 TO RETURN-CODE
           END-IF.

       8000-LIRE-MVTAPP.
           READ F-MVTAPP
           EVALUATE WS-FS-MVTAPP
               WHEN '00'
                   ADD 1 TO WS-NB-LUS
               WHEN '10'
                   SET FIN-MVTAPP TO TRUE
               WHEN OTHER
                   DISPLAY 'BNKDB201 - ERREUR READ MVTAPP FS='
                           WS-FS-MVTAPP
                   EXEC SQL ROLLBACK END-EXEC
                   MOVE 16 TO RETURN-CODE
                   STOP RUN
           END-EVALUATE.

      *----------------------------------------------------------------*
      * ERREUR SQL : DIAGNOSTIC DSNTIAR, ROLLBACK, ARRET RC=12         *
      *----------------------------------------------------------------*
       9000-ERREUR-SQL.
           MOVE SQLCODE TO WS-ED-SQLCODE
           DISPLAY 'BNKDB201 - ERREUR SQL, SQLCODE = ' WS-ED-SQLCODE
           DISPLAY 'BNKDB201 - MOUVEMENT EN COURS  : ' MVT-REF
           CALL 'DSNTIAR' USING SQLCA WS-MSG-ERREUR WS-MSG-LRECL
           PERFORM VARYING WS-IX-MSG FROM 1 BY 1
                   UNTIL WS-IX-MSG > 10
              IF WS-MSG-TEXTE(WS-IX-MSG) NOT = SPACES
                 DISPLAY WS-MSG-TEXTE(WS-IX-MSG)
              END-IF
           END-PERFORM
           EXEC SQL ROLLBACK END-EXEC
           DISPLAY 'BNKDB201 - ROLLBACK EFFECTUE, ARRET DU PROGRAMME'
           MOVE 12 TO RETURN-CODE
           STOP RUN.
