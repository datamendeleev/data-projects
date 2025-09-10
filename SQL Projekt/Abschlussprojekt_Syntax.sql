CREATE DATABASE IF NOT EXISTS credit_project;
USE credit_project;

DROP TABLE IF EXISTS credit_risk;
CREATE TABLE credit_risk (
  person_age                     INT,
  person_income                  INT,
  person_home_ownership          VARCHAR(20),
  person_emp_length              DECIMAL(7,2),               
  loan_intent                    VARCHAR(30),
  loan_grade                     CHAR(1),                    
  loan_amnt                      INT,
  loan_int_rate                  DECIMAL(6,3),               
  loan_status                    TINYINT,                    
  loan_percent_income            DECIMAL(7,4),                
  cb_person_default_on_file      CHAR(1),                     
  cb_person_cred_hist_length     INT
);


-- Die CSV habe ich so geladen da der Table data import wizard bei mir nicht funktioniert hatte, hat aber auch so wunderbar funktioniert!
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 9.3/Uploads/credit_risk_dataset.csv'
INTO TABLE credit_risk
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(person_age,
 person_income,
 person_home_ownership,
 @person_emp_length,
 loan_intent,
 loan_grade,
 loan_amnt,
 @loan_int_rate,
 loan_status,
 loan_percent_income,
 cb_person_default_on_file,
 cb_person_cred_hist_length)
SET person_emp_length = NULLIF(@person_emp_length, ''),
    loan_int_rate     = NULLIF(@loan_int_rate, '');

-- Kreditüberwachung:

-- Überprüfung der CSV
SELECT COUNT(*) FROM credit_risk;

SELECT * FROM credit_risk LIMIT 10;

SELECT 
  SUM(person_emp_length IS NULL) AS missing_emp_length,
  SUM(loan_int_rate IS NULL)     AS missing_int_rate
FROM credit_risk;


-- View der Risikoklassen für einfacheres Einfügen im weiteren Verlauf
CREATE OR REPLACE VIEW risiko_klassen AS
SELECT
  r.loan_status,
  r.loan_int_rate,
  r.loan_amnt,
  r.person_age,
  r.person_income,
  r.person_emp_length,
  r.person_home_ownership,
  r.loan_percent_income,
  r.loan_grade, 
  r.risk_points,
  CASE
    WHEN r.risk_points <= 8 THEN 'Sehr niedrig'
    WHEN r.risk_points BETWEEN 9 AND 12 THEN 'Niedrig'
    WHEN r.risk_points BETWEEN 13 AND 16 THEN 'Mittel'
    WHEN r.risk_points BETWEEN 17 AND 20 THEN 'Hoch'
    ELSE 'Sehr hoch'
  END AS risikoklasse
FROM (
  SELECT
    loan_status,
    loan_int_rate,
    loan_amnt,
    person_age,
    person_income,
    person_emp_length,
    person_home_ownership,
    loan_percent_income,
    loan_grade,
    (
      CASE loan_grade
        WHEN 'A' THEN 1 WHEN 'B' THEN 2 WHEN 'C' THEN 3
        WHEN 'D' THEN 4 WHEN 'E' THEN 5 WHEN 'F' THEN 6
        WHEN 'G' THEN 7 END
      +
      CASE
        WHEN person_income < 20000 THEN 5
        WHEN person_income BETWEEN 20000 AND 40000 THEN 4
        WHEN person_income BETWEEN 40001 AND 60000 THEN 3
        WHEN person_income BETWEEN 60001 AND 100000 THEN 2
        ELSE 1 END
      +
      CASE
        WHEN loan_amnt < 5000 THEN 1
        WHEN loan_amnt BETWEEN 5000 AND 10000 THEN 2
        WHEN loan_amnt BETWEEN 10001 AND 20000 THEN 3
        WHEN loan_amnt BETWEEN 20001 AND 30000 THEN 4
        ELSE 5 END
      +
      CASE
        WHEN loan_percent_income < 0.2 THEN 1
        WHEN loan_percent_income BETWEEN 0.2 AND 0.3 THEN 2
        WHEN loan_percent_income BETWEEN 0.31 AND 0.4 THEN 3
        WHEN loan_percent_income BETWEEN 0.41 AND 0.5 THEN 4
        ELSE 5 END
	  +
	  CASE
        WHEN person_emp_length IS NULL THEN 3
        WHEN person_emp_length < 1 THEN 5
        WHEN person_emp_length BETWEEN 1 AND 3 THEN 4
        WHEN person_emp_length BETWEEN 4 AND 6 THEN 3
        WHEN person_emp_length BETWEEN 7 AND 10 THEN 2
        ELSE 1 END
	  +
	  CASE person_home_ownership
        WHEN 'OWN' THEN 1
        WHEN 'MORTGAGE' THEN 2
        WHEN 'RENT' THEN 4
        ELSE 3 END
    ) AS risk_points
  FROM credit_risk
) AS r;

-- Abfrage der Risikogruppen
SELECT risikoklasse, COUNT(*) AS anzahl, ROUND(AVG(loan_status),3) AS ausfallquote
FROM risiko_klassen
GROUP BY risikoklasse
ORDER BY FIELD(risikoklasse,'Sehr niedrig','Niedrig','Mittel','Hoch','Sehr hoch');

-- Kundenabfrage der bestimmten Risikogruppen
SELECT 
    person_age,
    person_income,
    loan_amnt,
    loan_int_rate,
    loan_percent_income,
    risikoklasse
FROM risiko_klassen
WHERE risikoklasse = 'Sehr hoch'
LIMIT 20;

-- Durchschnittswerte für die Risikoklassen
SELECT 
  risikoklasse,
  COUNT(*)                                   AS anzahl,
  ROUND(AVG(loan_status),3)                  AS ausfallquote,
  ROUND(AVG(person_income),0)                AS avg_einkommen,
  ROUND(AVG(loan_amnt),0)                    AS avg_kreditbetrag,
  ROUND(AVG(loan_percent_income),3)          AS avg_kredit_zu_einkommen,
  ROUND(AVG(loan_int_rate),2)                AS avg_zins
FROM risiko_klassen
GROUP BY risikoklasse
ORDER BY FIELD(risikoklasse,'Sehr niedrig','Niedrig','Mittel','Hoch','Sehr hoch');

-- Lift-Tabelle
WITH deciles AS (
  SELECT
    NTILE(10) OVER (ORDER BY risk_points DESC) AS decile,  -- 1 = höchste Risiken
    loan_status
  FROM risiko_klassen
)
SELECT
  decile,
  COUNT(*) AS n_kredite,
  SUM(loan_status) AS anzahl_ausfaelle,
  ROUND(AVG(loan_status),3) AS ausfallquote,
  ROUND(SUM(SUM(loan_status)) OVER (ORDER BY decile)
        / SUM(SUM(loan_status)) OVER (),3) AS kumulierte_ausfaelle
FROM deciles
GROUP BY decile
ORDER BY decile;


-- Kreditvergabe & Pricing

-- Pearson Korrelation

-- Risiko <-> Loan Status
SELECT
  (
    AVG(loan_int_rate * risk_points) - AVG(loan_int_rate) * AVG(risk_points)
  ) /
  SQRT(
    (AVG(loan_int_rate * loan_int_rate) - POW(AVG(loan_int_rate),2)) *
    (AVG(risk_points * risk_points) - POW(AVG(risk_points),2))
  ) AS Korrelation_Risiko_Zins
FROM risiko_klassen
WHERE loan_int_rate IS NOT NULL;



-- Red-Flag-Beispiele

(
-- 1) Hoch-/Sehr-hohes Risiko, aber ungewöhnlich niedriger Zins
  SELECT 
    'HighRisk_LowRate' AS flag,
    risikoklasse, risk_points, loan_grade,
    person_income, loan_amnt, loan_int_rate, loan_percent_income, loan_status
  FROM risiko_klassen
  WHERE risikoklasse IN ('Hoch','Sehr hoch')
    AND loan_int_rate IS NOT NULL
  ORDER BY loan_int_rate ASC, risk_points DESC
  LIMIT 1
)
UNION ALL
(
-- Hoch-/Sehr-hohes Risiko mit sehr großem Kreditbetrag
  SELECT 
    'HighRisk_HighAmount' AS flag,
    risikoklasse, risk_points, loan_grade,
    person_income, loan_amnt, loan_int_rate, loan_percent_income, loan_status
  FROM risiko_klassen
  WHERE risikoklasse IN ('Hoch','Sehr hoch')
  ORDER BY loan_amnt DESC, risk_points DESC
  LIMIT 1
)
UNION ALL
(
-- Sehr niedriges Risiko, aber ungewöhnlich hoher Zins
  SELECT 
    'LowRisk_HighRate' AS flag,
    risikoklasse, risk_points, loan_grade,
    person_income, loan_amnt, loan_int_rate, loan_percent_income, loan_status
  FROM risiko_klassen
  WHERE risikoklasse = 'Sehr niedrig'
    AND loan_int_rate IS NOT NULL
  ORDER BY loan_int_rate DESC, risk_points ASC
  LIMIT 1
)
;

-- Workload-Planner

SELECT
  risikoklasse,
  COUNT(*) AS n_kredite,
  CASE risikoklasse
    WHEN 'Sehr niedrig' THEN 0.5
    WHEN 'Niedrig'      THEN 1
    WHEN 'Mittel'       THEN 1
    WHEN 'Hoch'         THEN 2
    ELSE                    3 
  END AS checks_pro_jahr,
  COUNT(*) *
  CASE risikoklasse
    WHEN 'Sehr niedrig' THEN 0.5
    WHEN 'Niedrig'      THEN 1
    WHEN 'Mittel'       THEN 1
    WHEN 'Hoch'         THEN 2
    ELSE                    3
  END AS total_checks
FROM risiko_klassen
GROUP BY risikoklasse
ORDER BY FIELD(risikoklasse,'Sehr niedrig','Niedrig','Mittel','Hoch','Sehr hoch');
