-- ============================================================================
-- QUERY 1: Total Bookings, Revenue, and Active Rides Summary
-- ============================================================================
-- WHAT:      High-level dashboard KPIs — total bookings, total revenue,
--            and count of currently active rides.
-- CONCEPTS:  Aggregate functions (COUNT, SUM), CASE WHEN inside SUM for
--            conditional aggregation.
-- INSIGHT:   Gives the CEO a single-glance view of platform health and scale.
-- ============================================================================
SELECT
    COUNT(*)                                        AS total_bookings,
    SUM(amount)                                     AS total_revenue,
    SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active_rides,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_rides,
    SUM(CASE WHEN status = 'overdue' THEN 1 ELSE 0 END)   AS overdue_rides,
    ROUND(AVG(amount), 2)                           AS avg_booking_value
FROM bookings;

-- ============================================================================
-- QUERY 2: Month-over-Month Revenue Growth Percentage
-- ============================================================================
-- WHAT:      Calculates monthly revenue and the percentage change compared
--            to the previous month using the LAG window function.
-- CONCEPTS:  DATE_FORMAT for month extraction, LAG() window function,
--            percentage calculation with ROUND, NULL handling for first month.
-- INSIGHT:   Reveals growth trajectory — accelerating, stable, or declining.
--            Critical for investor reporting and forecasting.
-- ============================================================================
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

-- ============================================================================
-- QUERY 4: Top 5 Vehicle Models by Booking Count
-- ============================================================================
-- WHAT:      Ranks EV models by popularity (number of bookings) to identify
--            which models customers prefer.
-- CONCEPTS:  JOIN between bookings and vehicles, GROUP BY, ORDER BY DESC,
--            LIMIT for top-N analysis.
-- INSIGHT:   Guides procurement decisions — invest more in popular models,
--            phase out underperforming ones.
-- ============================================================================
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

-- ============================================================================
-- QUERY 11: Sales Agent Leaderboard
-- ============================================================================
-- WHAT:      Ranks sales agents by the number of customers they referred who
--            went on to make bookings, plus total revenue attributed to them.
-- CONCEPTS:  Multi-table JOIN (agents → customers → bookings), complex
--            aggregation with COUNT DISTINCT, LEFT JOIN for agents with zero
--            referrals, COALESCE for NULL handling.
-- INSIGHT:   Identifies top-performing agents for bonuses and underperformers
--            for coaching. Revenue attribution helps calculate commission.
-- ============================================================================
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

-- ============================================================================
-- QUERY 12: Package Popularity Trend by Month
-- ============================================================================
-- WHAT:      Shows how the popularity of each package type changes month over
--            month — are customers shifting to longer commitments?
-- CONCEPTS:  DATE_FORMAT for month extraction, GROUP BY on two dimensions
--            (month × package), COUNT for frequency analysis.
-- INSIGHT:   A shift from "1 Month" to "6 Months" packages indicates growing
--            customer confidence. Useful for pricing strategy adjustments.
-- ============================================================================
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

-- ============================================================================
-- QUERY 20: Hub-to-Hub Demand Gap Analysis (Self-Join)
-- ============================================================================
-- WHAT:      Compares every pair of hubs within the same city to identify
--            demand imbalances — one hub may be overwhelmed while a nearby
--            hub is underutilized.
-- CONCEPTS:  Self-join on hubs table (h1 × h2), subquery aggregation,
--            ABS() for absolute difference, percentage gap calculation.
-- INSIGHT:   Demand gaps suggest vehicle redistribution opportunities.
--            If Hub A has 3x the bookings of Hub B in the same city,
--            vehicles should be moved from B to A.
-- ============================================================================
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