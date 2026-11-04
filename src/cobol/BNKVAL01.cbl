       IDENTIFICATION DIVISION.
       PROGRAM-ID. BNKVAL01.
      *----------------------------------------------------------------*
      * VALIDATION DES MOUVEMENTS BANCAIRES DU JOUR                    *
      *                                                                *
      * ENTREE : MVTIN    MOUVEMENTS BRUTS          FB 80  (CPYMVT)    *
      *          SYSIN    CARTE PARAMETRE : DATE DE TRAITEMENT         *
      *                   AAAAMMJJ EN COLONNES 1-8 (SI ABSENTE OU      *
      *                   INVALIDE : DATE SYSTEME)                     *
      * SORTIE : MVTOK    MOUVEMENTS VALIDES        FB 80  (CPYMVT)    *
      *          MVTREJ   MOUVEMENTS REJETES        FB 120 (CPYREJ)    *
      *                                                                *
      * CONTROLES (LE PREMIER EN ERREUR DETERMINE LE CODE REJET) :     *
      *   R01 REFERENCE ABSENTE                                        *
      *   R02 NUMERO DE COMPTE NON NUMERIQUE                           *
      *   R03 TYPE DE MOUVEMENT DIFFERENT DE D / C                     *
      *   R04 MONTANT NON NUMERIQUE                                    *
      *   R05 MONTANT NUL                                              *
      *   R06 DATE NON NUMERIQUE                                       *
      *   R07 DATE INVALIDE (MOIS, JOUR, ANNEES BISSEXTILES)           *
      *   R08 DATE POSTERIEURE A LA DATE DE TRAITEMENT                 *
      *                                                                *
      * CODES RETOUR : 0 = AUCUN REJET   4 = REJETS PRESENTS           *
      *               16 = ERREUR FICHIER                              *
      *----------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT F-MVTIN   ASSIGN TO MVTIN
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS IS WS-FS-MVTIN.
           SELECT F-MVTOK   ASSIGN TO MVTOK
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS IS WS-FS-MVTOK.
           SELECT F-MVTREJ  ASSIGN TO MVTREJ
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS IS WS-FS-MVTREJ.

       DATA DIVISION.
       FILE SECTION.
       FD  F-MVTIN
           RECORDING MODE IS F
           BLOCK CONTAINS 0 RECORDS.
           COPY CPYMVT.

       FD  F-MVTOK
           RECORDING MODE IS F
           BLOCK CONTAINS 0 RECORDS.
       01  OK-ENREG                    PIC X(80).

       FD  F-MVTREJ
           RECORDING MODE IS F
           BLOCK CONTAINS 0 RECORDS.
           COPY CPYREJ.

       WORKING-STORAGE SECTION.
      *--- FILE STATUS -------------------------------------------------
       01  WS-FS-MVTIN                 PIC X(02).
       01  WS-FS-MVTOK                 PIC X(02).
       01  WS-FS-MVTREJ                PIC X(02).
       01  WS-FIN-MVTIN                PIC X(01) VALUE 'N'.
           88  FIN-MVTIN                         VALUE 'O'.

      *--- DATE DE TRAITEMENT ------------------------------------------
       01  WS-CARTE-PARAM              PIC X(80) VALUE SPACES.
       01  WS-DATE-TRT                 PIC X(08).
       01  WS-DATE-SYSTEME             PIC X(21).

      *--- RESULTAT DES CONTROLES --------------------------------------
       01  WS-CODE-REJET               PIC X(03).
           88  MVT-VALIDE                        VALUE SPACES.
       01  WS-MOTIF-REJET              PIC X(37).

      *--- CALCUL DU NOMBRE DE JOURS DU MOIS ---------------------------
       01  WS-CALCUL-DATE.
           05  WS-JOURS-MAX            PIC 9(02).
           05  WS-QUOTIENT             PIC 9(04).
           05  WS-RESTE-4              PIC 9(04).
           05  WS-RESTE-100            PIC 9(04).
           05  WS-RESTE-400            PIC 9(04).

      *--- COMPTEURS ---------------------------------------------------
       01  WS-COMPTEURS.
           05  WS-NB-LUS               PIC 9(07) COMP-3 VALUE 0.
           05  WS-NB-VALIDES           PIC 9(07) COMP-3 VALUE 0.
           05  WS-NB-REJETES           PIC 9(07) COMP-3 VALUE 0.
       01  WS-ED-NB                    PIC Z(6)9.

       PROCEDURE DIVISION.
       0000-PRINCIPAL.
           PERFORM 1000-INITIALISER
           PERFORM 2000-TRAITER-MOUVEMENT UNTIL FIN-MVTIN
           PERFORM 3000-TERMINER
           GOBACK.

      *----------------------------------------------------------------*
      * INITIALISATION : DATE DE TRAITEMENT, OUVERTURES, 1ERE LECTURE  *
      *----------------------------------------------------------------*
       1000-INITIALISER.
           MOVE FUNCTION CURRENT-DATE TO WS-DATE-SYSTEME
           ACCEPT WS-CARTE-PARAM
           IF WS-CARTE-PARAM(1:8) IS NUMERIC
              MOVE WS-CARTE-PARAM(1:8)  TO WS-DATE-TRT
           ELSE
              MOVE WS-DATE-SYSTEME(1:8) TO WS-DATE-TRT
           END-IF
           DISPLAY 'BNKVAL01 - DATE DE TRAITEMENT : ' WS-DATE-TRT

           OPEN INPUT  F-MVTIN
           IF WS-FS-MVTIN NOT = '00'
              DISPLAY 'BNKVAL01 - ERREUR OPEN MVTIN FS=' WS-FS-MVTIN
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           OPEN OUTPUT F-MVTOK
           IF WS-FS-MVTOK NOT = '00'
              DISPLAY 'BNKVAL01 - ERREUR OPEN MVTOK FS=' WS-FS-MVTOK
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           OPEN OUTPUT F-MVTREJ
           IF WS-FS-MVTREJ NOT = '00'
              DISPLAY 'BNKVAL01 - ERREUR OPEN MVTREJ FS=' WS-FS-MVTREJ
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           PERFORM 8000-LIRE-MVTIN.

      *----------------------------------------------------------------*
      * TRAITEMENT D'UN MOUVEMENT : CONTROLE PUIS ORIENTATION          *
      *----------------------------------------------------------------*
       2000-TRAITER-MOUVEMENT.
           MOVE SPACES TO WS-CODE-REJET WS-MOTIF-REJET
           PERFORM 2100-CONTROLER-MOUVEMENT
           IF MVT-VALIDE
              PERFORM 2800-ECRIRE-VALIDE
           ELSE
              PERFORM 2900-ECRIRE-REJET
           END-IF
           PERFORM 8000-LIRE-MVTIN.

       2100-CONTROLER-MOUVEMENT.
           EVALUATE TRUE
               WHEN MVT-REF = SPACES
                   MOVE 'R01' TO WS-CODE-REJET
                   MOVE 'REFERENCE ABSENTE' TO WS-MOTIF-REJET
               WHEN MVT-NUM-CPT IS NOT NUMERIC
                   MOVE 'R02' TO WS-CODE-REJET
                   MOVE 'NUMERO DE COMPTE NON NUMERIQUE'
                     TO WS-MOTIF-REJET
               WHEN NOT MVT-DEBIT AND NOT MVT-CREDIT
                   MOVE 'R03' TO WS-CODE-REJET
                   MOVE 'TYPE DE MOUVEMENT INVALIDE'
                     TO WS-MOTIF-REJET
               WHEN MVT-MONTANT-X IS NOT NUMERIC
                   MOVE 'R04' TO WS-CODE-REJET
                   MOVE 'MONTANT NON NUMERIQUE' TO WS-MOTIF-REJET
               WHEN MVT-MONTANT = ZERO
                   MOVE 'R05' TO WS-CODE-REJET
                   MOVE 'MONTANT NUL' TO WS-MOTIF-REJET
               WHEN OTHER
                   PERFORM 2200-CONTROLER-DATE
           END-EVALUATE.

      *----------------------------------------------------------------*
      * CONTROLE DE LA DATE DE VALEUR (AAAAMMJJ)                       *
      * NB : FUNCTION TEST-DATE-YYYYMMDD FERAIT LE MEME TRAVAIL ; LE   *
      * CALCUL EST ECRIT ICI EXPLICITEMENT A TITRE DE DEMONSTRATION.   *
      *----------------------------------------------------------------*
       2200-CONTROLER-DATE.
           IF MVT-DATE-X IS NOT NUMERIC
              MOVE 'R06' TO WS-CODE-REJET
              MOVE 'DATE NON NUMERIQUE' TO WS-MOTIF-REJET
           ELSE
              IF MVT-DATE-MM < 1 OR MVT-DATE-MM > 12
                 MOVE 'R07' TO WS-CODE-REJET
                 MOVE 'DATE INVALIDE (MOIS)' TO WS-MOTIF-REJET
              ELSE
                 PERFORM 2210-CALCULER-JOURS-MAX
                 IF MVT-DATE-JJ < 1 OR MVT-DATE-JJ > WS-JOURS-MAX
                    MOVE 'R07' TO WS-CODE-REJET
                    MOVE 'DATE INVALIDE (JOUR)' TO WS-MOTIF-REJET
                 ELSE
                    IF MVT-DATE-X > WS-DATE-TRT
                       MOVE 'R08' TO WS-CODE-REJET
                       MOVE 'DATE POSTERIEURE A LA DATE DE TRT'
                         TO WS-MOTIF-REJET
                    END-IF
                 END-IF
              END-IF
           END-IF.

       2210-CALCULER-JOURS-MAX.
           EVALUATE MVT-DATE-MM
               WHEN 04
               WHEN 06
               WHEN 09
               WHEN 11
                   MOVE 30 TO WS-JOURS-MAX
               WHEN 02
                   PERFORM 2220-TESTER-BISSEXTILE
               WHEN OTHER
                   MOVE 31 TO WS-JOURS-MAX
           END-EVALUATE.

      *    BISSEXTILE : DIVISIBLE PAR 4 ET NON PAR 100, OU PAR 400
       2220-TESTER-BISSEXTILE.
           DIVIDE MVT-DATE-AAAA BY 4   GIVING WS-QUOTIENT
                                       REMAINDER WS-RESTE-4
           DIVIDE MVT-DATE-AAAA BY 100 GIVING WS-QUOTIENT
                                       REMAINDER WS-RESTE-100
           DIVIDE MVT-DATE-AAAA BY 400 GIVING WS-QUOTIENT
                                       REMAINDER WS-RESTE-400
           IF WS-RESTE-400 = 0
              OR (WS-RESTE-4 = 0 AND WS-RESTE-100 NOT = 0)
              MOVE 29 TO WS-JOURS-MAX
           ELSE
              MOVE 28 TO WS-JOURS-MAX
           END-IF.

       2800-ECRIRE-VALIDE.
           WRITE OK-ENREG FROM MVT-ENREG
           IF WS-FS-MVTOK NOT = '00'
              DISPLAY 'BNKVAL01 - ERREUR WRITE MVTOK FS=' WS-FS-MVTOK
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           ADD 1 TO WS-NB-VALIDES.

       2900-ECRIRE-REJET.
           MOVE MVT-ENREG      TO REJ-MVT
           MOVE WS-CODE-REJET  TO REJ-CODE
           MOVE WS-MOTIF-REJET TO REJ-MOTIF
           WRITE REJ-ENREG
           IF WS-FS-MVTREJ NOT = '00'
              DISPLAY 'BNKVAL01 - ERREUR WRITE MVTREJ FS=' WS-FS-MVTREJ
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           ADD 1 TO WS-NB-REJETES.

      *----------------------------------------------------------------*
      * FIN DE TRAITEMENT : FERMETURES, STATISTIQUES, CODE RETOUR      *
      *----------------------------------------------------------------*
       3000-TERMINER.
           CLOSE F-MVTIN F-MVTOK F-MVTREJ
           DISPLAY 'BNKVAL01 - STATISTIQUES DE VALIDATION'
           MOVE WS-NB-LUS     TO WS-ED-NB
           DISPLAY '  MOUVEMENTS LUS     : ' WS-ED-NB
           MOVE WS-NB-VALIDES TO WS-ED-NB
           DISPLAY '  MOUVEMENTS VALIDES : ' WS-ED-NB
           MOVE WS-NB-REJETES TO WS-ED-NB
           DISPLAY '  MOUVEMENTS REJETES : ' WS-ED-NB
           IF WS-NB-REJETES > 0
              MOVE 4 TO RETURN-CODE
           ELSE
              MOVE 0 TO RETURN-CODE
           END-IF.

       8000-LIRE-MVTIN.
           READ F-MVTIN
           EVALUATE WS-FS-MVTIN
               WHEN '00'
                   ADD 1 TO WS-NB-LUS
               WHEN '10'
                   SET FIN-MVTIN TO TRUE
               WHEN OTHER
                   DISPLAY 'BNKVAL01 - ERREUR READ MVTIN FS='
                           WS-FS-MVTIN
                   PERFORM 9999-ARRET-ANORMAL
           END-EVALUATE.

       9999-ARRET-ANORMAL.
           DISPLAY 'BNKVAL01 - ARRET ANORMAL DU PROGRAMME'
           MOVE 16 TO RETURN-CODE
           STOP RUN.
