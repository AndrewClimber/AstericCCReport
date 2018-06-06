call `collect_phones`(
        '2018-04-24 00:00:00',
        '2018-04-26 00:30:00',
     );

call `report_building`(
        '2018-04-24 00:00:00',
        '2018-04-26 00:30:00',
        3,
        180,
        1800
    );
        
select * from `qstat_report` where avg_speed_answer is not null;

delete from `qstat_report`;



CREATE TABLE `save_phones` (
  `uid` INTEGER(11) DEFAULT NULL,
  `dt` DATETIME DEFAULT NULL,
  `i2` VARCHAR(40) DEFAULT NULL
) ENGINE=HEAP
ROW_FORMAT=FIXED;