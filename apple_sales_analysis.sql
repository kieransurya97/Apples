-- Apple Sales SQL Project
-- PostgreSQL

-- =========================================================
-- EXPLORATORY DATA ANALYSIS
-- =========================================================

SELECT * FROM category;
SELECT * FROM products;
SELECT * FROM stores;
SELECT * FROM sales;
SELECT * FROM warranty;

SELECT DISTINCT repair_status
FROM warranty;

SELECT COUNT(*) AS total_sales_rows
FROM sales;

-- =========================================================
-- QUERY PERFORMANCE
-- =========================================================

EXPLAIN ANALYZE
SELECT *
FROM sales
WHERE product_id = 'P-44';

CREATE INDEX IF NOT EXISTS idx_sales_product_id
    ON sales(product_id);

CREATE INDEX IF NOT EXISTS idx_sales_store_id
    ON sales(store_id);

CREATE INDEX IF NOT EXISTS idx_sales_sale_date
    ON sales(sale_date);

EXPLAIN ANALYZE
SELECT *
FROM sales
WHERE store_id = 'ST-31';

-- =========================================================
-- BUSINESS QUESTIONS
-- =========================================================

-- Q1. Number of stores in each country
SELECT
    country,
    COUNT(store_id) AS total_stores
FROM stores
GROUP BY country
ORDER BY total_stores DESC;

-- Q2. Total units sold by each store
SELECT
    s.store_id,
    st.store_name,
    SUM(s.quantity) AS total_units_sold
FROM sales AS s
JOIN stores AS st
    ON st.store_id = s.store_id
GROUP BY s.store_id, st.store_name
ORDER BY total_units_sold DESC;

-- Q3. Sales in December 2023
SELECT
    COUNT(sale_id) AS total_sales
FROM sales
WHERE sale_date >= DATE '2023-12-01'
  AND sale_date < DATE '2024-01-01';

-- Q4. Stores that never had a warranty claim
SELECT COUNT(*) AS stores_without_claims
FROM stores AS st
WHERE NOT EXISTS (
    SELECT 1
    FROM sales AS s
    JOIN warranty AS w
        ON w.sale_id = s.sale_id
    WHERE s.store_id = st.store_id
);

-- Q5. Percentage of claims marked Warranty Void
SELECT
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE repair_status = 'Warranty Void'
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS warranty_void_percentage
FROM warranty;

-- Q6. Store with highest units sold in latest dataset year
SELECT
    s.store_id,
    st.store_name,
    SUM(s.quantity) AS total_units_sold
FROM sales AS s
JOIN stores AS st
    ON st.store_id = s.store_id
WHERE s.sale_date >= (
    SELECT MAX(sale_date) - INTERVAL '1 year'
    FROM sales
)
GROUP BY s.store_id, st.store_name
ORDER BY total_units_sold DESC
LIMIT 1;

-- Q7. Unique products sold in latest dataset year
SELECT
    COUNT(DISTINCT product_id) AS unique_products_sold
FROM sales
WHERE sale_date >= (
    SELECT MAX(sale_date) - INTERVAL '1 year'
    FROM sales
);

-- Q8. Average product price by category
SELECT
    p.category_id,
    c.category_name,
    ROUND(AVG(p.price)::numeric, 2) AS average_price
FROM products AS p
JOIN category AS c
    ON c.category_id = p.category_id
GROUP BY p.category_id, c.category_name
ORDER BY average_price DESC;

-- Q9. Warranty claims in 2020
SELECT
    COUNT(*) AS warranty_claims
FROM warranty
WHERE claim_date >= DATE '2020-01-01'
  AND claim_date < DATE '2021-01-01';

-- Q10. Best-selling day for each store
WITH daily_sales AS (
    SELECT
        store_id,
        TRIM(TO_CHAR(sale_date, 'Day')) AS day_name,
        SUM(quantity) AS total_units_sold
    FROM sales
    GROUP BY store_id, TRIM(TO_CHAR(sale_date, 'Day'))
),
ranked_days AS (
    SELECT
        store_id,
        day_name,
        total_units_sold,
        RANK() OVER (
            PARTITION BY store_id
            ORDER BY total_units_sold DESC
        ) AS sales_rank
    FROM daily_sales
)
SELECT
    store_id,
    day_name,
    total_units_sold
FROM ranked_days
WHERE sales_rank = 1
ORDER BY store_id;

-- Q11. Least-selling product in each country for each year
WITH yearly_product_sales AS (
    SELECT
        st.country,
        EXTRACT(YEAR FROM s.sale_date)::int AS sales_year,
        p.product_id,
        p.product_name,
        SUM(s.quantity) AS total_units_sold
    FROM sales AS s
    JOIN stores AS st
        ON st.store_id = s.store_id
    JOIN products AS p
        ON p.product_id = s.product_id
    GROUP BY
        st.country,
        EXTRACT(YEAR FROM s.sale_date),
        p.product_id,
        p.product_name
),
ranked_products AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY country, sales_year
            ORDER BY total_units_sold ASC
        ) AS product_rank
    FROM yearly_product_sales
)
SELECT
    country,
    sales_year,
    product_id,
    product_name,
    total_units_sold
FROM ranked_products
WHERE product_rank = 1
ORDER BY country, sales_year;

-- Q12. Claims filed within 180 days of sale
SELECT
    COUNT(*) AS claims_within_180_days
FROM warranty AS w
JOIN sales AS s
    ON s.sale_id = w.sale_id
WHERE w.claim_date BETWEEN s.sale_date
                       AND s.sale_date + INTERVAL '180 days';

-- Q13. Claims for products launched in latest two years
SELECT
    p.product_id,
    p.product_name,
    COUNT(DISTINCT w.claim_id) AS total_claims,
    COUNT(DISTINCT s.sale_id) AS total_sales
FROM products AS p
LEFT JOIN sales AS s
    ON s.product_id = p.product_id
LEFT JOIN warranty AS w
    ON w.sale_id = s.sale_id
WHERE p.launch_date >= (
    SELECT MAX(launch_date) - INTERVAL '2 years'
    FROM products
)
GROUP BY p.product_id, p.product_name
HAVING COUNT(w.claim_id) > 0
ORDER BY total_claims DESC;

-- Q14. USA months exceeding 5,000 units in latest three years
SELECT
    DATE_TRUNC('month', s.sale_date)::date AS sales_month,
    SUM(s.quantity) AS total_units_sold
FROM sales AS s
JOIN stores AS st
    ON st.store_id = s.store_id
WHERE st.country = 'USA'
  AND s.sale_date >= (
      SELECT MAX(sale_date) - INTERVAL '3 years'
      FROM sales
  )
GROUP BY DATE_TRUNC('month', s.sale_date)
HAVING SUM(s.quantity) > 5000
ORDER BY sales_month;

-- Q15. Category with most claims in latest two years
SELECT
    c.category_name,
    COUNT(w.claim_id) AS total_claims
FROM warranty AS w
JOIN sales AS s
    ON s.sale_id = w.sale_id
JOIN products AS p
    ON p.product_id = s.product_id
JOIN category AS c
    ON c.category_id = p.category_id
WHERE w.claim_date >= (
    SELECT MAX(claim_date) - INTERVAL '2 years'
    FROM warranty
)
GROUP BY c.category_name
ORDER BY total_claims DESC
LIMIT 1;

-- Q16. Warranty claim rate by country
SELECT
    st.country,
    COUNT(DISTINCT s.sale_id) AS total_purchases,
    COUNT(DISTINCT w.claim_id) AS total_claims,
    ROUND(
        100.0 * COUNT(DISTINCT w.claim_id)
        / NULLIF(COUNT(DISTINCT s.sale_id), 0),
        2
    ) AS claim_rate_percentage
FROM sales AS s
JOIN stores AS st
    ON st.store_id = s.store_id
LEFT JOIN warranty AS w
    ON w.sale_id = s.sale_id
GROUP BY st.country
ORDER BY claim_rate_percentage DESC;

-- Q17. Year-over-year revenue growth by store
WITH yearly_sales AS (
    SELECT
        s.store_id,
        st.store_name,
        EXTRACT(YEAR FROM s.sale_date)::int AS sales_year,
        SUM(s.quantity * p.price) AS total_revenue
    FROM sales AS s
    JOIN products AS p
        ON p.product_id = s.product_id
    JOIN stores AS st
        ON st.store_id = s.store_id
    GROUP BY
        s.store_id,
        st.store_name,
        EXTRACT(YEAR FROM s.sale_date)
),
growth_analysis AS (
    SELECT
        store_id,
        store_name,
        sales_year,
        total_revenue AS current_year_revenue,
        LAG(total_revenue) OVER (
            PARTITION BY store_id
            ORDER BY sales_year
        ) AS previous_year_revenue
    FROM yearly_sales
)
SELECT
    store_id,
    store_name,
    sales_year,
    previous_year_revenue,
    current_year_revenue,
    ROUND(
        100.0 * (current_year_revenue - previous_year_revenue)
        / NULLIF(previous_year_revenue, 0),
        2
    ) AS growth_percentage
FROM growth_analysis
WHERE previous_year_revenue IS NOT NULL
ORDER BY store_id, sales_year;

-- Q18. Warranty claim rate by price segment
SELECT
    CASE
        WHEN p.price < 500 THEN 'Budget Product'
        WHEN p.price BETWEEN 500 AND 1000 THEN 'Mid-Range Product'
        ELSE 'Premium Product'
    END AS price_segment,
    COUNT(DISTINCT s.sale_id) AS total_sales,
    COUNT(DISTINCT w.claim_id) AS total_claims,
    ROUND(
        100.0 * COUNT(DISTINCT w.claim_id)
        / NULLIF(COUNT(DISTINCT s.sale_id), 0),
        2
    ) AS claim_rate_percentage
FROM sales AS s
JOIN products AS p
    ON p.product_id = s.product_id
LEFT JOIN warranty AS w
    ON w.sale_id = s.sale_id
WHERE s.sale_date >= (
    SELECT MAX(sale_date) - INTERVAL '5 years'
    FROM sales
)
GROUP BY price_segment
ORDER BY claim_rate_percentage DESC;

-- Q19. Store with highest percentage of Paid Repaired claims
SELECT
    s.store_id,
    st.store_name,
    COUNT(w.claim_id) FILTER (
        WHERE w.repair_status = 'Paid Repaired'
    ) AS paid_repaired_claims,
    COUNT(w.claim_id) AS total_claims,
    ROUND(
        100.0 * COUNT(w.claim_id) FILTER (
            WHERE w.repair_status = 'Paid Repaired'
        ) / NULLIF(COUNT(w.claim_id), 0),
        2
    ) AS paid_repaired_percentage
FROM warranty AS w
JOIN sales AS s
    ON s.sale_id = w.sale_id
JOIN stores AS st
    ON st.store_id = s.store_id
GROUP BY s.store_id, st.store_name
ORDER BY paid_repaired_percentage DESC
LIMIT 1;

-- Q20. Monthly running revenue total by store
WITH monthly_sales AS (
    SELECT
        s.store_id,
        DATE_TRUNC('month', s.sale_date)::date AS sales_month,
        SUM(p.price * s.quantity) AS monthly_revenue
    FROM sales AS s
    JOIN products AS p
        ON p.product_id = s.product_id
    WHERE s.sale_date >= (
        SELECT MAX(sale_date) - INTERVAL '4 years'
        FROM sales
    )
    GROUP BY
        s.store_id,
        DATE_TRUNC('month', s.sale_date)
)
SELECT
    store_id,
    sales_month,
    monthly_revenue,
    SUM(monthly_revenue) OVER (
        PARTITION BY store_id
        ORDER BY sales_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM monthly_sales
ORDER BY store_id, sales_month;

-- BONUS. Product sales by life-cycle period
SELECT
    p.product_name,
    CASE
        WHEN s.sale_date >= p.launch_date
         AND s.sale_date < p.launch_date + INTERVAL '6 months'
            THEN '0-6 Months'
        WHEN s.sale_date >= p.launch_date + INTERVAL '6 months'
         AND s.sale_date < p.launch_date + INTERVAL '12 months'
            THEN '6-12 Months'
        WHEN s.sale_date >= p.launch_date + INTERVAL '12 months'
         AND s.sale_date < p.launch_date + INTERVAL '18 months'
            THEN '12-18 Months'
        ELSE '18+ Months'
    END AS product_life_cycle,
    SUM(s.quantity) AS total_units_sold
FROM sales AS s
JOIN products AS p
    ON p.product_id = s.product_id
WHERE s.sale_date >= p.launch_date
GROUP BY p.product_name, product_life_cycle
ORDER BY p.product_name, total_units_sold DESC;
