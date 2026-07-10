
SELECT
    COUNT(*)                                        AS total_bookings,
    SUM(amount)                                     AS total_revenue,
    SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active_rides,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_rides,
    SUM(CASE WHEN status = 'overdue' THEN 1 ELSE 0 END)   AS overdue_rides,
    ROUND(AVG(amount), 2)                           AS avg_booking_value
FROM bookings;


WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(booking_date, '%Y-%m')  AS revenue_month,
        SUM(amount)                         AS monthly_total
    FROM bookings
    WHERE status != 'cancelled'
    GROUP BY DATE_FORMAT(booking_date, '%Y-%m')
    ORDER BY revenue_month
)
SELECT
    revenue_month,
    monthly_total,
    LAG(monthly_total) OVER (ORDER BY revenue_month) AS prev_month_revenue,
    ROUND(
        (monthly_total - LAG(monthly_total) OVER (ORDER BY revenue_month))
        / LAG(monthly_total) OVER (ORDER BY revenue_month) * 100,
        2
    ) AS growth_pct
FROM monthly_revenue;


SELECT
    v.model,
    COUNT(b.booking_id)     AS total_bookings,
    SUM(b.amount)           AS total_revenue,
    ROUND(AVG(b.amount), 2) AS avg_booking_value
FROM bookings b
JOIN vehicles v ON b.vehicle_id = v.vehicle_id
WHERE b.status != 'cancelled'
GROUP BY v.model
ORDER BY total_bookings DESC
LIMIT 5;


SELECT
    sa.agent_id,
    CONCAT(sa.first_name, ' ', sa.last_name)    AS agent_name,
    h.hub_name,
    h.city,
    COUNT(DISTINCT c.customer_id)                AS customers_referred,
    COUNT(DISTINCT b.booking_id)                 AS bookings_generated,
    COALESCE(SUM(b.amount), 0)                   AS total_revenue_attributed,
    ROUND(
        COALESCE(SUM(b.amount), 0)
        / NULLIF(COUNT(DISTINCT c.customer_id), 0), 2
    )                                            AS revenue_per_customer
FROM sales_agents sa
JOIN hubs h ON sa.hub_id = h.hub_id
LEFT JOIN customers c ON sa.agent_id = c.referral_agent_id
LEFT JOIN bookings b  ON c.customer_id = b.customer_id AND b.status != 'cancelled'
GROUP BY sa.agent_id, sa.first_name, sa.last_name, h.hub_name, h.city
ORDER BY total_revenue_attributed DESC;


SELECT
    DATE_FORMAT(booking_date, '%Y-%m')  AS booking_month,
    package,
    COUNT(*)                            AS booking_count,
    SUM(amount)                         AS monthly_revenue,
    ROUND(AVG(amount), 2)               AS avg_amount
FROM bookings
WHERE status != 'cancelled'
GROUP BY DATE_FORMAT(booking_date, '%Y-%m'), package
ORDER BY booking_month, booking_count DESC;

--

WITH hub_demand AS (
    -- Aggregate booking metrics per hub
    SELECT
        h.hub_id,
        h.hub_name,
        h.city,
        h.capacity,
        COUNT(b.booking_id)                     AS total_bookings,
        COALESCE(SUM(b.amount), 0)              AS total_revenue,
        COUNT(DISTINCT b.customer_id)           AS unique_customers
    FROM hubs h
    LEFT JOIN bookings b ON h.hub_id = b.hub_id AND b.status != 'cancelled'
    GROUP BY h.hub_id, h.hub_name, h.city, h.capacity
)
SELECT
    h1.hub_name                                     AS hub_a,
    h2.hub_name                                     AS hub_b,
    h1.city,
    h1.total_bookings                               AS hub_a_bookings,
    h2.total_bookings                               AS hub_b_bookings,
    ABS(h1.total_bookings - h2.total_bookings)      AS booking_gap,
    ROUND(
        ABS(h1.total_bookings - h2.total_bookings)
        / NULLIF(GREATEST(h1.total_bookings, h2.total_bookings), 0) * 100, 2
    )                                                AS gap_pct,
    h1.total_revenue                                AS hub_a_revenue,
    h2.total_revenue                                AS hub_b_revenue,
    CASE
        WHEN h1.total_bookings > h2.total_bookings THEN CONCAT(h1.hub_name, ' has higher demand')
        WHEN h1.total_bookings < h2.total_bookings THEN CONCAT(h2.hub_name, ' has higher demand')
        ELSE 'Equal demand'
    END                                              AS demand_analysis
FROM hub_demand h1
JOIN hub_demand h2
    ON h1.city = h2.city                            -- Same city comparison only
    AND h1.hub_id < h2.hub_id                       -- Avoid duplicate pairs (A-B and B-A)
ORDER BY gap_pct DESC;
