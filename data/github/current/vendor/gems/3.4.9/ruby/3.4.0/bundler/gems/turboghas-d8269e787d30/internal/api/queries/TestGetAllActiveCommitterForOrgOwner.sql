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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE features_active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND
			(tg_repositories.enabled & ?) != 0
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT COUNT(1) FROM (SELECT 1 FROM cte_contributions WHERE
			1 = 1 /* ANY repository_id */
		 AND features_active
	 GROUP BY user_id, repository_id HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors) AND user_id NOT IN (
		0
	)) AS grouped

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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE features_active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND
			(tg_repositories.enabled & ?) != 0
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT COUNT(1) FROM (SELECT 1 FROM cte_contributions WHERE
		1 = 1 /* ANY repository_id */
	 GROUP BY user_id, repository_id HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors) AND user_id NOT IN (
		0
	)) AS grouped

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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE features_active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND
			(tg_repositories.enabled & ?) != 0
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT COUNT(1) FROM (SELECT 1 FROM cte_contributions WHERE
		1 = 1 /* ANY repository_id */
	 GROUP BY user_id, repository_id HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors) AND user_id NOT IN (SELECT /*+ NO_MERGE(cte_entity_contributors) */ user_id FROM cte_entity_contributors)) AS grouped

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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE features_active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND
			(tg_repositories.enabled & ?) != 0
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT COUNT(1) FROM (SELECT 1 FROM cte_contributions WHERE
		repository_id IN (?)
	 GROUP BY user_id, repository_id HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors) AND user_id NOT IN (
		0
	)) AS grouped

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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE features_active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND
			(tg_repositories.enabled & ?) != 0
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT COUNT(1) FROM (SELECT 1 FROM cte_contributions WHERE
		repository_id IN (?, ?)
	 GROUP BY user_id, repository_id HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors) AND user_id NOT IN (
		0
	)) AS grouped

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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE features_active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND
			(tg_repositories.enabled & ?) != 0
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT grouped.user_id, tg_users.login, grouped.repository_id, concat(owners.login, '/', tg_repositories.name) as repository_nwo, tg_contributions.pushed_at, tg_contributions.email
	FROM (
		SELECT MAX(id) AS id, user_id, repository_id FROM cte_contributions WHERE
				1 = 1 /* ANY repository_id */
			 AND features_active
		 GROUP BY user_id, repository_id HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors) AND user_id NOT IN (
			0
		)
	) AS grouped
	INNER JOIN tg_repositories USING (repository_id)
	INNER JOIN tg_users USING (user_id)
	INNER JOIN tg_users owners ON tg_repositories.owner_id = owners.user_id
	INNER JOIN tg_contributions ON tg_contributions.id = grouped.id
	ORDER BY tg_repositories.name, tg_contributions.pushed_at DESC, tg_users.login ASC
	LIMIT ?, ?

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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE features_active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND
			(tg_repositories.enabled & ?) != 0
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT grouped.user_id, tg_users.login, grouped.repository_id, concat(owners.login, '/', tg_repositories.name) as repository_nwo, tg_contributions.pushed_at, tg_contributions.email
	FROM (
		SELECT MAX(id) AS id, user_id, repository_id FROM cte_contributions WHERE
			1 = 1 /* ANY repository_id */
		 GROUP BY user_id, repository_id HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors) AND user_id NOT IN (
			0
		)
	) AS grouped
	INNER JOIN tg_repositories USING (repository_id)
	INNER JOIN tg_users USING (user_id)
	INNER JOIN tg_users owners ON tg_repositories.owner_id = owners.user_id
	INNER JOIN tg_contributions ON tg_contributions.id = grouped.id
	ORDER BY tg_repositories.name, tg_contributions.pushed_at DESC, tg_users.login ASC
	LIMIT ?, ?

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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE features_active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND
			(tg_repositories.enabled & ?) != 0
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT grouped.user_id, tg_users.login, grouped.repository_id, concat(owners.login, '/', tg_repositories.name) as repository_nwo, tg_contributions.pushed_at, tg_contributions.email
	FROM (
		SELECT MAX(id) AS id, user_id, repository_id FROM cte_contributions WHERE
			1 = 1 /* ANY repository_id */
		 GROUP BY user_id, repository_id HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors) AND user_id NOT IN (SELECT /*+ NO_MERGE(cte_entity_contributors) */ user_id FROM cte_entity_contributors)
	) AS grouped
	INNER JOIN tg_repositories USING (repository_id)
	INNER JOIN tg_users USING (user_id)
	INNER JOIN tg_users owners ON tg_repositories.owner_id = owners.user_id
	INNER JOIN tg_contributions ON tg_contributions.id = grouped.id
	ORDER BY tg_repositories.name, tg_contributions.pushed_at DESC, tg_users.login ASC
	LIMIT ?, ?

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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE features_active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND
			(tg_repositories.enabled & ?) != 0
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT grouped.user_id, tg_users.login, grouped.repository_id, concat(owners.login, '/', tg_repositories.name) as repository_nwo, tg_contributions.pushed_at, tg_contributions.email
	FROM (
		SELECT MAX(id) AS id, user_id, repository_id FROM cte_contributions WHERE
			repository_id IN (?)
		 GROUP BY user_id, repository_id HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors) AND user_id NOT IN (
			0
		)
	) AS grouped
	INNER JOIN tg_repositories USING (repository_id)
	INNER JOIN tg_users USING (user_id)
	INNER JOIN tg_users owners ON tg_repositories.owner_id = owners.user_id
	INNER JOIN tg_contributions ON tg_contributions.id = grouped.id
	ORDER BY tg_repositories.name, tg_contributions.pushed_at DESC, tg_users.login ASC
	LIMIT ?, ?

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
			tg_purchasers.owner_id = ?
	),
	cte_entity_contributors AS (
		SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
		FROM (
			SELECT user_id, owner_id, repository_id
			FROM cte_contributions
			WHERE features_active
		UNION ALL
			SELECT tg_contributions.user_id, other_purchasers.owner_id, tg_repositories.repository_id
			FROM tg_entities
			INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
			INNER JOIN tg_purchasers other_purchasers ON other_purchasers.entity_id = tg_purchasers.entity_id AND other_purchasers.entity_type = tg_purchasers.entity_type AND other_purchasers.id != tg_purchasers.id
			INNER JOIN tg_users owners ON owners.user_id = other_purchasers.owner_id
			INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND
			(tg_repositories.enabled & ?) != 0
			INNER JOIN tg_contributions ON tg_contributions.repository_id = tg_repositories.repository_id AND tg_contributions.pushed_at >= DATE(NOW() - INTERVAL ? DAY)
			WHERE
			tg_purchasers.owner_id = ?
		) AS data
		GROUP BY user_id
	)
	SELECT grouped.user_id, tg_users.login, grouped.repository_id, concat(owners.login, '/', tg_repositories.name) as repository_nwo, tg_contributions.pushed_at, tg_contributions.email
	FROM (
		SELECT MAX(id) AS id, user_id, repository_id FROM cte_contributions WHERE
			repository_id IN (?, ?)
		 GROUP BY user_id, repository_id HAVING user_id IN (SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors) AND user_id NOT IN (
			0
		)
	) AS grouped
	INNER JOIN tg_repositories USING (repository_id)
	INNER JOIN tg_users USING (user_id)
	INNER JOIN tg_users owners ON tg_repositories.owner_id = owners.user_id
	INNER JOIN tg_contributions ON tg_contributions.id = grouped.id
	ORDER BY tg_repositories.name, tg_contributions.pushed_at DESC, tg_users.login ASC
	LIMIT ?, ?
