
SELECT * FROM [gold.dim_customers]
SELECT MIN(order_date) mindate,
MAX(order_date) maxdate,
DATEDIFF(DAY,MIN(order_date), MAX(order_date)) differetdate
FROM [gold.fact_sales];

SELECT MIN(birthdate) mindate,
DATEDIFF(YEAR, MIN(birthdate), GETDATE()) lastyear
FROM [gold.dim_customers];

SELECT COUNT(quantity) FROM [gold.fact_sales];

SELECT SUM(sales_amount) FROM [gold.fact_sales];

--
SELECT 
	SUM(sales_amount) Total_sale, 
	category FROM [gold.fact_sales]
LEFT JOIN [gold.dim_products]
ON [gold.fact_sales].product_key = [gold.dim_products].product_key
GROUP BY category
ORDER BY SUM(sales_amount);

--Which 5 country generate the highest revenue?
SELECT TOP 5 
	SUM(sales_amount) Total_Sales, 
	country FROM [gold.fact_sales] f
LEFT JOIN [gold.dim_customers] c
ON f.customer_key = c.customer_key
GROUP BY country
ORDER BY country DESC;

--What are the 5 worst_performing products in term of sales?
SELECT TOP 5 
	SUM(sales_amount) Total_sales, 
	product_name
FROM [gold.fact_sales] f
LEFT JOIN [gold.dim_products] p
ON f.product_key = p.product_key
GROUP BY product_name
ORDER BY SUM(sales_amount);

--TOP 10 customers who have generated the highest revenue
--and 3  with fewer order place.
SELECT	TOP 10
		customer_id, order_number,
		CONCAT (first_name, ' ', last_name) Fullname,
		SUM(sales_amount) Total_sales
FROM [gold.dim_customers] c
LEFT JOIN [gold.fact_sales] f
ON c.customer_key = f.customer_key
GROUP BY customer_id, CONCAT (first_name, ' ', last_name), order_number

--Performance sale over year
SELECT  
	DATETRUNC(MONTH, order_date) Order_month,
	COUNT(customer_key)	Total_customer,
	COUNT(product_key)	Total_products,
	SUM	(sales_amount)	Total_sales,
	SUM	(quantity)		Total_quantity
FROM [gold.fact_sales]
WHERE MONTH(order_date) IS NOT NULL
GROUP BY DATETRUNC(MONTH, order_date) 
ORDER BY DATETRUNC(MONTH, order_date);

--Calculate the total sales per month and the running total sales over time.
SELECT 
	Monthsale,
	Total_sales,
	SUM(Total_sales) OVER (ORDER BY Monthsale) AS Running_sales
FROM
(
SELECT  
	DATETRUNC(MONTH, order_date) AS Monthsale,
	SUM(sales_amount) AS Total_sales
FROM [gold.fact_sales]
GROUP BY DATETRUNC(MONTH, order_date)	
)t
ORDER BY Monthsale

/*Year over Year sales performance analysis
--analyzed the performance of product by comparing their sales 
--to both the average sales performance of the product and the previous's year sales*/
WITH cte_yoy AS
	(
	SELECT 
		Sales_year,
		product_name,
		current_sales,
		--Average sales for the products across years
		AVG(current_sales) OVER (PARTITION BY product_name ORDER BY Sales_year) AS Avg_sales,
		--Sales from the previous year for the same product
		LAG(current_sales) OVER (PARTITION BY product_name ORDER BY Sales_year) AS Previous_sale
	FROM
		(
			SELECT 
				YEAR(order_date) AS Sales_year,
				product_name,
				SUM(sales_amount) AS current_sales
			FROM [gold.fact_sales] AS f
			LEFT JOIN [gold.dim_products] AS p
			ON f.product_key = p.product_key
			WHERE product_name IS NOT NULL
			GROUP BY product_name, YEAR(order_date)
		) AS t
	)
SELECT 
	Sales_year,
	product_name,
	current_sales,
	Previous_sale,
	Avg_sales,
	 -- Difference between current sales and the average sales
	(current_sales - Avg_sales) AS diff_changes,
	-- Year-over-Year percentage change
	(current_sales - Previous_sale) / COALESCE(NULLIF(Previous_sale, 0), 1) *100 AS YoY_changes,
	CASE
		WHEN (current_sales - Avg_sales) > 0 THEN 'Above avg'
		WHEN (current_sales - Avg_sales) < 0 THEN 'Below avg'
		ELSE 'Avg'
	END AS Avg_rank,

	CASE
		WHEN (current_sales - Previous_sale) > 0 THEN 'Increase'
		WHEN (current_sales - Previous_sale) < 0 THEN 'Decrease'
		ELSE 'No Change'
	END AS Sales_changes
FROM cte_yoy
ORDER BY  Sales_year, Sales_changes;

--Which categories contributed the most overall sales
With cte_sales_category
AS
(
	SELECT 
	category, SUM(sales_amount) total_sales
	FROM [gold.fact_sales] AS f
	LEFT JOIN [gold.dim_products] AS p
	ON f.product_key = p.product_key
	GROUP BY category
)
SELECT 
	category,
	total_sales,
	SUM(total_sales) OVER() Overall_sales,
	CONCAT(ROUND(CAST(total_sales AS FLOAT)/SUM(total_sales) OVER() *100, 2), '%') percent_sales
FROM cte_sales_category
ORDER BY total_sales DESC;

/* Segment products into cost range and count how many products falls into each segment*/
SELECT COUNT(product_id) total_products,
		Cost_range
FROM
(SELECT product_id,
	product_name,cost,
	CASE
		WHEN cost BETWEEN 0 AND 500 THEN 'Low cost'
		WHEN cost BETWEEN 501 AND  1000 THEN 'Medium cost'
		WHEN cost BETWEEN 1001 AND  2000 THEN 'High cost'
	END AS Cost_range
FROM [gold.dim_products])t
GROUP BY Cost_range;

 /* Group customer into segment based on their spending behavior:
	-VIP:Customer with at least 12 month of history and spending more than #5000
	-Regular:Customer with at least 12 month of history and spending #5000 or less
	-New :Customer with a lifespan less than 12 month.
	Find the number of customer by each group
*/

with spending_segment AS
(
	SELECT
		customer_id,
		total_sales,
		diff_date
	FROM
		(SELECT c.customer_id,
		SUM(sales_amount) total_sales,
		DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) diff_date
		FROM [gold.fact_sales] f
		LEFT JOIN [gold.dim_customers] c
		ON f.customer_key = c.customer_key
		GROUP BY customer_id)t	
)

SELECT 
	COUNT(customer_id) AS total_customer,
	Customer_segment
FROM 
	(SELECT 
		customer_id,
		total_sales,
		diff_date,
	CASE
		WHEN total_sales > 5000 AND diff_date >= 12 THEN 'VIP'
		WHEN total_sales <= 5000 AND diff_date >= 12  THEN 'Regular'
		ELSE 'New'
	END AS Customer_segment
	FROM spending_segment) AS u
GROUP BY Customer_segment
ORDER BY COUNT(customer_id)

/*Customer metrics and behavior report*/
SELECT * FROM [gold.dim_customers];



with customer_metrics AS
(   
--customer and dimensionn data
	SELECT 
		c.customer_key,
		order_number,
		customer_id,
		CONCAT(first_name, ' ', last_name) AS customer_name,
		gender,
		birthdate,
		sales_amount,
		quantity,
		order_date
	FROM [gold.dim_customers] c
	LEFT JOIN [gold.fact_sales] f
	ON c.customer_key = f.customer_key
),
--aggregation
customer_aggregate AS
(   SELECT	customer_key,
			customer_id,
			customer_name,
			gender,
			birthdate,
			DATEDIFF(YEAR, birthdate, GETDATE()) 
			-IIF(FORMAT (birthdate, 'MMdd') > FORMAT(GETDATE(), 'MMdd'), 1, 0) AS age,
			COALESCE(NULLIF(DATEDIFF(MONTH,MIN(order_date),MAX(order_date)),0), 1) AS customer_lifetime,
			MAX(order_date) AS last_order_date,
			DATEDIFF(DAY, MAX(order_date), '2014-01-28') AS recency,
			SUM(sales_amount) AS total_sales,
			SUM(quantity) AS total_quantity,
			COUNT(DISTINCT order_number) AS total_order	
	FROM    customer_metrics
	GROUP BY customer_key,
			customer_id,
			customer_name,
			gender,
			birthdate
),
customer_report AS
(SELECT
		customer_key,
		customer_id,
		customer_name,
		gender,
		birthdate,
		age,
		customer_lifetime,
		last_order_date,
		total_sales,
		total_quantity,
		total_order,
		COUNT(customer_id) OVER() AS total_count_customer,
--Valuable KPIs
		total_sales/customer_lifetime AS avg_monthly_spend,
		recency,
		(total_sales *1)/NULLIF(total_order, 0) AS avg_order_value,
		(total_order *1) /NULLIF(customer_lifetime, 0) AS order_frequency,
		(total_quantity *1)/NULLIF(total_order, 0) As avg_item_per_order
FROM	customer_aggregate
)
SELECT 
		customer_key,
		customer_id,
		customer_name,
		gender,
		birthdate,
		age,
		customer_lifetime,
		last_order_date,
		recency,
		total_sales,
		total_quantity,
		total_order,
		total_count_customer,
		avg_order_value,
		avg_monthly_spend,
--Customer segment
	CASE
		WHEN age <= 40 THEN 'Young Adult'
		WHEN age <= 55 THEN 'Adult'
		ELSE 'Old'
	END AS age_group,
	CASE
		WHEN total_sales > 5000 AND customer_lifetime >= 12 THEN 'VIP'
		WHEN total_sales <= 5000 AND customer_lifetime >= 12  THEN 'Regular'
		ELSE 'New'
	END AS Customer_segment,
	CASE
		WHEN recency BETWEEN 1 AND 90 THEN 'Active'
		WHEN recency BETWEEN 91 AND 120 THEN 'Warm'
		ELSE 'At_risk'
	END activity_status
FROM customer_report;

GO
 /* Group products into categories based on their sales performance:
    - Best Seller: Products with at least 12 months of sales history and total sales over $50,000
    - Average Seller: Products with at least 12 months of sales history and total sales of $50,000 or less
    - New Product: Products with a lifespan of less than 12 months
    Find the number of products in each category.
*/

/* Product dimension data*/
CREATE VIEW Products_reports  AS

with product_database AS
(
SELECT 
	p.product_key,
	product_id,
	product_name,
	order_number,
	customer_key,
	category_id,
	order_date,
	cost,
	sales_amount,
	quantity
FROM [gold.dim_products] p
LEFT JOIN [gold.fact_sales] f
ON p.product_key = f.product_key
WHERE order_date IS NOT NULL
),
product_aggregate AS
(
SELECT
	product_key,
	product_id,
	product_name,
	DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS products_lifespan,
	MAX(order_date) AS last_sales_date,
	DATEDIFF(MONTH, MAX(order_date), '2014-01-28') AS recency_in_month,
	SUM(cost) AS total_cost,
	SUM(sales_amount) AS total_sale,
	COUNT(DISTINCT order_number) AS total_order,
	COUNT(DISTINCT customer_key) AS total_customer,
	SUM(quantity) AS total_quantity,
	ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity,0)), 1) AS avg_selling_price
FROM product_database
GROUP BY 
	product_key,
	product_id,
	product_name
	)
SELECT 
	product_key,
	product_id,
	product_name,
	last_sales_date,
	products_lifespan,
	recency_in_month,
	total_sale,
	total_cost,
	total_order,
	total_quantity,
	total_customer,
	avg_selling_price,
	CASE
		WHEN total_order = 0 THEN 0
		ELSE total_sale/total_order
	END AS Avg_order_revenue,
	CASE
		WHEN products_lifespan = 0 THEN total_sale
		ELSE total_sale/products_lifespan
	END AS Avg_monthly_revenue,
	CASE
		WHEN total_sale < 300000 THEN 'Slow_mover'
		WHEN total_sale BETWEEN 300000 AND 600000 THEN 'Steady_selling'
		WHEN total_sale > 600000 THEN 'Best_selling'
	END AS sales_performance
FROM product_aggregate;