-- 1. Получение общих данных
select currency_code, sum(revenue) as total_revenue, count(order_id) as total_orders, avg(revenue) as avg_revenue_per_order, count(distinct user_id) as total_users
from afisha.purchases
group by currency_code
order by total_revenue desc

--2. Изучение распределения выручки в разрезе устройств
select device_type_canonical, sum(revenue) as total_revenue, count(order_id) as total_orders, avg(revenue) as avg_revenue_per_order, 
round(sum(revenue)::numeric /
(select sum(revenue) from afisha.purchases where currency_code = 'rub')::numeric, 3) as revenue_share
from afisha.purchases
where currency_code = 'rub'
group by device_type_canonical
order by revenue_share desc

-- 3. Изучение распределения выручки в разрезе типа мероприятий
select event_type_main, sum(revenue) as total_revenue, count(order_id) as total_orders, avg(revenue) as avg_revenue_per_order, count (distinct event_name_code) as total_event_name, avg(tickets_count) as avg_tickets, sum(revenue) / sum(tickets_count) as avg_ticket_revenue,
round((sum(revenue) / (select sum(revenue) from afisha.purchases where currency_code = 'rub'))::numeric, 3) as revenue_share
from afisha.purchases
join afisha.events using(event_id)
where currency_code = 'rub'
group by event_type_main
order by total_orders desc

-- 4. Динамика изменения значений
select DATE_TRUNC('week', created_dt_msk)::date as week, sum(revenue) as total_revenue, count(order_id) as total_orders, count(distinct user_id) as total_users, sum(revenue) / count(order_id) as revenue_per_order
from afisha.purchases
where currency_code = 'rub'
group by week
order by week 

--5. Выделение топ-сегментов
select region_name, sum(revenue) as total_revenue, count(order_id) as total_orders, count(distinct user_id) as total_users, sum(tickets_count) as total_tickets, sum(revenue) / sum(tickets_count) as one_ticket_cost
from afisha.purchases
join afisha.events using(event_id)
join afisha.city using(city_id)
join afisha.regions using(region_id)
where currency_code = 'rub'
group by region_name
order by total_revenue desc
limit 7

