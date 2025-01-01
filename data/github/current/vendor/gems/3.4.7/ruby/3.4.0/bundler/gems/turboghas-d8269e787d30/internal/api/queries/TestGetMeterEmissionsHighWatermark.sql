WITH
	cte_contributors AS (
		SELECT tg_users.user_id FROM tg_entities
		INNER JOIN json_table(tg_entities.user_ids, '$[*]' columns(user_id INT PATH '$')) AS seats
		INNER JOIN tg_users ON tg_users.user_id = seats.user_id
		WHERE
			tg_entities.entity_type = 'Business' AND tg_entities.entity_id = ?
	),
	cte_contributions AS (
		SELECT
		    tg_contributions.id AS id,
			tg_contributions.user_id AS user_id,
			tg_contributions.repository_id AS repository_id,
			(tg_repositories.enabled & ?) != 0
		 AS features_active,
			tg_repositories.enabled,
			owners.user_id AS owner_id,
			owners.type AS owner_type,
			tg_contributions.pushed_at AS pushed_at
		FROM tg_entities
		INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
		INNER JOIN tg_users owners ON owners.user_id = tg_purchasers.owner_id
		INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id
		INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
		WHERE
			tg_entities.entity_type = 'Business' AND tg_entities.entity_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories FROM cte_contributions WHERE features_active GROUP BY user_id
	),
	cte_users AS (
		SELECT user_id FROM cte_contributions WHERE features_active HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors)
	),
	cte_previous_emissions AS (
		SELECT actor_id AS user_id
		 FROM tg_meter_emissions
		WHERE customer_id = ?
		  AND sku = ?
		  AND usage_at >= ?
	),
	cte_added AS (
		SELECT user_id FROM cte_users UNION SELECT user_id FROM cte_previous_emissions
	)
	SELECT count(1) FROM cte_added

--

WITH
	cte_contributors AS (
		SELECT tg_users.user_id FROM tg_entities
		INNER JOIN json_table(tg_entities.user_ids, '$[*]' columns(user_id INT PATH '$')) AS seats
		INNER JOIN tg_users ON tg_users.user_id = seats.user_id
		WHERE
			tg_entities.entity_type = 'Business' AND tg_entities.entity_id = ?
	),
	cte_contributions AS (
		SELECT
		    tg_contributions.id AS id,
			tg_contributions.user_id AS user_id,
			tg_contributions.repository_id AS repository_id,
			(tg_repositories.enabled & ?) != 0
		 AS features_active,
			tg_repositories.enabled,
			owners.user_id AS owner_id,
			owners.type AS owner_type,
			tg_contributions.pushed_at AS pushed_at
		FROM tg_entities
		INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
		INNER JOIN tg_users owners ON owners.user_id = tg_purchasers.owner_id
		INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id
		INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
		WHERE
			tg_entities.entity_type = 'Business' AND tg_entities.entity_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories FROM cte_contributions WHERE features_active GROUP BY user_id
	),
	cte_users AS (
		SELECT user_id FROM cte_contributions WHERE features_active HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors)
	),
	cte_previous_emissions AS (
		SELECT actor_id AS user_id
		 FROM tg_meter_emissions
		WHERE customer_id = ?
		  AND sku = ?
		  AND usage_at >= ?
	),
	cte_added AS (
		SELECT user_id FROM cte_users UNION SELECT user_id FROM cte_previous_emissions
	)
	SELECT user_id FROM cte_added WHERE user_id NOT IN (
		SELECT actor_id AS user_id
		  FROM tg_meter_emissions
		 WHERE customer_id = ?
		   AND sku = ?
		   AND usage_at > ? - INTERVAL 24 HOUR
	) ORDER BY user_id ASC
