       IDENTIFICATION DIVISION.
       PROGRAM-ID. BNKINI01.
      *----------------------------------------------------------------*
      * CHARGEMENT INITIAL DU FICHIER MAITRE DES COMPTES (VSAM KSDS)   *
      *                                                                *
      * ENTREE : SEEDCPT  FICHIER SEQUENTIEL FB 80 (ZONES DISPLAY)     *
      * SORTIE : CPTMST   VSAM KSDS, CLE = NUMERO DE COMPTE            *
      *                                                                *
      * LE FICHIER D'ENTREE DOIT ETRE TRIE PAR NUMERO DE COMPTE :      *
      * UNE CLE HORS SEQUENCE OU EN DOUBLE PROVOQUE UN ARRET RC=16.    *
      *                                                                *
      * CODES RETOUR : 0 = OK   16 = ERREUR FICHIER                    *
      *----------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT F-SEEDCPT ASSIGN TO SEEDCPT
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS IS WS-FS-SEED.
           SELECT F-CPTMST  ASSIGN TO CPTMST
                  ORGANIZATION IS INDEXED
                  ACCESS MODE IS SEQUENTIAL
                  RECORD KEY IS CPT-NUM
                  FILE STATUS IS WS-FS-CPTMST.

       DATA DIVISION.
       FILE SECTION.
       FD  F-SEEDCPT
           RECORDING MODE IS F.
       01  SEED-ENREG.
           05  SEED-NUM                PIC X(11).
           05  SEED-TITULAIRE          PIC X(30).
           05  SEED-SOLDE              PIC S9(11)V99
                                       SIGN IS LEADING SEPARATE.
           05  SEED-DECOUVERT          PIC 9(07)V99.
           05  SEED-STATUT             PIC X(01).
           05  FILLER                  PIC X(15).

       FD  F-CPTMST.
           COPY CPYCPT.

       WORKING-STORAGE SECTION.
       01  WS-FS-SEED                  PIC X(02).
       01  WS-FS-CPTMST                PIC X(02).
           88  CPTMST-OK                         VALUE '00' '97'.
       01  WS-FIN-SEED                 PIC X(01) VALUE 'N'.
           88  FIN-SEED                          VALUE 'O'.
       01  WS-NB-LUS                   PIC 9(07) COMP-3 VALUE 0.
       01  WS-NB-ECRITS                PIC 9(07) COMP-3 VALUE 0.
       01  WS-ED-NB                    PIC Z(6)9.
       01  WS-DATE-JOUR                PIC X(21).

       PROCEDURE DIVISION.
       0000-PRINCIPAL.
           PERFORM 1000-INITIALISER
           PERFORM 2000-CHARGER-COMPTE UNTIL FIN-SEED
           PERFORM 3000-TERMINER
           GOBACK.

       1000-INITIALISER.
           MOVE FUNCTION CURRENT-DATE TO WS-DATE-JOUR
           OPEN INPUT F-SEEDCPT
           IF WS-FS-SEED NOT = '00'
              DISPLAY 'BNKINI01 - ERREUR OPEN SEEDCPT FS=' WS-FS-SEED
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           OPEN OUTPUT F-CPTMST
           IF NOT CPTMST-OK
              DISPLAY 'BNKINI01 - ERREUR OPEN CPTMST FS=' WS-FS-CPTMST
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           PERFORM 8000-LIRE-SEED.

       2000-CHARGER-COMPTE.
           INITIALIZE CPT-ENREG
           MOVE SEED-NUM               TO CPT-NUM
           MOVE SEED-TITULAIRE         TO CPT-TITULAIRE
           MOVE SEED-SOLDE             TO CPT-SOLDE
           MOVE SEED-DECOUVERT         TO CPT-DECOUVERT-AUT
           MOVE SEED-STATUT            TO CPT-STATUT
           MOVE WS-DATE-JOUR(1:8)      TO CPT-DATE-MAJ
           WRITE CPT-ENREG
           IF WS-FS-CPTMST NOT = '00'
              DISPLAY 'BNKINI01 - ERREUR WRITE CPTMST FS='
                      WS-FS-CPTMST ' CLE=' CPT-NUM
              PERFORM 9999-ARRET-ANORMAL
           END-IF
           ADD 1 TO WS-NB-ECRITS
           PERFORM 8000-LIRE-SEED.

       3000-TERMINER.
           CLOSE F-SEEDCPT F-CPTMST
           DISPLAY 'BNKINI01 - CHARGEMENT DU FICHIER MAITRE TERMINE'
           MOVE WS-NB-LUS TO WS-ED-NB
           DISPLAY '  COMPTES LUS    : ' WS-ED-NB
           MOVE WS-NB-ECRITS TO WS-ED-NB
           DISPLAY '  COMPTES CHARGES: ' WS-ED-NB
           MOVE 0 TO RETURN-CODE.

       8000-LIRE-SEED.
           READ F-SEEDCPT
           EVALUATE WS-FS-SEED
               WHEN '00'
                   ADD 1 TO WS-NB-LUS
               WHEN '10'
                   SET FIN-SEED TO TRUE
               WHEN OTHER
                   DISPLAY 'BNKINI01 - ERREUR READ SEEDCPT FS='
                           WS-FS-SEED
                   PERFORM 9999-ARRET-ANORMAL
           END-EVALUATE.

       9999-ARRET-ANORMAL.
           DISPLAY 'BNKINI01 - ARRET ANORMAL DU PROGRAMME'
           MOVE 16 TO RETURN-CODE
           STOP RUN.
