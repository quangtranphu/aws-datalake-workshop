

CREATE EXTERNAL TABLE IF NOT EXISTS gdelt.events (
        `globaleventid` INT,
        `day` INT,
        `monthyear` INT,
        `year` INT,
        `fractiondate` FLOAT,
        `actor1code` string,
        `actor1name` string,
        `actor1countrycode` string,
        `actor1knowngroupcode` string,
        `actor1ethniccode` string,
        `actor1religion1code` string,
        `actor1religion2code` string,
        `actor1type1code` string,
        `actor1type2code` string,
        `actor1type3code` string,
        `actor2code` string,
        `actor2name` string,
        `actor2countrycode` string,
        `actor2knowngroupcode` string,
        `actor2ethniccode` string,
        `actor2religion1code` string,
        `actor2religion2code` string,
        `actor2type1code` string,
        `actor2type2code` string,
        `actor2type3code` string,
        `isrootevent` BOOLEAN,
        `eventcode` string,
        `eventbasecode` string,
        `eventrootcode` string,
        `quadclass` INT,
        `goldsteinscale` FLOAT,
        `nummentions` INT,
        `numsources` INT,
        `numarticles` INT,
        `avgtone` FLOAT,
        `actor1geo_type` INT,
        `actor1geo_fullname` string,
        `actor1geo_countrycode` string,
        `actor1geo_adm1code` string,
        `actor1geo_lat` FLOAT,
        `actor1geo_long` FLOAT,
        `actor1geo_featureid` INT,
        `actor2geo_type` INT,
        `actor2geo_fullname` string,
        `actor2geo_countrycode` string,
        `actor2geo_adm1code` string,
        `actor2geo_lat` FLOAT,
        `actor2geo_long` FLOAT,
        `actor2geo_featureid` INT,
        `actiongeo_type` INT,
        `actiongeo_fullname` string,
        `actiongeo_countrycode` string,
        `actiongeo_adm1code` string,
        `actiongeo_lat` FLOAT,
        `actiongeo_long` FLOAT,
        `actiongeo_featureid` INT,
        `dateadded` INT,
        `sourceurl` string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe'
WITH SERDEPROPERTIES ( 'serialization.format' = '\t',
            'field.delim' = '\t')
LOCATION 's3://gdelt-open-data/events/';

CREATE EXTERNAL TABLE IF NOT EXISTS gdelt.eventcodes (
    `code` string,
    `description` string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe'
WITH SERDEPROPERTIES (
    'serialization.format' = '\t','field.delim' = '\t')
LOCATION 's3://sdl-immersion-day-220334428465/eventcodes/'
TBLPROPERTIES ( "skip.header.line.count"="1");


-- Show top 10 event categories

WITH cte as (
    SELECT eventcode,
                COUNT(globaleventid) AS nb_events
        FROM gdelt.events
        GROUP BY eventcode
        ORDER BY nb_events DESC LIMIT 10
)
SELECT cte.eventcode,
        gdelt.eventcodes.description,
        cte.nb_events
    FROM cte
    LEFT JOIN gdelt.eventcodes 
    ON cte.eventcode = gdelt.eventcodes.code
ORDER BY cte.nb_events DESC;


-- Count Obama events per year
SELECT year,
        COUNT(globaleventid) AS nb_events
    FROM gdelt.events
    WHERE actor1name='BARACK OBAMA'
    GROUP BY year
ORDER BY year ASC;

-- Count Obama/Merkel events per category:

WITH cte as (
    SELECT eventcode,
            COUNT(globaleventid) AS nb_events
    FROM gdelt.events
    WHERE actor1name='BARACK OBAMA'and actor2name='ANGELA MERKEL'
    GROUP BY eventcode
    ORDER BY nb_events DESC
)
SELECT cte.eventcode,
    gdelt.eventcodes.description,
    cte.nb_events
FROM cte
LEFT JOIN gdelt.eventcodes 
ON cte.eventcode = gdelt.eventcodes.code
WHERE cte.nb_events >= 20
ORDER BY cte.nb_events DESC;