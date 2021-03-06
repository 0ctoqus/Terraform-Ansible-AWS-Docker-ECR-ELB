CREATE DATABASE iktos;
use iktos;

CREATE TABLE Adult (
    age INT(25),
    workclass VARCHAR(25),
    fnlwgt INT(25),
    education VARCHAR(25),
    education_num INT(25),
    marital_tatus VARCHAR(25),
    occupation VARCHAR(25),
    relationship VARCHAR(25),
    race VARCHAR(25),
    sex VARCHAR(25),
    capital_gain INT(25),
    capital_loss INT(25),
    hours_per_week INT(25),
    native_country VARCHAR(25),
    volume VARCHAR(25)
);

LOAD DATA LOCAL INFILE  '/var/lib/mysql-files/adult.data' into table Adult
FIELDS TERMINATED BY ', ' ENCLOSED BY '"'
LINES TERMINATED BY '\n';
