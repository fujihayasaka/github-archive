WITH
	cte_enabled_repositories AS (
		SELECT
		    tg_repositories.repository_id AS repository_id,
		    concat(owners.login, '/', tg_repositories.name) AS repository_nwo
		FROM tg_entities
		INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
		INNER JOIN tg_users owners ON owners.user_id = tg_purchasers.owner_id
		INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND tg_repositories.enabled
		WHERE
			(tg_repositories.enabled & ?) != 0
		 AND
			tg_entities.entity_type = 'Business' AND tg_entities.entity_id = ?
	)
	SELECT COUNT(1) FROM cte_enabled_repositories

--

WITH
	cte_enabled_repositories AS (
		SELECT
		    tg_repositories.repository_id AS repository_id,
		    concat(owners.login, '/', tg_repositories.name) AS repository_nwo
		FROM tg_entities
		INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
		INNER JOIN tg_users owners ON owners.user_id = tg_purchasers.owner_id
		INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND tg_repositories.enabled
		WHERE
			(tg_repositories.enabled & ?) != 0
		 AND
			tg_entities.entity_type = 'Business' AND tg_entities.entity_id = ?
	)
	SELECT repository_id, repository_nwo FROM cte_enabled_repositories ORDER BY
		repository_nwo asc
	 LIMIT ?, ?
