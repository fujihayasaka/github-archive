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
			tg_repositories.enabled AS active,
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
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories FROM cte_contributions WHERE active GROUP BY user_id
	)
	SELECT COUNT(DISTINCT owner_id) FROM cte_contributions WHERE active AND owner_type = 'Organization' AND user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors)

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
			tg_repositories.enabled AS active,
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
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories FROM cte_contributions WHERE active GROUP BY user_id
	)
	SELECT owner_id, owners.login, committers, unique_committers FROM (
		SELECT
			org_contributions.owner_id,
			COUNT(DISTINCT org_contributions.user_id) AS committers,
			IFNULL(SUM(org_contributions.user_id IN (SELECT /*+ NO_MERGE(cte_entity_contributors) */ user_id FROM cte_entity_contributors WHERE cte_entity_contributors.owners = 1)), 0) AS unique_committers
		FROM (
		SELECT owner_id, user_id FROM cte_contributions WHERE active GROUP BY owner_id, user_id HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors)
	) AS org_contributions
		GROUP BY org_contributions.owner_id
	) AS grouped
	INNER JOIN tg_users owners ON owners.user_id = grouped.owner_id
	WHERE owners.type = 'Organization'
	ORDER BY
		3 DESC, 1 ASC
	LIMIT ?, ?
