// Package ctes include a number of common table expressions for working with contributions.
package ctes

import (
	"context"

	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/proto"
	"github.com/simon-engledew/sqlh"
)

var SQL = sqlh.SQL

func init() {
	if fromctx.IsTest {
		SQL = sqlh.DebugSQL
	}
}

// Warning: The below is the core billing logic, so you should be reticent to change behaviour here
// Instead, you probably want to do filtering in your specific endpoint rather than here.

type contextKey string

var committerPeriodKey contextKey = "committerPeriodDays"

// WithCommitterPeriod allows the caller to override the 90 day commit window used by Advanced Security billing
func WithCommitterPeriod(ctx context.Context, days uint) context.Context {
	return context.WithValue(ctx, committerPeriodKey, days)
}

const DefaultCommitterPeriodDays = 90

func committerPeriodDays(ctx context.Context) uint {
	if v, ok := ctx.Value(committerPeriodKey).(uint); ok {
		return v
	}
	return DefaultCommitterPeriodDays
}

type Entity interface {
	GetEntityId() uint64
	GetEntityType() v1.EntityType
}

func WithContributions(ctx context.Context, req Entity, query sqlh.Expr, ctes ...sqlh.Expr) sqlh.Expr {
	return SQL("WITH ? ?", sqlh.In(append([]sqlh.Expr{
		SQL(`cte_contributors AS (?)`, contributorsForEntity(req)),
		SQL(`cte_contributions AS (?)`, contributions(ctx, req)),
		SQL(`cte_entity_contributors AS (?)`, entityContributors(ctx, req)),
	}, ctes...)), query)
}

func contributions(ctx context.Context, req Entity) sqlh.Expr {
	return SQL(`SELECT
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
WHERE ?`,
		committerPeriodDays(ctx),
		entityEq(req),
	)
}

func entityContributors(ctx context.Context, req Entity) sqlh.Expr {
	if req.GetEntityType() == v1.EntityType_ENTITY_TYPE_BUSINESS {
		return SQL(`SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories FROM cte_contributions WHERE active GROUP BY user_id`)
	}
	return SQL(`SELECT user_id, COUNT(DISTINCT owner_id) AS owners, COUNT(DISTINCT repository_id) AS repositories
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
	WHERE ?
) AS data
GROUP BY user_id`,
		committerPeriodDays(ctx),
		entityEq(req),
	)
}

var BillableUsers = SQL(`SELECT /*+ NO_MERGE(cte_contributors) */ user_id FROM cte_contributors`)

// contributorsForEntity selects all the users who are currently contributing to Entity.
func contributorsForEntity(req Entity) sqlh.Expr {
	switch req.GetEntityType() {
	case v1.EntityType_ENTITY_TYPE_BUSINESS:
		return SQL(`SELECT tg_users.user_id FROM tg_entities
INNER JOIN json_table(tg_entities.user_ids, '$[*]' columns(user_id INT PATH '$')) AS seats
INNER JOIN tg_users ON tg_users.user_id = seats.user_id
WHERE ?`, entityEq(req))
	case v1.EntityType_ENTITY_TYPE_USER:
		return SQL(`SELECT tg_users.user_id FROM tg_purchasers
INNER JOIN tg_entities ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
INNER JOIN json_table(tg_entities.user_ids, '$[*]' columns(user_id INT PATH '$')) AS seats
INNER JOIN tg_users ON tg_users.user_id = seats.user_id
WHERE ?`, entityEq(req))
	case v1.EntityType_ENTITY_TYPE_INVALID:
		break
	}

	return SQL(`SELECT 1 != 1`)
}

func entityEq(req Entity) sqlh.Expr {
	switch req.GetEntityType() {
	case v1.EntityType_ENTITY_TYPE_BUSINESS:
		return SQL(`tg_entities.entity_type = 'Business' AND tg_entities.entity_id = ?`, req.GetEntityId())

	case v1.EntityType_ENTITY_TYPE_USER:
		return SQL(`tg_purchasers.owner_id = ?`, req.GetEntityId())

	case v1.EntityType_ENTITY_TYPE_INVALID:
		break
	}

	return SQL("1 != 1")
}

// RepositoryIn repository_id IN (<repository ids in request>)
// returns all repositories when passed an empty list.
func RepositoryIn(t interface{ GetRepositoryIds() []uint64 }) sqlh.Expr {
	repoIDs := t.GetRepositoryIds()
	if len(repoIDs) > 0 {
		return SQL(`repository_id IN (?)`, sqlh.In(repoIDs))
	}
	return SQL("1 = 1 /* ANY repository_id */")
}

func AdditionalCommitters(committerType proto.CommitterType) sqlh.Expr {
	if committerType == proto.CommitterType_ADDITIONAL_COMMITTERS {
		return EntityCommitters
	}
	return SQL("0")
}

var EntityCommitters = SQL(`SELECT /*+ NO_MERGE(cte_entity_contributors) */ user_id FROM cte_entity_contributors`)
var SharedCommitters = SQL(`? WHERE cte_entity_contributors.owners > 1`, EntityCommitters)
var UniqueCommitters = SQL(`? WHERE cte_entity_contributors.owners = 1`, EntityCommitters)
var UniqueRepositoryCommitters = SQL(`? WHERE cte_entity_contributors.repositories = 1`, EntityCommitters)
