//DEFKSDS  JOB (ACCT),'INIT COMPTES',CLASS=A,MSGCLASS=X,
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID
//*--------------------------------------------------------------------
//* INITIALISATION DU FICHIER MAITRE DES COMPTES
//*
//* STEP010 : IDCAMS - DEFINITION DU KSDS ET DE LA BASE GDG DES
//*           SAUVEGARDES (SUPPRESSION PREALABLE SI EXISTANTS)
//* STEP020 : BNKINI01 - CHARGEMENT INITIAL DU KSDS
//*
//* REMARQUE : SI TON SYSTEME NE SUBSTITUE PAS &SYSUID DANS LES
//* DONNEES IN-STREAM (SYMBOLS=JCLONLY), REMPLACE-LE PAR TON ID.
//*--------------------------------------------------------------------
//STEP010  EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSIN    DD *,SYMBOLS=JCLONLY
  DELETE &SYSUID..BANK.CPTMST CLUSTER PURGE
  DELETE &SYSUID..BANK.CPTMST.BKP GDG FORCE
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
  DEFINE GDG (NAME(&SYSUID..BANK.CPTMST.BKP)      -
              LIMIT(5)                            -
              NOEMPTY                             -
              SCRATCH)
/*
//*--------------------------------------------------------------------
//STEP020  EXEC PGM=BNKINI01,COND=(0,NE,STEP010)
//STEPLIB  DD DSN=&SYSUID..LOAD,DISP=SHR
//SEEDCPT  DD DSN=&SYSUID..BANK.SEED.COMPTES,DISP=SHR
//CPTMST   DD DSN=&SYSUID..BANK.CPTMST,DISP=OLD
//SYSOUT   DD SYSOUT=*
