       IDENTIFICATION DIVISION.
       PROGRAM-ID. BNKCON01.
      *----------------------------------------------------------------*
      * TRANSACTION CICS BNKI : CONSULTATION D'UN COMPTE               *
      *                                                                *
      * ECRAN   : MAPSET BNKMS01 / MAP BNKMP01 (BMS, 3270 24 X 80)     *
      * FICHIER : CPTMST = VSAM KSDS DES COMPTES (LECTURE SEULE),      *
      *           LE MEME FICHIER QUE CELUI MIS A JOUR PAR LA CHAINE   *
      *           BATCH BNKCHAIN (PROGRAMME BNKMAJ01)                  *
      *                                                                *
      * MODE PSEUDO-CONVERSATIONNEL : LE PROGRAMME SE TERMINE APRES    *
      * CHAQUE ECRAN (RETURN TRANSID + COMMAREA) ET N'OCCUPE AUCUNE    *
      * RESSOURCE PENDANT QUE L'UTILISATEUR SAISIT.                    *
      *                                                                *
      *   EIBCALEN = 0     PREMIER APPEL : ECRAN VIDE                  *
      *   ENTREE           LECTURE DU COMPTE SAISI ET AFFICHAGE        *
      *   PF3 / CLEAR      FIN DE LA TRANSACTION                       *
      *   AUTRE TOUCHE     MESSAGE D'ERREUR                            *
      *                                                                *
      * TOUTES LES COMMANDES SENSIBLES SONT TESTEES PAR RESP :         *
      *   MAPFAIL (RIEN SAISI), NOTFND (COMPTE INEXISTANT),            *
      *   NOTOPEN / DISABLED (FICHIER FERME, PAR EXEMPLE PENDANT LE    *
      *   BATCH), AUTRES ERREURS AVEC LE CODE RESP AFFICHE.            *
      *----------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SPECIAL-NAMES.
           DECIMAL-POINT IS COMMA.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
      *--- CODES RETOUR CICS -------------------------------------------
       01  WS-RESP                     PIC S9(8) COMP.
       01  WS-RESP-ED                  PIC -(7)9.

      *--- CLE DE LECTURE ET ZONE DE COMMUNICATION ---------------------
       01  WS-CLE                      PIC X(11).
       01  WS-COMMAREA.
           05  CA-DERNIER-CPT          PIC X(11).

      *--- MESSAGE AFFICHE EN LIGNE 22 ---------------------------------
       01  WS-MESSAGE                  PIC X(78).
       01  WS-TYPE-MSG                 PIC X(01).
           88  MSG-INFO                          VALUE 'I'.
           88  MSG-ERREUR                        VALUE 'E'.

      *--- ZONES DE CALCUL ET D'EDITION --------------------------------
       01  WS-SOLDE-DISPO              PIC S9(11)V99 COMP-3.
       01  WS-ED-MONTANT               PIC ---.---.---.--9,99.
       01  WS-DATE-MAJ.
           05  WS-MAJ-AAAA             PIC X(04).
           05  WS-MAJ-MM               PIC X(02).
           05  WS-MAJ-JJ               PIC X(02).
       01  WS-DATE-ED.
           05  WS-ED-JJ                PIC X(02).
           05  FILLER                  PIC X(01) VALUE '/'.
           05  WS-ED-MM                PIC X(02).
           05  FILLER                  PIC X(01) VALUE '/'.
           05  WS-ED-AAAA              PIC X(04).
       01  WS-ABSTIME                  PIC S9(15) COMP-3.
       01  WS-DATE-JOUR                PIC X(10).

       01  WS-MSG-FIN                  PIC X(40) VALUE
           'BNKI - FIN DE LA CONSULTATION DE COMPTE'.

      *--- ENREGISTREMENT DU FICHIER DES COMPTES (COMMUN AU BATCH) -----
           COPY CPYCPT.

      *--- MAP SYMBOLIQUE GENEREE PAR L'ASSEMBLAGE BMS (DSECT) ---------
           COPY BNKMS01.

      *--- CONSTANTES CICS : TOUCHES (DFHAID) ET ATTRIBUTS (DFHBMSCA) --
           COPY DFHAID.
           COPY DFHBMSCA.

       LINKAGE SECTION.
       01  DFHCOMMAREA                 PIC X(11).

       PROCEDURE DIVISION.
       0000-PRINCIPAL.
           EVALUATE TRUE
               WHEN EIBCALEN = 0
                   PERFORM 1000-PREMIER-AFFICHAGE
               WHEN EIBAID = DFHPF3
               WHEN EIBAID = DFHCLEAR
                   PERFORM 9000-FIN-TRANSACTION
               WHEN EIBAID = DFHENTER
                   MOVE DFHCOMMAREA TO WS-COMMAREA
                   PERFORM 2000-TRAITER-SAISIE
               WHEN OTHER
                   MOVE DFHCOMMAREA TO WS-COMMAREA
                   PERFORM 3000-TOUCHE-INVALIDE
           END-EVALUATE

      *    FIN DE LA TACHE : CICS RELANCERA BNKI A LA PROCHAINE TOUCHE
           EXEC CICS RETURN
                TRANSID('BNKI')
                COMMAREA(WS-COMMAREA)
                LENGTH(LENGTH OF WS-COMMAREA)
           END-EXEC
           GOBACK.

      *----------------------------------------------------------------*
      * PREMIER APPEL : ECRAN VIDE                                     *
      *----------------------------------------------------------------*
       1000-PREMIER-AFFICHAGE.
           MOVE SPACES     TO WS-COMMAREA
           MOVE LOW-VALUES TO BNKMP01O
           SET MSG-INFO TO TRUE
           MOVE 'SAISISSEZ UN NUMERO DE COMPTE (11 CHIFFRES)'
             TO WS-MESSAGE
           PERFORM 8000-ENVOYER-ECRAN.

      *----------------------------------------------------------------*
      * TOUCHE ENTREE : RECEPTION, CONTROLE, LECTURE DU COMPTE         *
      *----------------------------------------------------------------*
       2000-TRAITER-SAISIE.
           EXEC CICS RECEIVE
                MAP('BNKMP01')
                MAPSET('BNKMS01')
                INTO(BNKMP01I)
                RESP(WS-RESP)
           END-EXEC

           EVALUATE WS-RESP
               WHEN DFHRESP(NORMAL)
                   MOVE NUMCPTI TO WS-CLE
                   MOVE LOW-VALUES TO BNKMP01O
                   MOVE WS-CLE TO NUMCPTO
                   PERFORM 2100-CONTROLER-ET-LIRE
               WHEN DFHRESP(MAPFAIL)
                   MOVE LOW-VALUES TO BNKMP01O
                   SET MSG-ERREUR TO TRUE
                   MOVE 'AUCUN NUMERO SAISI : TAPEZ UN NUMERO DE COMPTE'
                     TO WS-MESSAGE
               WHEN OTHER
                   MOVE LOW-VALUES TO BNKMP01O
                   PERFORM 7000-ERREUR-CICS
           END-EVALUATE
           PERFORM 8000-ENVOYER-ECRAN.

       2100-CONTROLER-ET-LIRE.
           IF WS-CLE IS NOT NUMERIC
              SET MSG-ERREUR TO TRUE
              MOVE 'LE NUMERO DE COMPTE DOIT COMPORTER 11 CHIFFRES'
                TO WS-MESSAGE
           ELSE
              EXEC CICS READ
                   FILE('CPTMST')
                   INTO(CPT-ENREG)
                   RIDFLD(WS-CLE)
                   RESP(WS-RESP)
              END-EXEC
              EVALUATE WS-RESP
                  WHEN DFHRESP(NORMAL)
                      PERFORM 2200-AFFICHER-COMPTE
                  WHEN DFHRESP(NOTFND)
                      SET MSG-ERREUR TO TRUE
      *               STRING N'EFFACE PAS LA FIN DE LA ZONE RECEPTRICE
                      MOVE SPACES TO WS-MESSAGE
                      STRING 'COMPTE ' WS-CLE ' INEXISTANT'
                             DELIMITED BY SIZE INTO WS-MESSAGE
                  WHEN DFHRESP(NOTOPEN)
                  WHEN DFHRESP(DISABLED)
                      SET MSG-ERREUR TO TRUE
                      MOVE 'FICHIER DES COMPTES FERME (BATCH EN COURS)'
                        TO WS-MESSAGE
                  WHEN OTHER
                      PERFORM 7000-ERREUR-CICS
              END-EVALUATE
           END-IF.

       2200-AFFICHER-COMPTE.
           MOVE WS-CLE            TO CA-DERNIER-CPT
           MOVE CPT-TITULAIRE     TO TITUO

           MOVE CPT-SOLDE         TO WS-ED-MONTANT
           MOVE WS-ED-MONTANT     TO SOLDEO
           IF CPT-SOLDE < ZERO
              MOVE DFHRED         TO SOLDEC
           END-IF

           MOVE CPT-DECOUVERT-AUT TO WS-ED-MONTANT
           MOVE WS-ED-MONTANT     TO DECOUVO

           COMPUTE WS-SOLDE-DISPO = CPT-SOLDE + CPT-DECOUVERT-AUT
           MOVE WS-SOLDE-DISPO    TO WS-ED-MONTANT
           MOVE WS-ED-MONTANT     TO DISPOO

           EVALUATE TRUE
               WHEN CPT-ACTIF
                   MOVE 'ACTIF'   TO STATO
                   MOVE DFHGREEN  TO STATC
               WHEN CPT-BLOQUE
                   MOVE 'BLOQUE'  TO STATO
                   MOVE DFHRED    TO STATC
               WHEN OTHER
                   MOVE 'INCONNU' TO STATO
                   MOVE DFHYELLO  TO STATC
           END-EVALUATE

           MOVE CPT-DATE-MAJ      TO WS-DATE-MAJ
           MOVE WS-MAJ-JJ         TO WS-ED-JJ
           MOVE WS-MAJ-MM         TO WS-ED-MM
           MOVE WS-MAJ-AAAA       TO WS-ED-AAAA
           MOVE WS-DATE-ED        TO DTMAJO

           SET MSG-INFO TO TRUE
           MOVE 'COMPTE TROUVE - AUTRE NUMERO OU PF3 POUR QUITTER'
             TO WS-MESSAGE.

      *----------------------------------------------------------------*
      * TOUCHE NON PREVUE : ON REAFFICHE LE DERNIER NUMERO CONSULTE    *
      *----------------------------------------------------------------*
       3000-TOUCHE-INVALIDE.
           MOVE LOW-VALUES     TO BNKMP01O
           MOVE CA-DERNIER-CPT TO NUMCPTO
           SET MSG-ERREUR TO TRUE
           MOVE 'TOUCHE NON VALIDE : UTILISEZ ENTREE, PF3 OU CLEAR'
             TO WS-MESSAGE
           PERFORM 8000-ENVOYER-ECRAN.

      *----------------------------------------------------------------*
      * ERREUR CICS INATTENDUE : LE CODE RESP EST AFFICHE              *
      *----------------------------------------------------------------*
       7000-ERREUR-CICS.
           MOVE WS-RESP TO WS-RESP-ED
           SET MSG-ERREUR TO TRUE
           MOVE SPACES TO WS-MESSAGE
           STRING 'ERREUR CICS INATTENDUE, RESP = ' WS-RESP-ED
                  DELIMITED BY SIZE INTO WS-MESSAGE.

      *----------------------------------------------------------------*
      * ENVOI DE L'ECRAN : DATE DU JOUR, MESSAGE, CURSEUR SUR LA SAISIE*
      *----------------------------------------------------------------*
       8000-ENVOYER-ECRAN.
           EXEC CICS ASKTIME
                ABSTIME(WS-ABSTIME)
           END-EXEC
           EXEC CICS FORMATTIME
                ABSTIME(WS-ABSTIME)
                DDMMYYYY(WS-DATE-JOUR)
                DATESEP('/')
           END-EXEC
           MOVE WS-DATE-JOUR TO DATEJO

           MOVE WS-MESSAGE TO MSGO
           IF MSG-ERREUR
              MOVE DFHRED   TO MSGC
           ELSE
              MOVE DFHGREEN TO MSGC
           END-IF

      *    LONGUEUR -1 : POSITIONNEMENT DU CURSEUR SUR LE CHAMP (CURSOR)
           MOVE -1 TO NUMCPTL

           EXEC CICS SEND
                MAP('BNKMP01')
                MAPSET('BNKMS01')
                FROM(BNKMP01O)
                ERASE
                CURSOR
           END-EXEC.

      *----------------------------------------------------------------*
      * PF3 / CLEAR : MESSAGE DE FIN ET RETOUR A CICS SANS TRANSID     *
      *----------------------------------------------------------------*
       9000-FIN-TRANSACTION.
           EXEC CICS SEND TEXT
                FROM(WS-MSG-FIN)
                LENGTH(LENGTH OF WS-MSG-FIN)
                ERASE
                FREEKB
           END-EXEC
           EXEC CICS RETURN
           END-EXEC.
