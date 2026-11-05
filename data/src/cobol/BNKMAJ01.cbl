       IDENTIFICATION DIVISION.
       PROGRAM-ID. BNKMAJ01.
      *----------------------------------------------------------------*
      * MISE A JOUR DU FICHIER MAITRE DES COMPTES (VSAM KSDS)          *
      * A PARTIR DES MOUVEMENTS VALIDES ET TRIES                       *
      *                                                                *
      * ENTREE : MVTTRI   MOUVEMENTS TRIES PAR COMPTE / DATE / TYPE    *
      *                   (CREDITS AVANT DEBITS LE MEME JOUR)  FB 80   *
      *          SYSIN    CARTE PARAMETRE : DATE DE TRAITEMENT         *
      * E/S    : CPTMST   VSAM KSDS DES COMPTES (ACCES DIRECT)         *
      * SORTIE : MVTAPP   MOUVEMENTS APPLIQUES (POUR DB2)      FB 80   *
      *          MVTREJ   MOUVEMENTS REJETES                   FB 120  *
      *          RAPPORT  COMPTE RENDU D'EXECUTION             FB 132  *
      *                                                                *
      * PRINCIPE : TRAITEMENT PAR RUPTURE SUR LE NUMERO DE COMPTE.     *
      *   - UNE SEULE LECTURE DU KSDS PAR COMPTE (READ DIRECT)         *
      *   - LE SOLDE EST CALCULE EN MEMOIRE MOUVEMENT PAR MOUVEMENT    *
      *   - UN SEUL REWRITE PAR COMPTE, EN FIN DE RUPTURE              *
      *                                                                *
      * REJETS : R10 COMPTE INEXISTANT                                 *
      *          R11 COMPTE BLOQUE                                     *
      *          R12 DEBIT DEPASSANT LE DECOUVERT AUTORISE             *
      *                                                                *
      * CODES RETOUR : 0 = OK   4 = REJETS PRESENTS                    *
      *               16 = ERREUR FICHIER OU FICHIER NON TRIE          *
      *----------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SPECIAL-NAMES.
           DECIMAL-POINT IS COMMA.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT F-MVTTRI  ASSIGN TO MVTTRI
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS IS WS-FS-MVTTRI.
           SELECT F-CPTMST  ASSIGN TO CPTMST
                  ORGANIZATION IS INDEXED
                  ACCESS MODE IS RANDOM
                  RECORD KEY IS CPT-NUM
                  FILE STATUS IS WS-FS-CPTMST.
           SELECT F-MVTAPP  ASSIGN TO MVTAPP
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS IS WS-FS-MVTAPP.
           SELECT F-MVTREJ  ASSIGN TO MVTREJ
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS IS WS-FS-MVTREJ.
           SELECT F-RAPPORT ASSIGN TO RAPPORT
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS IS WS-FS-RAPPORT.

       DATA DIVISION.
       FILE SECTION.
       FD  F-MVTTRI
           RECORDING MODE IS F
           BLOCK CONTAINS 0 RECORDS.
           COPY CPYMVT.

       FD  F-CPTMST.
           COPY CPYCPT.

       FD  F-MVTAPP
           RECORDING MODE IS F
           BLOCK CONTAINS 0 RECORDS.
       01  APP-ENREG                   PIC X(80).

       FD  F-MVTREJ
           RECORDING MODE IS F
           BLOCK CONTAINS 0 RECORDS.
           COPY CPYREJ.

       FD  F-RAPPORT
           RECORDING MODE IS F
           BLOCK CONTAINS 0 RECORDS.
       01  RAP-LIGNE                   PIC X(132).

       WORKING-STORAGE SECTION.
      *--- FILE STATUS -------------------------------------------------
       01  WS-FS-MVTTRI                PIC X(02).
       01  WS-FS-CPTMST                PIC X(02).
      *    '97' = OPEN OK APRES VERIFY IMPLICITE (VSAM SUR Z/OS)
           88  CPTMST-OPEN-OK                    VALUE '00' '97'.
       01  WS-FS-MVTAPP                PIC X(02).
       01  WS-FS-MVTREJ                PIC X(02).
       01  WS-FS-RAPPORT               PIC X(02).
       01  WS-FIN-MVTTRI               PIC X(01) VALUE 'N'.
           88  FIN-MVTTRI                        VALUE 'O'.

      *--- DATE DE TRAITEMENT ------------------------------------------
       01  WS-CARTE-PARAM              PIC X(80) VALUE SPACES.
       01  WS-DATE-SYSTEME             PIC X(21).
       01  WS-DATE-TRT.
           05  WS-DATE-TRT-AAAA        PIC X(04).
           05  WS-DATE-TRT-MM          PIC X(02).
           05  WS-DATE-TRT-JJ          PIC X(02).

      *--- GESTION DE LA RUPTURE ---------------------------------------
       01  WS-CPT-COURANT              PIC X(11).
       01  WS-CPT-PRECEDENT            PIC X(11) VALUE LOW-VALUES.
       01  WS-ETAT-COMPTE              PIC X(01).
           88  CPT-TROUVE                        VALUE 'T'.
           88  CPT-INCONNU                       VALUE 'I'.
       01  WS-SOLDE-AVANT              PIC S9(11)V99 COMP-3.
       01  WS-SOLDE-COURANT            PIC S9(11)V99 COMP-3.
       01  WS-SOLDE-SIMULE             PIC S9(11)V99 COMP-3.
       01  WS-NB-APP-CPT               PIC 9(05)     COMP-3.
       01  WS-NB-REJ-CPT               PIC 9(05)     COMP-3.

      *--- REJET EN COURS ----------------------------------------------
       01  WS-CODE-REJET               PIC X(03).
       01  WS-MOTIF-REJET              PIC X(37).

      *--- COMPTEURS ET TOTAUX DE CONTROLE -----------------------------
       01  WS-TOTAUX.
           05  WS-NB-LUS               PIC 9(07)     COMP-3 VALUE 0.
           05  WS-NB-APPLIQUES         PIC 9(07)     COMP-3 VALUE 0.
           05  WS-NB-REJETES           PIC 9(07)     COMP-3 VALUE 0.
           05  WS-NB-CPT-MAJ           PIC 9(07)     COMP-3 VALUE 0.
           05  WS-TOT-CREDITS          PIC 9(13)V99  COMP-3 VALUE 0.
           05  WS-TOT-DEBITS           PIC 9(13)V99  COMP-3 VALUE 0.
       01  WS-NB-CONTROLE              PIC 9(07)     COMP-3.

      *--- LIGNES DU COMPTE RENDU --------------------------------------
       01  WS-L-TITRE.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  FILLER                  PIC X(50) VALUE
               'BNKMAJ01 - COMPTE RENDU DE MISE A JOUR DES COMPTES'.
           05  FILLER                  PIC X(10) VALUE '   DATE : '.
           05  LT-JJ                   PIC X(02).
           05  FILLER                  PIC X(01) VALUE '/'.
           05  LT-MM                   PIC X(02).
           05  FILLER                  PIC X(01) VALUE '/'.
           05  LT-AAAA                 PIC X(04).

       01  WS-L-TIRETS.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  FILLER                  PIC X(85) VALUE ALL '-'.

       01  WS-L-ENTETE.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  FILLER                  PIC X(11) VALUE 'COMPTE'.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(18) VALUE
               '       SOLDE AVANT'.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(04) VALUE ' APP'.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(04) VALUE ' REJ'.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(18) VALUE
               '       SOLDE APRES'.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(20) VALUE 'ETAT'.

       01  WS-L-DETAIL.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  LD-COMPTE               PIC X(11).
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  LD-SOLDE-AVANT          PIC ---.---.---.--9,99.
           05  LD-SOLDE-AVANT-X REDEFINES LD-SOLDE-AVANT
                                       PIC X(18).
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  LD-NB-APP               PIC ZZZ9.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  LD-NB-REJ               PIC ZZZ9.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  LD-SOLDE-APRES          PIC ---.---.---.--9,99.
           05  LD-SOLDE-APRES-X REDEFINES LD-SOLDE-APRES
                                       PIC X(18).
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  LD-ETAT                 PIC X(20).

       01  WS-L-TOTAL.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  LTO-LIBELLE             PIC X(30).
           05  FILLER                  PIC X(03) VALUE ' : '.
           05  LTO-VALEUR              PIC X(20).

       01  WS-ED-NB                    PIC ZZZ.ZZ9.
       01  WS-ED-MONTANT               PIC ZZZ.ZZZ.ZZZ.ZZ9,99.

       PROCEDURE DIVISION.
       0000-PRINCIPAL.
           PERFORM 1000-INITIALISER
           PERFORM 2000-TRAITER-COMPTE UNTIL FIN-MVTTRI
           PERFORM 3000-TERMINER
           GOBACK.

      *----------------------------------------------------------------*
      * INITIALISATION                                                 *
      *----------------------------------------------------------------*
       1000-INITIALISER.
           MOVE FUNCTION CURRENT-DATE TO WS-DATE-SYSTEME
           ACCEPT WS-CARTE-PARAM
           IF WS-CARTE-PARAM(1:8) IS NUMERIC
              MOVE WS-CARTE-PARAM(1:8)  TO WS-DATE-TRT
           ELSE
              MOVE WS-DATE-SYSTEME(1:8) TO WS-DATE-TRT
           END-IF
           DISPLAY 'BNKMAJ01 - DATE DE TRAITEMENT : ' WS-DATE-TRT

           OPEN INPUT F-MVTTRI
           IF WS-FS-MVTTRI NOT = '00'
              DISPLAY 'BNKMAJ01 - ERREUR OPEN MVTTRI FS=' WS-FS-MVTTRI
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           OPEN I-O F-CPTMST
           IF NOT CPTMST-OPEN-OK
              DISPLAY 'BNKMAJ01 - ERREUR OPEN CPTMST FS=' WS-FS-CPTMST
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           OPEN OUTPUT F-MVTAPP
           IF WS-FS-MVTAPP NOT = '00'
              DISPLAY 'BNKMAJ01 - ERREUR OPEN MVTAPP FS=' WS-FS-MVTAPP
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           OPEN OUTPUT F-MVTREJ
           IF WS-FS-MVTREJ NOT = '00'
              DISPLAY 'BNKMAJ01 - ERREUR OPEN MVTREJ FS=' WS-FS-MVTREJ
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           OPEN OUTPUT F-RAPPORT
           IF WS-FS-RAPPORT NOT = '00'
              DISPLAY 'BNKMAJ01 - ERREUR OPEN RAPPORT FS='
                      WS-FS-RAPPORT
              PERFORM 9999-ARRET-ANORMAL
           END-IF

           PERFORM 1100-ECRIRE-ENTETE
           PERFORM 8000-LIRE-MVTTRI.

       1100-ECRIRE-ENTETE.
           MOVE WS-DATE-TRT-JJ   TO LT-JJ
           MOVE WS-DATE-TRT-MM   TO LT-MM
           MOVE WS-DATE-TRT-AAAA TO LT-AAAA
           MOVE WS-L-TITRE  TO RAP-LIGNE
           PERFORM 8500-ECRIRE-RAPPORT
           MOVE WS-L-TIRETS TO RAP-LIGNE
           PERFORM 8500-ECRIRE-RAPPORT
           MOVE WS-L-ENTETE TO RAP-LIGNE
           PERFORM 8500-ECRIRE-RAPPORT
           MOVE WS-L-TIRETS TO RAP-LIGNE
           PERFORM 8500-ECRIRE-RAPPORT.

      *----------------------------------------------------------------*
      * TRAITEMENT D'UN COMPTE (RUPTURE SUR LE NUMERO DE COMPTE)       *
      *----------------------------------------------------------------*
       2000-TRAITER-COMPTE.
           MOVE MVT-NUM-CPT TO WS-CPT-COURANT
           MOVE 0 TO WS-NB-APP-CPT WS-NB-REJ-CPT
           PERFORM 2100-LIRE-COMPTE
           PERFORM 2200-TRAITER-MOUVEMENT
               UNTIL FIN-MVTTRI
                  OR MVT-NUM-CPT NOT = WS-CPT-COURANT
           PERFORM 2300-CLOTURER-COMPTE.

       2100-LIRE-COMPTE.
           MOVE WS-CPT-COURANT TO CPT-NUM
           READ F-CPTMST
           EVALUATE WS-FS-CPTMST
               WHEN '00'
                   SET CPT-TROUVE TO TRUE
                   MOVE CPT-SOLDE TO WS-SOLDE-AVANT
                                     WS-SOLDE-COURANT
               WHEN '23'
                   SET CPT-INCONNU TO TRUE
                   MOVE 0 TO WS-SOLDE-AVANT WS-SOLDE-COURANT
               WHEN OTHER
                   DISPLAY 'BNKMAJ01 - ERREUR READ CPTMST FS='
                           WS-FS-CPTMST ' CLE=' WS-CPT-COURANT
                   PERFORM 9999-ARRET-ANORMAL
           END-EVALUATE.

       2200-TRAITER-MOUVEMENT.
           EVALUATE TRUE
               WHEN CPT-INCONNU
                   MOVE 'R10' TO WS-CODE-REJET
                   MOVE 'COMPTE INEXISTANT' TO WS-MOTIF-REJET
                   PERFORM 2900-ECRIRE-REJET
               WHEN CPT-BLOQUE
                   MOVE 'R11' TO WS-CODE-REJET
                   MOVE 'COMPTE BLOQUE' TO WS-MOTIF-REJET
                   PERFORM 2900-ECRIRE-REJET
               WHEN MVT-CREDIT
                   ADD MVT-MONTANT TO WS-SOLDE-COURANT
                   ADD MVT-MONTANT TO WS-TOT-CREDITS
                   PERFORM 2800-ECRIRE-APPLIQUE
               WHEN MVT-DEBIT
                   COMPUTE WS-SOLDE-SIMULE =
                           WS-SOLDE-COURANT - MVT-MONTANT
                   IF WS-SOLDE-SIMULE + CPT-DECOUVERT-AUT < ZERO
                      MOVE 'R12' TO WS-CODE-REJET
                      MOVE 'DECOUVERT AUTORISE DEPASSE'
                        TO WS-MOTIF-REJET
                      PERFORM 2900-ECRIRE-REJET
                   ELSE
                      MOVE WS-SOLDE-SIMULE TO WS-SOLDE-COURANT
                      ADD MVT-MONTANT TO WS-TOT-DEBITS
                      PERFORM 2800-ECRIRE-APPLIQUE
                   END-IF
           END-EVALUATE
           PERFORM 8000-LIRE-MVTTRI.

      *----------------------------------------------------------------*
      * FIN DE RUPTURE : REWRITE DU COMPTE + LIGNE DE DETAIL           *
      *----------------------------------------------------------------*
       2300-CLOTURER-COMPTE.
           MOVE WS-CPT-COURANT TO LD-COMPTE
           MOVE WS-NB-APP-CPT  TO LD-NB-APP
           MOVE WS-NB-REJ-CPT  TO LD-NB-REJ
           EVALUATE TRUE
               WHEN CPT-INCONNU
                   MOVE SPACES TO LD-SOLDE-AVANT-X LD-SOLDE-APRES-X
                   MOVE 'COMPTE INEXISTANT' TO LD-ETAT
               WHEN WS-NB-APP-CPT > 0
                   MOVE WS-SOLDE-COURANT TO CPT-SOLDE
                   MOVE WS-DATE-TRT      TO CPT-DATE-MAJ
                   REWRITE CPT-ENREG
                   IF WS-FS-CPTMST NOT = '00'
                      DISPLAY 'BNKMAJ01 - ERREUR REWRITE CPTMST FS='
                              WS-FS-CPTMST ' CLE=' CPT-NUM
                      PERFORM 9999-ARRET-ANORMAL
                   END-IF
                   ADD 1 TO WS-NB-CPT-MAJ
                   MOVE WS-SOLDE-AVANT   TO LD-SOLDE-AVANT
                   MOVE WS-SOLDE-COURANT TO LD-SOLDE-APRES
                   MOVE 'MIS A JOUR' TO LD-ETAT
               WHEN OTHER
                   MOVE WS-SOLDE-AVANT TO LD-SOLDE-AVANT
                                          LD-SOLDE-APRES
                   IF CPT-BLOQUE
                      MOVE 'COMPTE BLOQUE' TO LD-ETAT
                   ELSE
                      MOVE 'INCHANGE' TO LD-ETAT
                   END-IF
           END-EVALUATE
           MOVE WS-L-DETAIL TO RAP-LIGNE
           PERFORM 8500-ECRIRE-RAPPORT.

       2800-ECRIRE-APPLIQUE.
           WRITE APP-ENREG FROM MVT-ENREG
           IF WS-FS-MVTAPP NOT = '00'
              DISPLAY 'BNKMAJ01 - ERREUR WRITE MVTAPP FS=' WS-FS-MVTAPP
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           ADD 1 TO WS-NB-APP-CPT WS-NB-APPLIQUES.

       2900-ECRIRE-REJET.
           MOVE MVT-ENREG      TO REJ-MVT
           MOVE WS-CODE-REJET  TO REJ-CODE
           MOVE WS-MOTIF-REJET TO REJ-MOTIF
           WRITE REJ-ENREG
           IF WS-FS-MVTREJ NOT = '00'
              DISPLAY 'BNKMAJ01 - ERREUR WRITE MVTREJ FS=' WS-FS-MVTREJ
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           ADD 1 TO WS-NB-REJ-CPT WS-NB-REJETES.

      *----------------------------------------------------------------*
      * FIN DE TRAITEMENT : TOTAUX DE CONTROLE ET CODE RETOUR          *
      *----------------------------------------------------------------*
       3000-TERMINER.
           MOVE WS-L-TIRETS TO RAP-LIGNE
           PERFORM 8500-ECRIRE-RAPPORT

           MOVE 'MOUVEMENTS LUS'          TO LTO-LIBELLE
           MOVE WS-NB-LUS                 TO WS-ED-NB
           MOVE WS-ED-NB                  TO LTO-VALEUR
           PERFORM 3100-ECRIRE-TOTAL
           MOVE 'MOUVEMENTS APPLIQUES'    TO LTO-LIBELLE
           MOVE WS-NB-APPLIQUES           TO WS-ED-NB
           MOVE WS-ED-NB                  TO LTO-VALEUR
           PERFORM 3100-ECRIRE-TOTAL
           MOVE 'MOUVEMENTS REJETES'      TO LTO-LIBELLE
           MOVE WS-NB-REJETES             TO WS-ED-NB
           MOVE WS-ED-NB                  TO LTO-VALEUR
           PERFORM 3100-ECRIRE-TOTAL
           MOVE 'COMPTES MIS A JOUR'      TO LTO-LIBELLE
           MOVE WS-NB-CPT-MAJ             TO WS-ED-NB
           MOVE WS-ED-NB                  TO LTO-VALEUR
           PERFORM 3100-ECRIRE-TOTAL
           MOVE 'TOTAL DES CREDITS'       TO LTO-LIBELLE
           MOVE WS-TOT-CREDITS            TO WS-ED-MONTANT
           MOVE WS-ED-MONTANT             TO LTO-VALEUR
           PERFORM 3100-ECRIRE-TOTAL
           MOVE 'TOTAL DES DEBITS'        TO LTO-LIBELLE
           MOVE WS-TOT-DEBITS             TO WS-ED-MONTANT
           MOVE WS-ED-MONTANT             TO LTO-VALEUR
           PERFORM 3100-ECRIRE-TOTAL

      *    CONTROLE D'EQUILIBRE : LUS = APPLIQUES + REJETES
           COMPUTE WS-NB-CONTROLE = WS-NB-APPLIQUES + WS-NB-REJETES
           MOVE 'CONTROLE LUS = APP + REJ'  TO LTO-LIBELLE
           IF WS-NB-CONTROLE = WS-NB-LUS
              MOVE 'OK' TO LTO-VALEUR
           ELSE
              MOVE 'KO - ANOMALIE' TO LTO-VALEUR
           END-IF
           PERFORM 3100-ECRIRE-TOTAL

           CLOSE F-MVTTRI F-CPTMST F-MVTAPP F-MVTREJ F-RAPPORT

           DISPLAY 'BNKMAJ01 - FIN DE TRAITEMENT'
           MOVE WS-NB-LUS       TO WS-ED-NB
           DISPLAY '  MOUVEMENTS LUS       : ' WS-ED-NB
           MOVE WS-NB-APPLIQUES TO WS-ED-NB
           DISPLAY '  MOUVEMENTS APPLIQUES : ' WS-ED-NB
           MOVE WS-NB-REJETES   TO WS-ED-NB
           DISPLAY '  MOUVEMENTS REJETES   : ' WS-ED-NB

           IF WS-NB-CONTROLE NOT = WS-NB-LUS
              DISPLAY 'BNKMAJ01 - TOTAUX DE CONTROLE DESEQUILIBRES'
              MOVE 16 TO RETURN-CODE
           ELSE
              IF WS-NB-REJETES > 0
                 MOVE 4 TO RETURN-CODE
              ELSE
                 MOVE 0 TO RETURN-CODE
              END-IF
           END-IF.

       3100-ECRIRE-TOTAL.
           MOVE WS-L-TOTAL TO RAP-LIGNE
           PERFORM 8500-ECRIRE-RAPPORT
           MOVE SPACES TO LTO-VALEUR.

      *----------------------------------------------------------------*
      * LECTURE DES MOUVEMENTS AVEC CONTROLE DE SEQUENCE               *
      *----------------------------------------------------------------*
       8000-LIRE-MVTTRI.
           READ F-MVTTRI
           EVALUATE WS-FS-MVTTRI
               WHEN '00'
                   ADD 1 TO WS-NB-LUS
                   IF MVT-NUM-CPT < WS-CPT-PRECEDENT
                      DISPLAY 'BNKMAJ01 - FICHIER NON TRIE : '
                              MVT-NUM-CPT ' APRES ' WS-CPT-PRECEDENT
                      PERFORM 9999-ARRET-ANORMAL
                   END-IF
                   MOVE MVT-NUM-CPT TO WS-CPT-PRECEDENT
               WHEN '10'
                   SET FIN-MVTTRI TO TRUE
               WHEN OTHER
                   DISPLAY 'BNKMAJ01 - ERREUR READ MVTTRI FS='
                           WS-FS-MVTTRI
                   PERFORM 9999-ARRET-ANORMAL
           END-EVALUATE.

       8500-ECRIRE-RAPPORT.
           WRITE RAP-LIGNE
           IF WS-FS-RAPPORT NOT = '00'
              DISPLAY 'BNKMAJ01 - ERREUR WRITE RAPPORT FS='
                      WS-FS-RAPPORT
              PERFORM 9999-ARRET-ANORMAL
           END-IF.

       9999-ARRET-ANORMAL.
           DISPLAY 'BNKMAJ01 - ARRET ANORMAL DU PROGRAMME'
           DISPLAY 'BNKMAJ01 - LES MISES A JOUR DEJA FAITES SONT'
           DISPLAY '  CONSERVEES : RESTAURER LA SAUVEGARDE DE CPTMST'
           DISPLAY '  (STEP025) AVANT DE RELANCER LA CHAINE.'
           MOVE 16 TO RETURN-CODE
           STOP RUN.
