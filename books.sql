-- 1. Расчёт MAU авторов
with t1 as (select main_author_id, extract('month' from msk_business_dt_str) as mnth, main_author_name, count(distinct puid) as mau
from bookmate.audition
join bookmate.content using(main_content_id)
join bookmate.author using(main_author_id) 
group by 1, 2, 3)
select main_author_name, sum(mau) as mau
from t1
where mnth = 11
group by main_author_name
order by mau desc
limit 3

-- 2. Расчёт MAU произведений
with metric as (select main_content_id, main_content_name, extract('month' from msk_business_dt_str) as mnth, published_topic_title_list, main_author_name, count(distinct puid) as mau
from bookmate.audition
join bookmate.content using(main_content_id)
join bookmate.author using(main_author_id)
where extract('month' from msk_business_dt_str) = 11
group by 1, 2, 3, 4, 5
order by 6 desc
limit 3)
select main_content_name, published_topic_title_list, main_author_name, mau
from metric

-- 3. Расчёт Retention Rate
WITH cohort AS (
    -- Шаг 1: Выделяем уникальных пользователей, которые были активны 2 декабря
    SELECT DISTINCT puid
    FROM bookmate.audition
    WHERE msk_business_dt_str = '2024-12-02'
),
daily_activity AS (
    -- Шаг 2: Считаем активность этих пользователей в последующие дни
    SELECT 
        CAST(a.msk_business_dt_str AS DATE) - CAST('2024-12-02' AS DATE) AS day_since_install,
        COUNT(DISTINCT a.puid) AS retained_users
    FROM bookmate.audition AS a
    INNER JOIN cohort AS c ON a.puid = c.puid
    WHERE CAST(a.msk_business_dt_str AS DATE) >= CAST('2024-12-02' AS DATE)
    GROUP BY 1
)
    -- Шаг 3: Рассчитываем Retention Rate с использованием оконной функции MAX
SELECT 
    day_since_install,
    retained_users,
    ROUND(retained_users::numeric / MAX(retained_users) OVER (), 2) AS retention_rate
FROM daily_activity
ORDER BY day_since_install ASC;

--4. Расчет LTV
WITH user_monthly_activity AS (
    SELECT 
        a.puid,
        g.usage_geo_id_name AS city,
        EXTRACT(MONTH FROM CAST(a.msk_business_dt_str AS DATE)) AS activity_month
    FROM bookmate.audition AS a
    JOIN bookmate.geo AS g ON a.usage_geo_id = g.usage_geo_id
    WHERE g.usage_geo_id_name IN ('Москва', 'Санкт-Петербург')
    GROUP BY 1, 2, 3
),
user_ltv AS (
    SELECT 
        puid,
        city,
        COUNT(activity_month) * 399 AS total_user_revenue
    FROM user_monthly_activity
    GROUP BY 1, 2
)
SELECT 
    city,
    COUNT(puid) AS total_users,
    ROUND(SUM(total_user_revenue)::numeric / COUNT(puid), 2) AS ltv
FROM user_ltv
GROUP BY city;

-- 5. Расчёт средней выручки прослушанного часа — аналог среднего чека
SELECT 
    DATE_TRUNC('month', CAST(msk_business_dt_str AS DATE))::date AS month,
    COUNT(DISTINCT puid) AS mau,
    ROUND(SUM(hours)::numeric, 2) AS hours,
    ROUND((COUNT(DISTINCT puid) * 399) / SUM(hours)::numeric, 2) AS avg_hour_rev
FROM bookmate.audition
WHERE CAST(msk_business_dt_str AS DATE) < '2024-12-01'
GROUP BY 1
ORDER BY 1;