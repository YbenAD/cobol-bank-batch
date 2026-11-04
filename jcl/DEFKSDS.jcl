//DEFKSDS  JOB (ACCT),'INIT COMPTES',CLASS=A,MSGCLASS=X,
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID
//*--------------------------------------------------------------------
//* INITIALISATION DU FICHIER MAITRE DES COMPTES (RELANCABLE)
//*
//* STEP005 : IDCAMS - DEFINITION DE LA BASE GDG DES SAUVEGARDES
//*           (ERREUR IGNOREE SI ELLE EXISTE DEJA : LES SAUVEGARDES
//*           DES RUNS PRECEDENTS SONT CONSERVEES)
//* STEP010 : IDCAMS - SUPPRESSION PUIS DEFINITION DU KSDS
//* STEP020 : BNKINI01 - CHARGEMENT INITIAL DU KSDS
//*
//* REMARQUE : SI TON SYSTEME NE SUBSTITUE PAS &SYSUID DANS LES
//* DONNEES IN-STREAM (SYMBOLS=JCLONLY), REMPLACE-LE PAR TON ID.
//*--------------------------------------------------------------------
//STEP005  EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSIN    DD *,SYMBOLS=JCLONLY
  DEFINE GDG (NAME(&SYSUID..BANK.CPTMST.BKP)      -
              LIMIT(5)                            -
              NOEMPTY                             -
              SCRATCH)
  SET MAXCC = 0
/*
//*--------------------------------------------------------------------
//STEP010  EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSIN    DD *,SYMBOLS=JCLONLY
  DELETE &SYSUID..BANK.CPTMST CLUSTER PURGE
  SET MAXCC = 0
  DEFINE CLUSTER (NAME(&SYSUID..BANK.CPTMST)      -
                  INDEXED                         -
                  KEYS(11 0)                      -
                  RECORDSIZE(100 100)             -
                  FREESPACE(10 10)                -
                  SHAREOPTIONS(2 3)               -
                  REUSE                           -
                  TRACKS(1 1))                    -
         DATA    (NAME(&SYSUID..BANK.CPTMST.DATA) -
                  CONTROLINTERVALSIZE(4096))      -
         INDEX   (NAME(&SYSUID..BANK.CPTMST.INDEX))
/*
//*--------------------------------------------------------------------
//STEP020  EXEC PGM=BNKINI01,COND=(0,NE,STEP010)
//STEPLIB  DD DSN=&SYSUID..LOAD,DISP=SHR
//SEEDCPT  DD DSN=&SYSUID..BANK.SEED.COMPTES,DISP=SHR
//CPTMST   DD DSN=&SYSUID..BANK.CPTMST,DISP=OLD
//SYSOUT   DD SYSOUT=*
