      ******************************************************************
      * DCLGEN TABLE(MVT_HIST)                                         *
      *        LANGUAGE(COBOL)                                         *
      *        QUOTE                                                   *
      * ... IS THE DCLGEN COMMAND THAT MADE THE FOLLOWING STATEMENTS   *
      ******************************************************************
           EXEC SQL DECLARE MVT_HIST TABLE
           ( REF_MVT                        CHAR(12) NOT NULL,
             NUM_CPT                        CHAR(11) NOT NULL,
             TYPE_MVT                       CHAR(1) NOT NULL,
             MONTANT                        DECIMAL(11, 2) NOT NULL,
             DATE_MVT                       DATE NOT NULL,
             LIBELLE                        CHAR(30) NOT NULL,
             TS_CHARGEMENT                  TIMESTAMP NOT NULL
           ) END-EXEC.
      ******************************************************************
      * COBOL DECLARATION FOR TABLE MVT_HIST                           *
      ******************************************************************
       01  DCLMVT-HIST.
           10 REF-MVT              PIC X(12).
           10 NUM-CPT              PIC X(11).
           10 TYPE-MVT             PIC X(1).
           10 MONTANT              PIC S9(9)V9(2) USAGE COMP-3.
           10 DATE-MVT             PIC X(10).
           10 LIBELLE              PIC X(30).
           10 TS-CHARGEMENT        PIC X(26).
      ******************************************************************
      * THE NUMBER OF COLUMNS DESCRIBED BY THIS DECLARATION IS 7       *
      ******************************************************************
