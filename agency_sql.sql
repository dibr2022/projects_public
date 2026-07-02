/* Aнализ данных для агентства недвижимости
*/


-- Задача 1: Время активности объявлений

WITH 
limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
 ),
-- Относим к регионам и категориям и по ним группируем. Фильтруем данные по выбросам, городам, дате, считаем статистические параметры
 group_table AS (
 SELECT
	CASE
		WHEN city = 'Санкт-Петербург' THEN 'Санкт-Петербург'    -- регионы
		ELSE 'Ленинградская обл'
	END AS region,
	CASE
		WHEN days_exposition <= 30 THEN '1-30 days'     --категории по срокам
		WHEN days_exposition <= 90 THEN '31-90 days'
		WHEN days_exposition <= 180 THEN '91-180 days'
		WHEN days_exposition > 180 THEN '181+ days'
		ELSE 'non category'
	END AS category,
	COUNT(DISTINCT id) AS num_ads,
	ROUND(AVG(last_price / total_area)) AS avg_price,
	ROUND(AVG(total_area)::NUMERIC, 1) AS avg_area,
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS median_num_rooms,
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS median_num_balc,
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floor) AS median_num_floors
FROM real_estate.advertisement
JOIN real_estate.flats USING(id)
JOIN real_estate.city USING(city_id)
JOIN real_estate."type" USING(type_id)
WHERE
	first_day_exposition >= '2015-01-01'    --  используйте только объявления о продаже недвижимости в городах за 2015–2018 годы включительно
	AND first_day_exposition < '2019-01-01'
	AND id IN (SELECT * FROM filtered_id)  -- фильтрация
	AND TYPE = 'город'   -- только города
GROUP BY region, category
)

SELECT
	region, -- регионы
	category, -- категории
	num_ads, -- количество объявлений
	SUM(num_ads) OVER (PARTITION BY region) AS total_region_ads, -- всего объявлений по регионам
	ROUND(num_ads * 100.0 / SUM(num_ads) OVER (PARTITION BY region), 2) AS perc_num_ads, -- проценты объявлений в разрезе категории
	avg_price,  -- средняя цена метра по категориям
	AVG(avg_price) OVER (PARTITION BY region) AS avg_regional_price, -- средняя стоимость метра по регионам
	avg_area, -- средний метраж
	median_num_rooms, -- медиана комнат
	median_num_balc, -- медиана числа балконов
	median_num_floors -- медиана этажа
FROM group_table
ORDER BY region DESC, num_ads DESC;



-- Задача 2: Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:


WITH 
limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
 --  Найдем месяцы публикации и снятия объявления:
month_table AS (
	SELECT
		*,
		first_day_exposition,
		EXTRACT (MONTH FROM first_day_exposition) AS beg_month,
		first_day_exposition::DATE + days_exposition::INTEGER AS end_date,
		EXTRACT (MONTH FROM first_day_exposition::DATE + days_exposition::INTEGER) AS end_month
	FROM real_estate.advertisement
	JOIN real_estate.flats USING(id)
	JOIN real_estate.city USING(city_id)
	JOIN real_estate.type USING(type_id)
	WHERE
		first_day_exposition >= '2015-01-01'  -- рассматриваем только целые года 2015 - 2018
		AND first_day_exposition < '2019-01-01'
		AND id IN (SELECT * FROM filtered_id)
		AND TYPE = 'город' -- только города
),
-- Считаем статистику по месяцу выставления объявления на продажу
beg_table AS (
	SELECT
		beg_month,
		COUNT(DISTINCT id) AS num_ads,
		ROUND(AVG(last_price / total_area)) AS avg_price,
		ROUND(AVG(total_area)::NUMERIC, 1) AS avg_area
	FROM month_table
	GROUP BY 1
),
-- Считаем статистику по месяцу снятия объявления с продажи
end_table AS (
	SELECT
		end_month,
		COUNT(DISTINCT id) AS num_ads,
		ROUND(AVG(last_price / total_area)) AS avg_price,
		ROUND(AVG(total_area)::NUMERIC, 1) AS avg_area
	FROM month_table
	WHERE end_month IS NOT NULL
	AND end_date < '2019-01-01' -- чтобы не возникал 2019 год дат снятия
	GROUP BY 1
)
-- Сводим в одну таблицу
SELECT
	b.beg_month, -- месяц
	b.num_ads AS ad_pub, -- количество публикаций
	ROUND(b.num_ads / sum(b.num_ads) OVER () ,3)AS pub_perc,
	ROW_NUMBER() OVER(ORDER BY b.num_ads desc) pub_rank, -- ранжирование по кол-ву публикаций
	e.num_ads AS ad_remove, -- количество снятий объявлений
	ROUND(e.num_ads / sum(e.num_ads) OVER () ,3)AS rem_perc,
	ROW_NUMBER() OVER(ORDER BY e.num_ads desc) rem_rank, -- ранжирование по кол-ву публикаций
	b.avg_price AS pub_avg_price, -- средняя стоимость при публикации
	e.avg_price AS rem_avg_price, -- средняя стоимость при снятии
	b.avg_area AS pub_avg_area, -- средняя площадь при публикации
	e.avg_area AS rem_avg_area -- средняя площадь при снятии
FROM beg_table b
JOIN end_table e ON b.beg_month = e.end_month
ORDER BY 1, 2 DESC;


