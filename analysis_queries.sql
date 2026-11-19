2. FINANCE ANALYSIS
-- ================================================================

-- 2.1 Revenue, COGS, gross profit, gross margin (headline)
SELECT
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 2) AS gross_revenue,
    ROUND(SUM(oi.quantity * p.unit_cost), 2)                       AS total_cogs,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) - SUM(oi.quantity * p.unit_cost), 2) AS gross_profit,
    ROUND(100.0 * (SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) - SUM(oi.quantity * p.unit_cost))
          / SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 1) AS gross_margin_pct
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p      ON p.product_id = oi.product_id
WHERE o.status <> 'Cancelled';

-- 2.2 Cash collected vs. booked revenue (accounts-receivable style gap) per order
SELECT o.order_id, o.order_date, o.status,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 2) AS order_revenue,
       COALESCE(pay.collected, 0)                                     AS collected,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) - COALESCE(pay.collected, 0), 2) AS ar_gap
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
LEFT JOIN (
    SELECT order_id, SUM(amount) AS collected
    FROM payments
    WHERE status = 'Completed'
    GROUP BY order_id
) pay ON pay.order_id = o.order_id
WHERE o.status <> 'Cancelled'
GROUP BY o.order_id, o.order_date, o.status, pay.collected
HAVING ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) - COALESCE(pay.collected, 0), 2) > 0
ORDER BY ar_gap DESC;

-- 2.3 Payments by status and by method
SELECT status, COUNT(*) AS payment_count, ROUND(SUM(amount), 2) AS total_amount,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_payments
FROM payments
GROUP BY status
ORDER BY total_amount DESC;

SELECT method, COUNT(*) AS payment_count, ROUND(SUM(amount), 2) AS total_amount
FROM payments
GROUP BY method
ORDER BY total_amount DESC;

-- 2.4 Department budget vs. actual payroll cost, with variance
SELECT d.department_name, d.budget,
       COUNT(e.employee_id)                       AS headcount,
       ROUND(SUM(e.salary), 2)                     AS payroll_cost,
       ROUND(d.budget - SUM(e.salary), 2)           AS variance,
       ROUND(100.0 * SUM(e.salary) / d.budget, 1)   AS budget_utilization_pct
FROM departments d
LEFT JOIN employees e ON e.department_id = d.department_id
GROUP BY d.department_id, d.department_name, d.budget
ORDER BY budget_utilization_pct DESC;

-- 2.5 Category profitability (revenue vs. current-cost COGS vs. margin)
SELECT c.category_name,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 2) AS revenue,
       ROUND(SUM(oi.quantity * p.unit_cost), 2)                       AS est_cogs,
       ROUND(100.0 * (SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) - SUM(oi.quantity * p.unit_cost))
             / SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 1) AS est_margin_pct
FROM order_items oi
JOIN products p   ON p.product_id = oi.product_id
JOIN categories c ON c.category_id = p.category_id
JOIN orders o     ON o.order_id = oi.order_id
WHERE o.status <> 'Cancelled'
GROUP BY c.category_name
ORDER BY est_margin_pct DESC;

-- 2.6 Monthly cash collected (completed payments only) vs. booked revenue
WITH booked AS (
    SELECT DATE_TRUNC('month', o.order_date)::date AS month,
           SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) AS revenue
    FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status <> 'Cancelled'
    GROUP BY 1
),
collected AS (
    SELECT DATE_TRUNC('month', payment_date)::date AS month, SUM(amount) AS cash
    FROM payments WHERE status = 'Completed'
    GROUP BY 1
)
SELECT COALESCE(b.month, c.month) AS month,
       ROUND(COALESCE(b.revenue, 0), 2) AS booked_revenue,
       ROUND(COALESCE(c.cash, 0), 2)    AS cash_collected
FROM booked b
FULL OUTER JOIN collected c ON c.month = b.month
ORDER BY 1;

-- 2.7 Failed/refunded payment exposure by payment method
SELECT method,
       COUNT(*) FILTER (WHERE status = 'Refunded')              AS refunded_count,
       ROUND(SUM(amount) FILTER (WHERE status = 'Refunded'), 2) AS refunded_amount,
       COUNT(*) FILTER (WHERE status = 'Pending')                AS pending_count,
       ROUND(SUM(amount) FILTER (WHERE status = 'Pending'), 2)  AS pending_amount
FROM payments
GROUP BY method
ORDER BY refunded_amount DESC NULLS LAST;

-- 2.8 Revenue concentration risk: % of revenue from top 5 customers (Pareto check)
WITH cust_rev AS (
    SELECT o.customer_id, SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) AS revenue
    FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status <> 'Cancelled'
    GROUP BY o.customer_id
),
ranked AS (
    SELECT *, RANK() OVER (ORDER BY revenue DESC) AS rnk FROM cust_rev
)
SELECT
    ROUND(100.0 * SUM(revenue) FILTER (WHERE rnk <= 5) / SUM(revenue), 1) AS pct_revenue_top5_customers,
    ROUND(100.0 * SUM(revenue) FILTER (WHERE rnk <= 10) / SUM(revenue), 1) AS pct_revenue_top10_customers
FROM ranked;


-- ================================================================
--
