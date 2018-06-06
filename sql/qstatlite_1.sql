-- phpMyAdmin SQL Dump
-- version 4.0.10.10
-- http://www.phpmyadmin.net
--
-- Хост: 127.0.0.1:3306
-- Время создания: Май 30 2018 г., 12:24
-- Версия сервера: 5.5.45
-- Версия PHP: 5.3.29

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;

--
-- База данных: `qstatlite_1`
--

DELIMITER $$
--
-- Процедуры
--
CREATE DEFINER=`root`@`%` PROCEDURE `report_building`(
        IN `date1` DATETIME,
        IN `date2` DATETIME,
        IN queue_name INTEGER(11),
        IN `wait_level` INTEGER(5),
        IN `difftime` INTEGER(11)
    )
    MODIFIES SQL DATA
BEGIN
  
  declare slevel DOUBLE(10,5);
  declare lusers DOUBLE(10,5);
  declare avgspeed INT;
  declare availability INT;
  declare D1 DATETIME;
  declare D2 DATETIME;

  
  
  


  set D1 = date1;
  set D2 = DATE_ADD(D1,INTERVAL difftime SECOND);
  

 while D2 < date2 do
     select `service_level`(D1,D2,`queue_name`,wait_level) into slevel;
     select avg_answer_time(D1,D2,`queue_name`) into avgspeed;
     select lost_users(D1,D2,`queue_name`) into lusers;

     if  (slevel >= 80 and avgspeed <= 5*60 and lusers <= 5 ) then
        set availability = 1;    
     else 
        set availability = 0;
     end if;

     insert into `qstat_report` 
     values(D2, `queue_name`, slevel, 
            SEC_TO_TIME(avgspeed),
            lusers,availability, D1, D2 );
     
     set D1 = DATE_ADD(D2,INTERVAL 1 SECOND);
     set D2 = DATE_ADD(D2,INTERVAL difftime SECOND);
     
     
  end while;   
  commit;
END$$

--
-- Функции
--
CREATE DEFINER=`root`@`%` FUNCTION `avg_answer_time`(
        `date1` DATETIME,
        `date2` DATETIME,
        queue_name INTEGER(11)
    ) RETURNS int(11)
BEGIN
   DECLARE result INT;
   
  select 
    AVG(`qs`.info1) into result
  from queue_stats qs
  where 
     qs.`qevent` in (7,8) and # COMPLETEAGENT,COMPLETECALLER
     qs.`qname` = queue_name and
     qs.`datetime` between date1 and date2                          
  order by qs.uniqueid,qs.datetime;

  RETURN result;
END$$

CREATE DEFINER=`root`@`%` FUNCTION `lost_users`(
        `date1` DATETIME,
        `date2` DATETIME,
        queue_name INTEGER(11)
    ) RETURNS double
BEGIN
   DECLARE result DOUBLE(10,2);
  
  select 
    IFNULL((lost.c*100)/(lost.c+unlost.u),0) into result
  from
   ( select count(*) c
     from queue_stats qs
     where 
       qs.`qevent` = 1 and # ABANDON
       qs.`qname` = queue_name and  
       qs.`datetime` between date1 and date2
     order by qs.uniqueid, qs.datetime
    ) lost,
    ( select count(*) u
      from queue_stats qs
      where 
        qs.`qevent` in (7,8) and #'COMPLETEAGENT','COMPLETECALLER'
        qs.`qname` = queue_name and
        qs.`datetime` between date1 and date2
      order by qs.uniqueid, qs.datetime
    ) unlost;
  
  RETURN result;
  
END$$

CREATE DEFINER=`root`@`%` FUNCTION `service_level`(
        `date1` DATETIME,
        `date2` DATETIME,
        queue_name INTEGER(11),
        `wait_level` INTEGER(5)
    ) RETURNS double(10,5)
BEGIN
   DECLARE result DOUBLE(10,2);
   
  select
    IFNULL((comp.complet*100)/(comp.complet+uncomp.uncomplet),0) INTO result
  from
  ( select 
      count(*) complet
    from queue_stats qs
    where  
      qs.`qevent` in (7,8) and #'COMPLETEAGENT','COMPLETECALLER'
      qs.`qname` = queue_name and
      qs.info1 <= wait_level and 
      qs.`datetime` between date1 and date2
     order by qs.uniqueid, qs.datetime
   ) comp,
   ( select 
       count(*) uncomplet
     from queue_stats qs
     where 
       qs.`qevent` in (7,8) and #'COMPLETEAGENT','COMPLETECALLER'
       qs.`qname` = queue_name and
       qs.info1 >= wait_level and
       qs.`datetime` between date1 and date2                          
     order by qs.uniqueid, qs.datetime
   ) uncomp;

  RETURN result;
  
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Структура таблицы `qstat_report`
--

CREATE TABLE IF NOT EXISTS `qstat_report` (
  `interval` datetime NOT NULL COMMENT 'Интервал среза',
  `qname` int(6) NOT NULL COMMENT 'название очереди',
  `service_level` double(10,5) DEFAULT NULL COMMENT 'Уровень обслуживания - это процент вызовов получивших обслуживание в пределах нормы ожидания - 180 сек.',
  `avg_speed_answer` varchar(40) DEFAULT NULL COMMENT 'Средняя скорость ответа -это среднее время ожидания абонентов ответа с момента поступления вызова до поднятия \r\nтрубки операторами.',
  `lost_users` double(15,3) DEFAULT NULL COMMENT 'Доля потерянных абонентов - это количество потерянных абонентов(которые не дождались ответа и им не перезвонили) \r\nк количеству абонентов, направленных на обслуживание к операторам. Норма <= 5%',
  `availab` int(11) DEFAULT NULL COMMENT 'Доступность - рассчитывается за каждый оцененный интервал (1 рабочий день)исходя из показателей \r\nуровень обслуживания, средняя скорость ответа, доля потерянных абонентов.',
  `d1` datetime DEFAULT NULL,
  `d2` datetime DEFAULT NULL,
  UNIQUE KEY `inter_qn_uniq` (`interval`,`qname`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
