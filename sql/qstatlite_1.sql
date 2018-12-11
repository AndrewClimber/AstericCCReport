-- phpMyAdmin SQL Dump
-- version 4.0.10.10
-- http://www.phpmyadmin.net
--
-- Хост: 127.0.0.1:3306
-- Время создания: Июл 18 2018 г., 07:12
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
CREATE DEFINER=`root`@`%` PROCEDURE `collect_phones`(
        IN date1 DATETIME,
        IN date2 DATETIME
    )
BEGIN
   DECLARE s_uid VARCHAR(40);
   DECLARE s_dt DATETIME;
   DECLARE s_i2 VARCHAR(40);
   
   DECLARE uid VARCHAR(40);
   DECLARE dt DATETIME;
   DECLARE qe INT;
   DECLARE i2 VARCHAR(40);
   
   DECLARE done INT DEFAULT FALSE;
           
   DECLARE Cphones CURSOR FOR
   select 
      qs.uniqueid, qs.`datetime`,qs.`qevent`,qs.`info2` 
   from   `queue_stats` as qs 
   where 
      qs.`qevent` in ( 7,8, 11, 1) and #('ABANDON','ENTERQUEUE')
      qs.`info2`!=22 and
      qs.`qname` in (3,6) and
      qs.`datetime` between date1 and date2
   order by qs.uniqueid, qs.`DATETIME`;
   DECLARE CONTINUE HANDLER 
      FOR NOT FOUND SET done = TRUE;
   
   delete from save_phones;
   
   OPEN Cphones;
   read_data: LOOP
      FETCH Cphones INTO uid,dt,qe,i2;
      IF qe = 11 THEN
         SET s_uid = uid;
         SET s_dt = dt;
         SET s_i2 = i2;
      END IF; 
      IF qe in (7,8) AND s_uid = uid THEN
         insert into save_phones 
           values(s_uid, s_dt, s_i2);   
      END IF;
      IF done THEN
         LEAVE read_data;
      END IF;      
   END LOOP;   
         

END$$

CREATE DEFINER=`root`@`%` PROCEDURE `report_building`(
        IN `date1`      DATETIME,
        IN `date2`      DATETIME,
        IN queue_name   INTEGER(11),
        IN `wait_level` INTEGER(5),
        IN `difftime`   INTEGER(11)
    )
    MODIFIES SQL DATA
BEGIN
/* ***************************************************************************************
 * Процедура построения отчета.
 * Использует пять функций : 
 * service_level   -  Уровень обслуживания - это процент вызовов получивших обслуживание 
 *                    в пределах нормы ожидания - wait_level.
 * avg_answer_time -  Средняя скорость ответа -это среднее время ожидания абонентов ответа 
 *                    с момента поступления вызова до поднятия трубки операторами.
 *
 * lost_users      -  Доля потерянных абонентов - это количество потерянных 
 *                    абонентов(которые не дождались ответа и им не перезвонили) 
 *                    к количеству абонентов, направленных на обслуживание к операторам.   
 *
 * uniq_success     - Кол-во успешных звонков
 * 
 * uniq_unsuccess   - Кол-во неуспешных звонков  
 *
 * Результаты работы процедуры заносятся в таблицу qstat_report      
 */
   
  -- Локальные переменные 
  -- Рассчитываются либо с помощью функций, 
  -- либо на основе других локальных переменных как ,например , availability 
  -- или unsuccess_proc
  DECLARE slevel DOUBLE(10,5); -- уровень обслуживания
  DECLARE lusers DOUBLE(10,5); -- потерянные абоненты
  DECLARE avgspeed INT;        -- средняя скорость ответа
  DECLARE availability INT;    -- Доступность. Рассчитывается за каждый оцененный интервал 
                               -- (1 рабочий день)исходя из показателей 
                               -- уровень обслуживания, средняя скорость ответа, 
                               -- доля потерянных  абонентов.
  -- переменные для расчета уникальных успешных и неуспешных звонков                             
  DECLARE unisuccess INT;              -- уникальное кол-во успешных               
  DECLARE uniunsuccess INT;            -- уникальное кол-во неуспешных  
  DECLARE unsuccess_proc DOUBLE(10,5); -- процент неуспешных
  -- две переменные для постороения интервалов в пределах параметров data1 и data2
  DECLARE D1 DATETIME;
  DECLARE D2 DATETIME;
  
  -- инициализация интервалов. intervals
  SET D1 = date1;
  SET D2 = DATE_ADD(D1,INTERVAL difftime SECOND);
  
 -- сбор данных пока интервал не превысит дату окончания построения отчета
 WHILE D2 < date2 DO
  -- получение данных с помощью функций
     select `service_level`(D1,D2,`queue_name`,wait_level) into slevel;
     select avg_answer_time(D1,D2,`queue_name`) into avgspeed;
     select lost_users(D1,D2,`queue_name`) into lusers;
  -- 99999 это заглушка   
     select `uniq_success`(D1,D2,`queue_name`,99999) into unisuccess;
     select `uniq_unsuccess`(D1,D2,`queue_name`,99999) into uniunsuccess;
  -- расчет availability на основе полученных данных
     IF  (slevel >= 80 and avgspeed <= 5*60 and lusers <= 5 ) THEN
        SET availability = 1;   -- все показатели попали в норму - 1 балл.
     ELSE 
        SET availability = 0;   -- не все показатели попали в норму - 0 баллов.
     END IF;
  -- расчет процента неуспешных звонков
     SET unsuccess_proc = IFNULL((100*uniunsuccess)/(unisuccess+uniunsuccess),0);
  -- занесение данных в итоговую таблицу
     insert into `qstat_report` 
     values(D2, `queue_name`, slevel, 
            SEC_TO_TIME(avgspeed),
            lusers,availability, unisuccess, unsuccess_proc, D1, D2 );
  -- инкремент начального и конечного времени интервалов   
     SET D1 = DATE_ADD(D2,INTERVAL 1 SECOND);
     SET D2 = DATE_ADD(D2,INTERVAL difftime SECOND);
     
     
  END WHILE;   
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
/* ***************************************************************************************
  Функция рассчета средней скорости ответа.
  Средняя скорость ответа -это среднее время ожидания абонентов ответа с момента 
  поступления вызова до поднятия трубки операторами.
  
  Вход :
  date1       Дата/время начала построения отчета
  date2       Дата/время окончания построения отчета 
  queue_name  Очередь для которой строится отчет

  Возвращает время в сек.
*/
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
/* ***************************************************************************************
Функция для рассчета доли потерянных пользователей.
Доля потерянных абонентов - это количество потерянных абонентов
(которые не дождались ответа и им не перезвонили) 
к количеству абонентов, направленных на обслуживание к операторам. Норма <= 5%
  
Вход :
  date1      Дата/время начала построения отчета
  date2      Дата/время окончания построения отчета 
  queue_name Очередь для которой строится отчет

Возвращает долю потерянных абонентов в процентах.
*/

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
        `date1`      DATETIME,
        `date2`      DATETIME,    
         queue_name   INTEGER(11), 
        `wait_level` INTEGER(5)   ) RETURNS tinyint(4)
BEGIN
  /* ***************************************************************************************
  Уровень обслуживания - это процент вызовов получивших обслуживание 
  в пределах нормы ожидания - wait_level. Обычно 180 сек.  Норма >= 80%
  
  Вход :
  date1        Дата/время начала построения отчета
  date2        Дата/время окончания построения отчета 
  queue_name   Очередь для которой строится отчет
  wait_level   Предел нормы ожидания

  Возвращает обслуженные вызовы в процентах.
  */
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

CREATE DEFINER=`root`@`%` FUNCTION `uniq`(
        date1 DATETIME,
        date2 DATETIME,
        queue_name INTEGER(11),
        eventype INTEGER(11)
    ) RETURNS tinyint(4)
BEGIN
   DECLARE result INTEGER;
   DECLARE D2 DATETIME;
   
# D2 = date2 - весь конец день чтобы рассчитать за день
#

   select count(*) from 
     (
       select distinct qs.`info2`
       from `queue_stats` as qs 
       where 
          qs.`qevent` = eventype and
          qs.`info2`!=22 and
          qs.qname = queue_name and
          qs.`datetime` between date1 and date2
     ) f INTO result;

  RETURN result;
END$$

CREATE DEFINER=`root`@`%` FUNCTION `uniq_success`(
        date1 DATETIME,
        date2 DATETIME,
        queue_name INTEGER(11),
        eventype INTEGER(11)
    ) RETURNS tinyint(4)
BEGIN
   DECLARE result INTEGER;
   DECLARE D2 DATETIME;
   
# D2 = date2 - весь конец день чтобы рассчитать за день
#
     
   select count(*) from
   (
    select  distinct intq.`info2`  from
    (
      select 
         qs.`uniqueid`, qs.`info2`, qs.`qevent`
      from   `queue_stats` as qs 
      where 
         qs.`qevent` = 11 and 
         qs.`qname` = queue_name and
         qs.`info2`!=22 and
         qs.`uniqueid` in (
            select  distinct qs.`uniqueid`
            from   `queue_stats` as qs 
            where 
               qs.`qevent` in (7,8) and 
               qs.`qname` = queue_name and
               qs.`info2`!=22 and
               qs.`datetime` between date1 and date2
         ) and      
         qs.`datetime` between date1 and date2
      ) intq
   ) outq INTO result;
      
     

  RETURN result;
END$$

CREATE DEFINER=`root`@`%` FUNCTION `uniq_unsuccess`(
        date1 DATETIME,
        date2 DATETIME,
        queue_name INTEGER(11),
        eventype INTEGER(11)
    ) RETURNS tinyint(4)
BEGIN
   DECLARE result INTEGER;
   DECLARE D2 DATETIME;
   
# D2 = date2 - весь конец день чтобы рассчитать за день
#
   select count(*) from
   (
     select  distinct intq.`info2`  from
    (
      select 
         qs.`uniqueid`, qs.`info2`, qs.`qevent`
      from   `queue_stats` as qs 
      where 
         qs.`qevent` = 11 and 
         qs.`qname` = queue_name and
         qs.`info2`!=22 and
         qs.`uniqueid` in (
            select  distinct qs.`uniqueid`
            from   `queue_stats` as qs 
            where 
               qs.`qevent` = 1 and 
               qs.`qname` = queue_name and
               qs.`info2`!=22 and
               qs.`datetime` between date1 and date2
         ) and      
         qs.`datetime` between date1 and date2
      ) intq
   ) outq INTO result;

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
  `uni_success` int(11) DEFAULT NULL,
  `uni_unsuccess` double(15,3) DEFAULT NULL,
  `d1` datetime DEFAULT NULL,
  `d2` datetime DEFAULT NULL,
  UNIQUE KEY `inter_qn_uniq` (`interval`,`qname`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- --------------------------------------------------------

--
-- Структура таблицы `save_phones`
--

CREATE TABLE IF NOT EXISTS `save_phones` (
  `uid` varchar(40) DEFAULT NULL,
  `dt` datetime DEFAULT NULL,
  `i2` varchar(40) DEFAULT NULL
) ENGINE=MEMORY DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
