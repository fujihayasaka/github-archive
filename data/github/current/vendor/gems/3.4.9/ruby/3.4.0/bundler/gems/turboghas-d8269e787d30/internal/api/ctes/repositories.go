package ctes

import (
	"github.com/simon-engledew/sqlh"
)

func EnabledRepositoriesCTEs(req Request) []sqlh.Expr {
	return []sqlh.Expr{SQL(`cte_enabled_repositories AS (?)`, enabledRepositories(req))}
}

func enabledRepositories(req Request) sqlh.Expr {
	return SQL(`SELECT
    tg_repositories.repository_id AS repository_id,
    concat(owners.login, '/', tg_repositories.name) AS repository_nwo
FROM tg_entities
INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
INNER JOIN tg_users owners ON owners.user_id = tg_purchasers.owner_id
INNER JOIN tg_repositories ON tg_repositories.owner_id = owners.user_id AND tg_repositories.enabled
WHERE ? AND ?`,
		featuresEnabled(req.GetFeatures()),
		entityEq(req),
	)
}
