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
	SELECT
		count(1) AS 'maximum_committers',
		IFNULL(sum(is_active), 0) AS 'active_committers',
		count(1) - IFNULL(sum(is_active OR
		1 != 1
	), 0) AS 'additional_committers',
		IFNULL(sum(is_unique AND
		1 = 1
	), 0) AS 'unique_committers',
		IFNULL(sum(
		0
	 AND not is_active), 0) AS 'additional_metered_committers'
	FROM (
		SELECT
			user_id,
			max(
		1 = 1 /* ANY repository_id */
	) AS 'repo_included',
			max(active) AS 'is_active',
			max(active) and min(
		1 = 1 /* ANY repository_id */
	 or not active) AS 'is_unique'
		FROM cte_contributions
		GROUP BY user_id
		HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors)
	) AS contributions
	WHERE repo_included = 1

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
	SELECT
		count(1) AS 'maximum_committers',
		IFNULL(sum(is_active), 0) AS 'active_committers',
		count(1) - IFNULL(sum(is_active OR
		1 != 1
	), 0) AS 'additional_committers',
		IFNULL(sum(is_unique AND
		1 = 1
	), 0) AS 'unique_committers',
		IFNULL(sum(
		0
	 AND not is_active), 0) AS 'additional_metered_committers'
	FROM (
		SELECT
			user_id,
			max(
		repository_id IN (?)
	) AS 'repo_included',
			max(active) AS 'is_active',
			max(active) and min(
		repository_id IN (?)
	 or not active) AS 'is_unique'
		FROM cte_contributions
		GROUP BY user_id
		HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors)
	) AS contributions
	WHERE repo_included = 1

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
	SELECT
		count(1) AS 'maximum_committers',
		IFNULL(sum(is_active), 0) AS 'active_committers',
		count(1) - IFNULL(sum(is_active OR
		1 != 1
	), 0) AS 'additional_committers',
		IFNULL(sum(is_unique AND
		1 = 1
	), 0) AS 'unique_committers',
		IFNULL(sum(
		0
	 AND not is_active), 0) AS 'additional_metered_committers'
	FROM (
		SELECT
			user_id,
			max(
		repository_id IN (?, ?)
	) AS 'repo_included',
			max(active) AS 'is_active',
			max(active) and min(
		repository_id IN (?, ?)
	 or not active) AS 'is_unique'
		FROM cte_contributions
		GROUP BY user_id
		HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors)
	) AS contributions
	WHERE repo_included = 1

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
	SELECT
		count(1) AS 'maximum_committers',
		IFNULL(sum(is_active), 0) AS 'active_committers',
		count(1) - IFNULL(sum(is_active OR
		1 != 1
	), 0) AS 'additional_committers',
		IFNULL(sum(is_unique AND
		1 = 1
	), 0) AS 'unique_committers',
		IFNULL(sum(
		user_id IN (SELECT actor_id
		FROM tg_meter_emissions
		WHERE customer_id = ? AND actor_id IN (?))
	 AND not is_active), 0) AS 'additional_metered_committers'
	FROM (
		SELECT
			user_id,
			max(
		1 = 1 /* ANY repository_id */
	) AS 'repo_included',
			max(active) AS 'is_active',
			max(active) and min(
		1 = 1 /* ANY repository_id */
	 or not active) AS 'is_unique'
		FROM cte_contributions
		GROUP BY user_id
		HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors)
	) AS contributions
	WHERE repo_included = 1

--

WITH
	cte_contributors AS (
		SELECT tg_users.user_id FROM tg_purchasers
		INNER JOIN tg_entities ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
		INNER JOIN json_table(tg_entities.user_ids, '$[*]' columns(user_id INT PATH '$')) AS seats
		INNER JOIN tg_users ON tg_users.user_id = seats.user_id
		WHERE
			tg_purchasers.owner_id = ?
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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND tg_repositories.enabled
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT
		count(1) AS 'maximum_committers',
		IFNULL(sum(is_active), 0) AS 'active_committers',
		count(1) - IFNULL(sum(is_active OR
		user_id IN (SELECT /*+ NO_MERGE(cte_entity_contributors) */ user_id FROM cte_entity_contributors WHERE cte_entity_contributors.owners > 1)
	), 0) AS 'additional_committers',
		IFNULL(sum(is_unique AND
		user_id IN (SELECT /*+ NO_MERGE(cte_entity_contributors) */ user_id FROM cte_entity_contributors WHERE cte_entity_contributors.owners = 1)
	), 0) AS 'unique_committers',
		IFNULL(sum(
		0
	 AND not is_active), 0) AS 'additional_metered_committers'
	FROM (
		SELECT
			user_id,
			max(
		1 = 1 /* ANY repository_id */
	) AS 'repo_included',
			max(active) AS 'is_active',
			max(active) and min(
		1 = 1 /* ANY repository_id */
	 or not active) AS 'is_unique'
		FROM cte_contributions
		GROUP BY user_id
		HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors)
	) AS contributions
	WHERE repo_included = 1

--

WITH
	cte_contributors AS (
		SELECT tg_users.user_id FROM tg_purchasers
		INNER JOIN tg_entities ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
		INNER JOIN json_table(tg_entities.user_ids, '$[*]' columns(user_id INT PATH '$')) AS seats
		INNER JOIN tg_users ON tg_users.user_id = seats.user_id
		WHERE
			tg_purchasers.owner_id = ?
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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND tg_repositories.enabled
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT
		count(1) AS 'maximum_committers',
		IFNULL(sum(is_active), 0) AS 'active_committers',
		count(1) - IFNULL(sum(is_active OR
		user_id IN (SELECT /*+ NO_MERGE(cte_entity_contributors) */ user_id FROM cte_entity_contributors WHERE cte_entity_contributors.owners > 1)
	), 0) AS 'additional_committers',
		IFNULL(sum(is_unique AND
		user_id IN (SELECT /*+ NO_MERGE(cte_entity_contributors) */ user_id FROM cte_entity_contributors WHERE cte_entity_contributors.owners = 1)
	), 0) AS 'unique_committers',
		IFNULL(sum(
		0
	 AND not is_active), 0) AS 'additional_metered_committers'
	FROM (
		SELECT
			user_id,
			max(
		repository_id IN (?)
	) AS 'repo_included',
			max(active) AS 'is_active',
			max(active) and min(
		repository_id IN (?)
	 or not active) AS 'is_unique'
		FROM cte_contributions
		GROUP BY user_id
		HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors)
	) AS contributions
	WHERE repo_included = 1
