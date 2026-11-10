       IDENTIFICATION DIVISION.
       PROGRAM-ID. BNKHIS01.
      *----------------------------------------------------------------*
      * TRANSACTION CICS BNKH : HISTORIQUE DES MOUVEMENTS D'UN COMPTE  *
      *                                                                *
      * ECRAN   : MAPSET BNKMS02 / MAP BNKMP02 (10 MOUVEMENTS PAR PAGE)*
      * DONNEES : MVTHIST = KSDS DE L'HISTORIQUE (CPYHIS), EXTRAIT DE  *
      *           LA TABLE DB2 MVT_HIST PAR LE BATCH BNKEXT01          *
      *           CPTMST  = KSDS DES COMPTES, POUR LE NOM DU TITULAIRE *
      *                                                                *
      * PAGINATION PAR PARCOURS VSAM (BROWSE) :                        *
      *   CLE = COMPTE + DATE INVERSEE + REFERENCE : POUR UN COMPTE,   *
      *   L'ORDRE CROISSANT DES CLES VA DU PLUS RECENT AU PLUS ANCIEN. *
      *   ENTREE : STARTBR SUR (COMPTE + LOW-VALUES), PUIS READNEXT    *
      *   PF8    : STARTBR SUR LA DERNIERE CLE AFFICHEE, PUIS READNEXT *
      *   PF7    : STARTBR SUR LA PREMIERE CLE AFFICHEE, PUIS READPREV *
      *            (LIGNES LUES A L'ENVERS, REMISES DANS L'ORDRE)      *
      *   LE PREMIER READNEXT/READPREV RENVOIE L'ENREGISTREMENT DE     *
      *   DEPART, DEJA AFFICHE : IL EST IGNORE.                        *
      *   11 LIGNES SONT LUES POUR 10 AFFICHEES : LA 11E INDIQUE QU'IL *
      *   EXISTE UNE PAGE SUIVANTE.                                    *
      *   LES CLES DE LA PREMIERE ET DE LA DERNIERE LIGNE AFFICHEES    *
      *   SONT CONSERVEES DANS LA COMMAREA ENTRE DEUX ECRANS.          *
      *                                                                *
      * MODE PSEUDO-CONVERSATIONNEL : CHAQUE PARCOURS EST OUVERT ET    *
      * FERME (ENDBR) DANS LA MEME TACHE.                              *
      *                                                                *
      * LES MESSAGES SEULS (PREMIERE/DERNIERE PAGE, TOUCHE INVALIDE)   *
      * SONT ENVOYES EN SEND MAP DATAONLY : SEULE LA LIGNE DE MESSAGE  *
      * EST TRANSMISE, LA LISTE AFFICHEE RESTE A L'ECRAN.              *
      *----------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SPECIAL-NAMES.
           DECIMAL-POINT IS COMMA.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
      *--- CODES RETOUR ------------------------------------------------
       01  WS-RESP                     PIC S9(8) COMP.
       01  WS-RESP-ED                  PIC -(7)9.
       01  WS-ERREUR                   PIC X(01) VALUE 'N'.
           88  ERREUR-DETECTEE                   VALUE 'O'.

      *--- ZONE DE COMMUNICATION ENTRE DEUX ECRANS ---------------------
       01  WS-COMMAREA.
           05  CA-CPT                  PIC X(11).
           05  CA-PAGE                 PIC 9(03).
           05  CA-PREM-CLE             PIC X(31).
           05  CA-DERN-CLE             PIC X(31).
           05  CA-SUITE                PIC X(01).
               88  CA-PAGE-SUIVANTE              VALUE 'O'.
               88  CA-PAS-DE-SUITE               VALUE 'N'.

      *--- PARCOURS VSAM -----------------------------------------------
       01  WS-RID                      PIC X(31).
       01  WS-CLE-DEPART               PIC X(31).
       01  WS-FIN-PARCOURS             PIC X(01).
           88  FIN-PARCOURS                      VALUE 'O'.

      *--- MOUVEMENTS DE LA PAGE (11 POSTES : LE 11E SERT DE TEMOIN) ---
       01  WS-PAGE.
           05  WS-NB-LIGNES            PIC 9(02) VALUE 0.
           05  WS-MVT OCCURS 11 TIMES.
               10  T-CLE               PIC X(31).
               10  T-DATE              PIC X(08).
               10  T-TYPE              PIC X(01).
               10  T-MONTANT           PIC S9(9)V99 COMP-3.
               10  T-LIBELLE           PIC X(30).
       01  WS-TAMPON.
           05  WS-NB-TAMPON            PIC 9(02).
           05  WS-TMP OCCURS 10 TIMES.
               10  TMP-CLE             PIC X(31).
               10  TMP-DATE            PIC X(08).
               10  TMP-TYPE            PIC X(01).
               10  TMP-MONTANT         PIC S9(9)V99 COMP-3.
               10  TMP-LIBELLE         PIC X(30).
       01  WS-I                        PIC 9(02).
       01  WS-J                        PIC 9(02).

      *--- LIGNE DE DETAIL (75 CARACTERES, ALIGNEE SUR L'EN-TETE) ------
       01  WS-LIGNE.
           05  L-DATE                  PIC X(10).
           05  FILLER                  PIC X(02).
           05  L-REF                   PIC X(12).
           05  FILLER                  PIC X(02).
           05  L-TYPE                  PIC X(01).
           05  FILLER                  PIC X(02).
           05  L-MONTANT               PIC ZZZ.ZZZ.ZZ9,99.
           05  FILLER                  PIC X(02).
           05  L-LIBELLE               PIC X(30).
       01  WS-COULEUR                  PIC X(01).
       01  WS-DATE-MVT.
           05  DM-AAAA                 PIC X(04).
           05  DM-MM                   PIC X(02).
           05  DM-JJ                   PIC X(02).

      *--- DIVERS ------------------------------------------------------
       01  WS-CLE                      PIC X(11).
       01  WS-MESSAGE                  PIC X(78).
       01  WS-TYPE-MSG                 PIC X(01).
           88  MSG-INFO                          VALUE 'I'.
           88  MSG-ERREUR                        VALUE 'E'.
       01  WS-ED-PAGE                  PIC ZZ9.
       01  WS-ABSTIME                  PIC S9(15) COMP-3.
       01  WS-DATE-JOUR                PIC X(10).
       01  WS-MSG-FIN                  PIC X(40) VALUE
           'BNKH - FIN DE LA CONSULTATION'.

           COPY CPYCPT.
           COPY CPYHIS.
           COPY BNKMS02.
           COPY DFHAID.
           COPY DFHBMSCA.

       LINKAGE SECTION.
       01  DFHCOMMAREA                 PIC X(77).

       PROCEDURE DIVISION.
       0000-PRINCIPAL.
           EVALUATE TRUE
               WHEN EIBCALEN = 0
                   PERFORM 1000-PREMIER-AFFICHAGE
               WHEN EIBAID = DFHPF3
               WHEN EIBAID = DFHCLEAR
                   PERFORM 9000-FIN-TRANSACTION
               WHEN OTHER
                   MOVE DFHCOMMAREA TO WS-COMMAREA
                   EVALUATE EIBAID
                       WHEN DFHENTER
                           PERFORM 2000-RECHERCHER
                       WHEN DFHPF8
                           PERFORM 3000-PAGE-SUIVANTE
                       WHEN DFHPF7
                           PERFORM 4000-PAGE-PRECEDENTE
                       WHEN OTHER
                           SET MSG-ERREUR TO TRUE
                           MOVE 'TOUCHE NON VALIDE'
                             TO WS-MESSAGE
                           PERFORM 8500-ENVOYER-MESSAGE
                   END-EVALUATE
           END-EVALUATE

           EXEC CICS RETURN
                TRANSID('BNKH')
                COMMAREA(WS-COMMAREA)
                LENGTH(LENGTH OF WS-COMMAREA)
           END-EXEC
           GOBACK.

      *----------------------------------------------------------------*
      * PREMIER APPEL : ECRAN VIDE                                     *
      *----------------------------------------------------------------*
       1000-PREMIER-AFFICHAGE.
           MOVE SPACES TO WS-COMMAREA
           MOVE 0      TO CA-PAGE WS-NB-LIGNES
           MOVE LOW-VALUES TO BNKMP02O
           SET MSG-INFO TO TRUE
           MOVE 'SAISISSEZ UN NUMERO DE COMPTE (11 CHIFFRES)'
             TO WS-MESSAGE
           PERFORM 8000-ENVOYER-ECRAN.

      *----------------------------------------------------------------*
      * ENTREE : NOUVELLE RECHERCHE, PREMIERE PAGE                     *
      *----------------------------------------------------------------*
       2000-RECHERCHER.
           EXEC CICS RECEIVE
                MAP('BNKMP02')
                MAPSET('BNKMS02')
                INTO(BNKMP02I)
                RESP(WS-RESP)
           END-EXEC
           EVALUATE WS-RESP
               WHEN DFHRESP(NORMAL)
                   MOVE NUMCPTI TO WS-CLE
               WHEN DFHRESP(MAPFAIL)
                   MOVE SPACES TO WS-CLE
               WHEN OTHER
                   PERFORM 7000-ERREUR-CICS
                   PERFORM 8500-ENVOYER-MESSAGE
                   EXIT PARAGRAPH
           END-EVALUATE

           IF WS-CLE IS NOT NUMERIC
              SET MSG-ERREUR TO TRUE
              MOVE 'LE NUMERO DE COMPTE DOIT COMPORTER 11 CHIFFRES'
                TO WS-MESSAGE
              PERFORM 8500-ENVOYER-MESSAGE
              EXIT PARAGRAPH
           END-IF

           MOVE LOW-VALUES TO BNKMP02O
           MOVE WS-CLE TO CA-CPT
           MOVE 0      TO CA-PAGE WS-NB-LIGNES
           SET CA-PAS-DE-SUITE TO TRUE
           PERFORM 5000-LIRE-TITULAIRE
           IF NOT ERREUR-DETECTEE
      *       DEBUT DU COMPTE : LOW-VALUES APRES LE NUMERO DE COMPTE
              MOVE CA-CPT     TO WS-RID(1:11)
              MOVE LOW-VALUES TO WS-RID(12:20)
              PERFORM 6000-LIRE-VERS-ANCIENS
           END-IF
           IF NOT ERREUR-DETECTEE
              MOVE 1 TO CA-PAGE
              SET MSG-INFO TO TRUE
              EVALUATE TRUE
                  WHEN WS-NB-LIGNES = 0
                      MOVE 'AUCUN MOUVEMENT DANS L''HISTORIQUE'
                        TO WS-MESSAGE
                  WHEN CA-PAGE-SUIVANTE
                      MOVE 'PF8 = MOUVEMENTS PLUS ANCIENS' TO WS-MESSAGE
                  WHEN OTHER
                      MOVE 'TOUS LES MOUVEMENTS SONT AFFICHES'
                        TO WS-MESSAGE
              END-EVALUATE
           END-IF
           PERFORM 8000-ENVOYER-ECRAN.

      *----------------------------------------------------------------*
      * PF8 : PAGE SUIVANTE (MOUVEMENTS PLUS ANCIENS)                  *
      *----------------------------------------------------------------*
       3000-PAGE-SUIVANTE.
           EVALUATE TRUE
               WHEN CA-CPT = SPACES
                   SET MSG-ERREUR TO TRUE
                   MOVE 'SAISISSEZ D''ABORD UN NUMERO DE COMPTE'
                     TO WS-MESSAGE
                   PERFORM 8500-ENVOYER-MESSAGE
               WHEN NOT CA-PAGE-SUIVANTE
                   SET MSG-ERREUR TO TRUE
                   MOVE 'DERNIERE PAGE : PAS DE MOUVEMENT PLUS ANCIEN'
                     TO WS-MESSAGE
                   PERFORM 8500-ENVOYER-MESSAGE
               WHEN OTHER
                   MOVE LOW-VALUES TO BNKMP02O
                   PERFORM 5000-LIRE-TITULAIRE
                   IF NOT ERREUR-DETECTEE
                      MOVE CA-DERN-CLE TO WS-RID
                      PERFORM 6000-LIRE-VERS-ANCIENS
                   END-IF
                   IF NOT ERREUR-DETECTEE
                      ADD 1 TO CA-PAGE
                      SET MSG-INFO TO TRUE
                      MOVE 'PF7 = PLUS RECENTS   PF8 = PLUS ANCIENS'
                        TO WS-MESSAGE
                   END-IF
                   PERFORM 8000-ENVOYER-ECRAN
           END-EVALUATE.

      *----------------------------------------------------------------*
      * PF7 : PAGE PRECEDENTE (MOUVEMENTS PLUS RECENTS)                *
      *----------------------------------------------------------------*
       4000-PAGE-PRECEDENTE.
           EVALUATE TRUE
               WHEN CA-CPT = SPACES
                   SET MSG-ERREUR TO TRUE
                   MOVE 'SAISISSEZ D''ABORD UN NUMERO DE COMPTE'
                     TO WS-MESSAGE
                   PERFORM 8500-ENVOYER-MESSAGE
               WHEN CA-PAGE <= 1
                   SET MSG-ERREUR TO TRUE
                   MOVE 'PREMIERE PAGE : PAS DE MOUVEMENT PLUS RECENT'
                     TO WS-MESSAGE
                   PERFORM 8500-ENVOYER-MESSAGE
               WHEN OTHER
                   MOVE LOW-VALUES TO BNKMP02O
                   PERFORM 5000-LIRE-TITULAIRE
                   IF NOT ERREUR-DETECTEE
                      MOVE CA-PREM-CLE TO WS-RID
                      PERFORM 6500-LIRE-VERS-RECENTS
                   END-IF
                   IF NOT ERREUR-DETECTEE
                      SUBTRACT 1 FROM CA-PAGE
                      SET MSG-INFO TO TRUE
                      IF CA-PAGE = 1
                         MOVE 'PF8 = MOUVEMENTS PLUS ANCIENS'
                           TO WS-MESSAGE
                      ELSE
                         MOVE 'PF7 = PLUS RECENTS   PF8 = PLUS ANCIENS'
                           TO WS-MESSAGE
                      END-IF
                   END-IF
                   PERFORM 8000-ENVOYER-ECRAN
           END-EVALUATE.

      *----------------------------------------------------------------*
      * TITULAIRE DU COMPTE (KSDS CPTMST)                              *
      *----------------------------------------------------------------*
       5000-LIRE-TITULAIRE.
           MOVE 'N' TO WS-ERREUR
           EXEC CICS READ
                FILE('CPTMST')
                INTO(CPT-ENREG)
                RIDFLD(CA-CPT)
                RESP(WS-RESP)
           END-EXEC
           EVALUATE WS-RESP
               WHEN DFHRESP(NORMAL)
                   MOVE CPT-TITULAIRE TO TITUO
               WHEN DFHRESP(NOTFND)
                   SET ERREUR-DETECTEE TO TRUE
                   SET MSG-ERREUR TO TRUE
                   MOVE SPACES TO WS-MESSAGE
                   STRING 'COMPTE ' CA-CPT ' INEXISTANT'
                          DELIMITED BY SIZE INTO WS-MESSAGE
               WHEN OTHER
      *            FICHIER FERME (BATCH) : L'HISTORIQUE RESTE VISIBLE
                   MOVE '(TITULAIRE INDISPONIBLE)' TO TITUO
           END-EVALUATE.

      *----------------------------------------------------------------*
      * PARCOURS VERS LES MOUVEMENTS PLUS ANCIENS (READNEXT)           *
      * DEPART : WS-RID. ON LIT JUSQU'A 11 LIGNES DU COMPTE ; S'IL Y   *
      * EN A 11, UNE PAGE SUIVANTE EXISTE ET 10 SONT AFFICHEES.        *
      *----------------------------------------------------------------*
       6000-LIRE-VERS-ANCIENS.
           MOVE 0      TO WS-NB-LIGNES
           MOVE WS-RID TO WS-CLE-DEPART
           EXEC CICS STARTBR
                FILE('MVTHIST')
                RIDFLD(WS-RID)
                GTEQ
                RESP(WS-RESP)
           END-EXEC
           EVALUATE WS-RESP
               WHEN DFHRESP(NORMAL)
                   CONTINUE
               WHEN DFHRESP(NOTFND)
      *            AUCUNE CLE APRES LE POINT DE DEPART
                   SET CA-PAS-DE-SUITE TO TRUE
                   EXIT PARAGRAPH
               WHEN OTHER
                   PERFORM 7100-ERREUR-HISTORIQUE
                   EXIT PARAGRAPH
           END-EVALUATE

           MOVE 'N' TO WS-FIN-PARCOURS
           PERFORM UNTIL FIN-PARCOURS OR WS-NB-LIGNES = 11
              EXEC CICS READNEXT
                   FILE('MVTHIST')
                   INTO(HIS-ENREG)
                   RIDFLD(WS-RID)
                   RESP(WS-RESP)
              END-EXEC
              EVALUATE WS-RESP
                  WHEN DFHRESP(NORMAL)
                      EVALUATE TRUE
                          WHEN HIS-NUM-CPT NOT = CA-CPT
                              SET FIN-PARCOURS TO TRUE
                          WHEN HIS-CLE = WS-CLE-DEPART
      *                       ENREGISTREMENT DE DEPART, DEJA AFFICHE
                              CONTINUE
                          WHEN OTHER
                              ADD 1 TO WS-NB-LIGNES
                              PERFORM 6100-RANGER-MOUVEMENT
                      END-EVALUATE
                  WHEN DFHRESP(ENDFILE)
                      SET FIN-PARCOURS TO TRUE
                  WHEN OTHER
                      PERFORM 7100-ERREUR-HISTORIQUE
                      SET FIN-PARCOURS TO TRUE
              END-EVALUATE
           END-PERFORM
           EXEC CICS ENDBR
                FILE('MVTHIST')
                RESP(WS-RESP)
           END-EXEC

           IF WS-NB-LIGNES = 11
              SET CA-PAGE-SUIVANTE TO TRUE
              MOVE 10 TO WS-NB-LIGNES
           ELSE
              SET CA-PAS-DE-SUITE TO TRUE
           END-IF
           PERFORM 6800-MEMORISER-CLES.

       6100-RANGER-MOUVEMENT.
           MOVE HIS-CLE     TO T-CLE(WS-NB-LIGNES)
           MOVE HIS-DATE    TO T-DATE(WS-NB-LIGNES)
           MOVE HIS-TYPE    TO T-TYPE(WS-NB-LIGNES)
           MOVE HIS-MONTANT TO T-MONTANT(WS-NB-LIGNES)
           MOVE HIS-LIBELLE TO T-LIBELLE(WS-NB-LIGNES).

      *----------------------------------------------------------------*
      * PARCOURS VERS LES MOUVEMENTS PLUS RECENTS (READPREV)           *
      * DEPART : PREMIERE CLE AFFICHEE (ELLE EXISTE). LES LIGNES SONT  *
      * LUES A L'ENVERS : ON LES REMET DANS L'ORDRE D'AFFICHAGE.       *
      *----------------------------------------------------------------*
       6500-LIRE-VERS-RECENTS.
           MOVE 0      TO WS-NB-TAMPON
           MOVE WS-RID TO WS-CLE-DEPART
           EXEC CICS STARTBR
                FILE('MVTHIST')
                RIDFLD(WS-RID)
                GTEQ
                RESP(WS-RESP)
           END-EXEC
           IF WS-RESP NOT = DFHRESP(NORMAL)
              PERFORM 7100-ERREUR-HISTORIQUE
              EXIT PARAGRAPH
           END-IF

           MOVE 'N' TO WS-FIN-PARCOURS
           PERFORM UNTIL FIN-PARCOURS OR WS-NB-TAMPON = 10
              EXEC CICS READPREV
                   FILE('MVTHIST')
                   INTO(HIS-ENREG)
                   RIDFLD(WS-RID)
                   RESP(WS-RESP)
              END-EXEC
              EVALUATE WS-RESP
                  WHEN DFHRESP(NORMAL)
                      EVALUATE TRUE
                          WHEN HIS-NUM-CPT NOT = CA-CPT
                              SET FIN-PARCOURS TO TRUE
                          WHEN HIS-CLE = WS-CLE-DEPART
                              CONTINUE
                          WHEN OTHER
                              ADD 1 TO WS-NB-TAMPON
                              MOVE HIS-CLE     TO TMP-CLE(WS-NB-TAMPON)
                              MOVE HIS-DATE    TO TMP-DATE(WS-NB-TAMPON)
                              MOVE HIS-TYPE    TO TMP-TYPE(WS-NB-TAMPON)
                              MOVE HIS-MONTANT
                                TO TMP-MONTANT(WS-NB-TAMPON)
                              MOVE HIS-LIBELLE
                                TO TMP-LIBELLE(WS-NB-TAMPON)
                      END-EVALUATE
                  WHEN DFHRESP(ENDFILE)
                      SET FIN-PARCOURS TO TRUE
                  WHEN OTHER
      *               NOTFND : LA CLE DE DEPART N'EXISTE PLUS (FICHIER
      *               RECHARGE ENTRE DEUX ECRANS)
                      PERFORM 7100-ERREUR-HISTORIQUE
                      SET FIN-PARCOURS TO TRUE
              END-EVALUATE
           END-PERFORM
           EXEC CICS ENDBR
                FILE('MVTHIST')
                RESP(WS-RESP)
           END-EXEC

           MOVE WS-NB-TAMPON TO WS-NB-LIGNES
           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > WS-NB-TAMPON
              COMPUTE WS-J = WS-NB-TAMPON - WS-I + 1
              MOVE WS-TMP(WS-J) TO WS-MVT(WS-I)
           END-PERFORM
      *    ON REVIENT EN ARRIERE : LA PAGE QU'ON QUITTE EXISTE TOUJOURS
           SET CA-PAGE-SUIVANTE TO TRUE
           PERFORM 6800-MEMORISER-CLES.

       6800-MEMORISER-CLES.
           IF WS-NB-LIGNES > 0
              MOVE T-CLE(1)            TO CA-PREM-CLE
              MOVE T-CLE(WS-NB-LIGNES) TO CA-DERN-CLE
           END-IF.

      *----------------------------------------------------------------*
      * ERREURS                                                        *
      *----------------------------------------------------------------*
       7000-ERREUR-CICS.
           MOVE WS-RESP TO WS-RESP-ED
           SET ERREUR-DETECTEE TO TRUE
           SET MSG-ERREUR TO TRUE
           MOVE SPACES TO WS-MESSAGE
           STRING 'ERREUR CICS INATTENDUE, RESP = ' WS-RESP-ED
                  DELIMITED BY SIZE INTO WS-MESSAGE.

       7100-ERREUR-HISTORIQUE.
           EVALUATE WS-RESP
               WHEN DFHRESP(NOTOPEN)
               WHEN DFHRESP(DISABLED)
                   SET ERREUR-DETECTEE TO TRUE
                   SET MSG-ERREUR TO TRUE
                   MOVE 'HISTORIQUE INDISPONIBLE (EXTRACTION EN COURS)'
                     TO WS-MESSAGE
               WHEN DFHRESP(NOTFND)
                   SET ERREUR-DETECTEE TO TRUE
                   SET MSG-ERREUR TO TRUE
                   MOVE 'HISTORIQUE MIS A JOUR : REFAITES LA RECHERCHE'
                     TO WS-MESSAGE
               WHEN OTHER
                   PERFORM 7000-ERREUR-CICS
           END-EVALUATE.

      *----------------------------------------------------------------*
      * ENVOI COMPLET DE L'ECRAN (ERASE)                               *
      *----------------------------------------------------------------*
       8000-ENVOYER-ECRAN.
           PERFORM 8900-DATE-DU-JOUR
           MOVE CA-CPT TO NUMCPTO
           IF CA-PAGE > 0
              MOVE CA-PAGE TO WS-ED-PAGE
              MOVE WS-ED-PAGE TO PAGEO
           END-IF
           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > 10
              PERFORM 8100-PREPARER-LIGNE
              PERFORM 8200-RANGER-LIGNE
           END-PERFORM
           PERFORM 8800-MESSAGE
           EXEC CICS SEND
                MAP('BNKMP02')
                MAPSET('BNKMS02')
                FROM(BNKMP02O)
                ERASE
                CURSOR
           END-EXEC.

      *    LIGNE WS-I : DETAIL DU MOUVEMENT, OU BLANCS APRES LA PAGE
      *    DEBITS EN ROUGE, CREDITS EN VERT
       8100-PREPARER-LIGNE.
           MOVE SPACES TO WS-LIGNE
           MOVE DFHNEUTR TO WS-COULEUR
           IF WS-I <= WS-NB-LIGNES
              MOVE T-DATE(WS-I) TO WS-DATE-MVT
              STRING DM-JJ '/' DM-MM '/' DM-AAAA
                     DELIMITED BY SIZE INTO L-DATE
              MOVE T-CLE(WS-I)(20:12) TO L-REF
              MOVE T-TYPE(WS-I)       TO L-TYPE
              MOVE T-MONTANT(WS-I)    TO L-MONTANT
              MOVE T-LIBELLE(WS-I)    TO L-LIBELLE
              IF T-TYPE(WS-I) = 'D'
                 MOVE DFHRED   TO WS-COULEUR
              ELSE
                 MOVE DFHGREEN TO WS-COULEUR
              END-IF
           END-IF.

       8200-RANGER-LIGNE.
           EVALUATE WS-I
               WHEN 1
                   MOVE WS-LIGNE TO LIG01O
                   MOVE WS-COULEUR TO LIG01C
               WHEN 2
                   MOVE WS-LIGNE TO LIG02O
                   MOVE WS-COULEUR TO LIG02C
               WHEN 3
                   MOVE WS-LIGNE TO LIG03O
                   MOVE WS-COULEUR TO LIG03C
               WHEN 4
                   MOVE WS-LIGNE TO LIG04O
                   MOVE WS-COULEUR TO LIG04C
               WHEN 5
                   MOVE WS-LIGNE TO LIG05O
                   MOVE WS-COULEUR TO LIG05C
               WHEN 6
                   MOVE WS-LIGNE TO LIG06O
                   MOVE WS-COULEUR TO LIG06C
               WHEN 7
                   MOVE WS-LIGNE TO LIG07O
                   MOVE WS-COULEUR TO LIG07C
               WHEN 8
                   MOVE WS-LIGNE TO LIG08O
                   MOVE WS-COULEUR TO LIG08C
               WHEN 9
                   MOVE WS-LIGNE TO LIG09O
                   MOVE WS-COULEUR TO LIG09C
               WHEN 10
                   MOVE WS-LIGNE TO LIG10O
                   MOVE WS-COULEUR TO LIG10C
           END-EVALUATE.

      *----------------------------------------------------------------*
      * ENVOI DU MESSAGE SEUL (DATAONLY) : LA LISTE RESTE A L'ECRAN    *
      *----------------------------------------------------------------*
       8500-ENVOYER-MESSAGE.
           MOVE LOW-VALUES TO BNKMP02O
           PERFORM 8800-MESSAGE
           EXEC CICS SEND
                MAP('BNKMP02')
                MAPSET('BNKMS02')
                FROM(BNKMP02O)
                DATAONLY
                CURSOR
           END-EXEC.

       8800-MESSAGE.
           MOVE WS-MESSAGE TO MSGO
           IF MSG-ERREUR
              MOVE DFHRED   TO MSGC
           ELSE
              MOVE DFHGREEN TO MSGC
           END-IF
      *    LONGUEUR -1 : CURSEUR POSITIONNE SUR LA SAISIE DU COMPTE
           MOVE -1 TO NUMCPTL.

       8900-DATE-DU-JOUR.
           EXEC CICS ASKTIME
                ABSTIME(WS-ABSTIME)
           END-EXEC
           EXEC CICS FORMATTIME
                ABSTIME(WS-ABSTIME)
                DDMMYYYY(WS-DATE-JOUR)
                DATESEP('/')
           END-EXEC
           MOVE WS-DATE-JOUR TO DATEJO.

      *----------------------------------------------------------------*
      * PF3 / CLEAR : FIN DE LA TRANSACTION                            *
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
