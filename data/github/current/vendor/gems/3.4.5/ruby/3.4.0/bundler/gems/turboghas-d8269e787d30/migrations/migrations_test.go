package migrations_test

import (
	"database/sql"
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/migrations"
	"github.com/go-sql-driver/mysql"
	"github.com/golang-migrate/migrate/v4/database"
	"github.com/golang-migrate/migrate/v4/source"
	"github.com/simon-engledew/sqlh"
	"github.com/stretchr/testify/require"
)

func createDatabase(t *testing.T, cfg *mysql.Config) {
	t.Helper()

	cfg = cfg.Clone()

	db, err := sql.Open("mysql", cfg.FormatDSN())
	require.NoError(t, err)

	defer func() {
		require.NoError(t, db.Close())
	}()

	{
		_, err := db.Exec(`
DROP DATABASE IF EXISTS turboghas_enterprise_test;
CREATE DATABASE turboghas_enterprise_test COLLATE utf8mb4_general_ci;
USE turboghas_enterprise_test;
DROP TABLE IF EXISTS ghas_repository_contributions;
CREATE TABLE ghas_repository_contributions (
	id bigint unsigned NOT NULL AUTO_INCREMENT,
	repository_id bigint NOT NULL,
	user_id bigint NOT NULL,
	pushed_date date NOT NULL,
	created_at datetime NOT NULL,
	updated_at datetime NOT NULL,
	owner_id bigint unsigned DEFAULT NULL,
	advanced_security_enabled tinyint(1) DEFAULT NULL,
	PRIMARY KEY (id),
	UNIQUE KEY index_ghas_repository_contributions_on_repo_user_pushed_date (repository_id,user_id,pushed_date)
) ENGINE=InnoDB;
DROP TABLE IF EXISTS users;
CREATE TABLE users (
  id bigint unsigned NOT NULL AUTO_INCREMENT,
  login varchar(40) NOT NULL,
  created_at datetime DEFAULT NULL,
  updated_at datetime DEFAULT NULL,
  remember_token varchar(40) DEFAULT NULL,
  remember_token_expires_at datetime DEFAULT NULL,
  wants_email tinyint(1) DEFAULT '1',
  disabled tinyint(1) DEFAULT '0',
  plan varchar(30) DEFAULT NULL,
  billed_on date DEFAULT NULL,
  auth_token varchar(255) DEFAULT NULL,
  upgrade_ignore varchar(30) DEFAULT NULL,
  upgrade_accept int DEFAULT NULL,
  gh_role varchar(30) DEFAULT NULL,
  billing_attempts int DEFAULT '0',
  spammy tinyint(1) DEFAULT '0',
  last_ip varchar(40) DEFAULT NULL,
  plan_duration varchar(20) DEFAULT NULL,
  billing_extra text,
  gift tinyint(1) DEFAULT NULL,
  last_read_broadcast_id bigint unsigned DEFAULT NULL,
  type varchar(30) NOT NULL DEFAULT 'User',
  raw_data blob,
  referral_code varchar(255) DEFAULT NULL,
  billing_type varchar(20) NOT NULL DEFAULT 'card',
  bcrypt_auth_token varchar(60) DEFAULT NULL,
  suspended_at datetime DEFAULT NULL,
  organization_billing_email varchar(255) DEFAULT NULL,
  gravatar_email varchar(255) DEFAULT NULL,
  time_zone_name varchar(40) DEFAULT NULL,
  session_fingerprint varchar(32) DEFAULT NULL,
  token_secret varchar(40) DEFAULT NULL,
  restrict_oauth_applications tinyint(1) DEFAULT NULL,
  spammy_reason text,
  seats int NOT NULL DEFAULT '0',
  split_diff_preferred tinyint(1) NOT NULL DEFAULT '0',
  require_email_verification tinyint(1) NOT NULL DEFAULT '0',
  warn_private_email tinyint(1) NOT NULL DEFAULT '0',
  primary_language_name_id bigint unsigned DEFAULT NULL,
  analytics_tracking_id varchar(32) DEFAULT NULL,
  report_third_party_analytics tinyint(1) NOT NULL DEFAULT '1',
  source_login varchar(40) DEFAULT NULL,
  migration_id bigint unsigned DEFAULT NULL,
  ofac_flagged tinyint(1) NOT NULL DEFAULT '0',
  weak_password_check_result blob,
  password_hash varbinary(127) DEFAULT NULL,
  color_mode tinyint NOT NULL DEFAULT '0',
  light_theme tinyint NOT NULL DEFAULT '1',
  dark_theme tinyint NOT NULL DEFAULT '2',
  pinned_api_version varchar(15) DEFAULT NULL,
  private_profile tinyint(1) NOT NULL DEFAULT '0',
  business_id bigint unsigned NOT NULL DEFAULT '0',
  two_factor_requirement_state tinyint NOT NULL DEFAULT '0',
  display_login varchar(40) COLLATE utf8mb3_general_ci NOT NULL,
  archived_at datetime(6) DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY index_users_on_login (login),
  UNIQUE KEY index_on_display_login_and_business_id (display_login,business_id),
  UNIQUE KEY index_users_on_analytics_tracking_id (analytics_tracking_id),
  KEY index_users_on_gh_role (gh_role),
  KEY index_users_on_type (type),
  KEY index_users_on_last_ip (last_ip),
  KEY index_users_on_plan_and_billing_type_and_type (plan,billing_type,type),
  KEY index_users_on_updated_at (updated_at),
  KEY index_users_on_suspended_at (suspended_at),
  KEY index_users_on_created_at (created_at),
  KEY index_users_on_billed_on_and_plan_duration_and_plan_and_disabled (billed_on,plan_duration,plan,disabled),
  KEY index_users_on_organization_billing_email (organization_billing_email),
  KEY index_users_on_gravatar_email (gravatar_email),
  KEY index_users_on_migration_id (migration_id),
  KEY index_users_on_source_login (source_login),
  KEY index_users_on_pinned_api_version (pinned_api_version),
  KEY index_users_on_spammy_and_updated_at (spammy,updated_at),
  KEY index_users_on_login_and_spammy (login,spammy),
  KEY index_users_on_two_factor_requirement_state (two_factor_requirement_state)
) ENGINE=InnoDB;
DROP TABLE IF EXISTS repositories;
CREATE TABLE repositories (
  id bigint unsigned NOT NULL AUTO_INCREMENT,
  name varchar(100) DEFAULT NULL,
  owner_id bigint unsigned NOT NULL,
  parent_id bigint unsigned DEFAULT NULL,
  sandbox tinyint(1) DEFAULT NULL,
  updated_at datetime DEFAULT NULL,
  created_at datetime DEFAULT NULL,
  public tinyint(1) DEFAULT '1',
  description mediumblob,
  homepage varchar(255) DEFAULT NULL,
  source_id bigint unsigned DEFAULT NULL,
  public_push tinyint(1) DEFAULT NULL,
  disk_usage int DEFAULT '0',
  locked tinyint(1) DEFAULT '0',
  pushed_at datetime DEFAULT NULL,
  watcher_count int DEFAULT '0',
  public_fork_count int NOT NULL DEFAULT '1',
  primary_language_name_id bigint unsigned DEFAULT NULL,
  has_issues tinyint(1) DEFAULT '1',
  has_wiki tinyint(1) DEFAULT '1',
  has_downloads tinyint(1) DEFAULT '1',
  raw_data blob,
  organization_id bigint unsigned DEFAULT NULL,
  disabled_at datetime DEFAULT NULL,
  disabled_by int DEFAULT NULL,
  disabling_reason varchar(30) DEFAULT NULL,
  health_status varchar(30) DEFAULT NULL,
  pushed_at_usec int DEFAULT NULL,
  active tinyint(1) DEFAULT '1',
  reflog_sync_enabled tinyint(1) DEFAULT '0',
  made_public_at datetime DEFAULT NULL,
  user_hidden tinyint NOT NULL DEFAULT '0',
  maintained tinyint(1) NOT NULL DEFAULT '1',
  template tinyint(1) NOT NULL DEFAULT '0',
  owner_login varchar(40) DEFAULT NULL,
  world_writable_wiki tinyint(1) NOT NULL DEFAULT '0',
  refset_updated_at datetime(6) DEFAULT NULL COMMENT 'The last time a ref was created or deleted on this repository',
  disabling_detail varchar(255) DEFAULT NULL,
  archived_at datetime(6) DEFAULT NULL,
  deleted_at datetime(6) DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY index_repositories_on_owner_id_and_name_and_active (owner_id,name,active),
  KEY index_repositories_on_public_and_watcher_count (public,watcher_count),
  KEY index_repositories_on_primary_language_name_id_and_public (primary_language_name_id,public),
  KEY index_repositories_on_created_at (created_at),
  KEY index_repositories_on_disabled_at (disabled_at),
  KEY index_repositories_on_owner_id_and_pushed_at (owner_id,pushed_at),
  KEY index_repositories_on_owner_id_and_made_public_at (owner_id,made_public_at),
  KEY index_repositories_on_user_hidden_and_owner_id (user_hidden,owner_id),
  KEY index_repositories_on_watcher_count_and_created_at_and_pushed_at (watcher_count,created_at,pushed_at),
  KEY index_repositories_on_active_and_updated_at (active,updated_at),
  KEY index_repositories_on_owner_and_parent_and_public_and_source_id (owner_id,parent_id,public,source_id),
  KEY index_on_public_and_primary_language_name_id_and_parent_id (public,primary_language_name_id,parent_id),
  KEY index_repositories_on_template_and_active_and_owner_id (template,active,owner_id),
  KEY index_repositories_on_owner_login_and_name_and_active (owner_login,name,active),
  KEY owner_and_org_and_name_and_active_and_public_and_disabled_at (owner_id,organization_id,name,active,public,disabled_at),
  KEY index_repositories_on_owner_id_and_updated_at (owner_id,updated_at),
  KEY index_repos_on_owner_id_public_active_primary_lang_name_id (owner_id,public,active,primary_language_name_id),
  KEY index_repos_on_organization_id_active_public_and_parent_id (organization_id,active,public,parent_id),
  KEY index_repositories_on_source_id_and_owner_id_and_active (source_id,owner_id,active),
  KEY index_repositories_on_source_id_organization_id_and_parent_id (source_id,organization_id,parent_id),
  KEY index_repositories_on_parent_id_and_active (parent_id,active),
  KEY index_repositories_on_owner_id_and_active_and_locked (owner_id,active,locked)
) ENGINE=InnoDB;
DROP TABLE IF EXISTS configuration_entries;
CREATE TABLE configuration_entries (
  id bigint unsigned NOT NULL AUTO_INCREMENT,
  target_id bigint unsigned NOT NULL,
  target_type varchar(30) NOT NULL,
  updater_id bigint unsigned NOT NULL,
  name varchar(80) NOT NULL,
  value varchar(255) NOT NULL,
  final tinyint(1) NOT NULL DEFAULT '0',
  created_at datetime NOT NULL,
  updated_at datetime NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY index_configuration_entries_on_target_and_name (target_id,target_type,name),
  KEY index_on_target_type_and_target_id_and_name_and_value_and_final (target_type,target_id,name,value,final),
  KEY index_configuration_entries_on_name_and_target_type_and_value (name,target_type,value)
) ENGINE=InnoDB;
`)
		require.NoError(t, err)
	}
}

func must[T any](t *testing.T) func(v T, err error) T {
	t.Helper()
	return func(v T, err error) T {
		require.NoError(t, err)
		return v
	}
}

func TestEnterpriseMigrations(t *testing.T) {
	logger, err := log.NewFromEnv(log.WithJSONConsole())
	require.NoError(t, err)
	ctx := fromctx.Logger.With(t.Context(), logger)

	cfg := dbtest.Config()
	cfg.MultiStatements = true
	// choose a database that will always exist first, so we can run the drop/create commands
	cfg.DBName = "sys"

	createDatabase(t, cfg)

	// switch to the newly minted database
	cfg.DBName = "turboghas_enterprise_test"

	db, err := sql.Open("mysql", cfg.FormatDSN())
	require.NoError(t, err)

	t.Cleanup(func() {
		require.NoError(t, db.Close())
	})

	const batches = 10
	const size = 1000
	then := time.Now()
	t.Logf("inserting %d repositories/users in batches of %d", batches*size, size)

	for i := 0; i < batches; i++ {
		args := make([]sqlh.Expr, size)
		for j := range args {
			args[j] = sqlh.SQL(`(?, ?, NOW(), NOW(), NOW())`, 1+i*size+j, 1+i*size+j)
		}
		_, err := sqlh.SQL(`INSERT INTO ghas_repository_contributions (repository_id, user_id, pushed_date, created_at, updated_at) VALUES ?`, sqlh.In(args)).Exec(db)
		require.NoError(t, err)
	}

	for i := 0; i < batches; i++ {
		args := make([]sqlh.Expr, size)
		for j := range args {
			args[j] = sqlh.SQL(`(?, ?)`, fmt.Sprintf("user-%d", 1+i*size+j), fmt.Sprintf("user-%d", 1+i*size+j))
		}
		_, err := sqlh.SQL(`INSERT INTO users (login, display_login) VALUES ?`, sqlh.In(args)).Exec(db)
		require.NoError(t, err)
	}

	for i := 0; i < batches; i++ {
		args := make([]sqlh.Expr, size)
		for j := range args {
			args[j] = sqlh.SQL(`(?, ?)`, 1+i*size+j, fmt.Sprintf("repo-%d", 1+i*size+j))
		}
		_, err := sqlh.SQL(`INSERT INTO repositories (owner_id, name) VALUES ?`, sqlh.In(args)).Exec(db)
		require.NoError(t, err)
	}

	for i := 0; i < batches; i++ {
		args := make([]sqlh.Expr, size)
		for j := range args {
			args[j] = sqlh.SQL(`(?, ?, 'Repository', 'advanced_security.user_enabled', 'true', NOW(), NOW())`, 1+i*size+j, 1+i*size+j)
		}
		_, err := sqlh.SQL(`INSERT INTO configuration_entries (updater_id, target_id, target_type, name, value, created_at, updated_at) VALUES ?`, sqlh.In(args)).Exec(db)
		require.NoError(t, err)
	}

	t.Logf("took %s, starting migrations", time.Since(then))

	m, err := migrations.New(ctx, must[database.Driver](t)(migrations.Driver(db)), must[source.Driver](t)(migrations.Source()))

	require.NoError(t, err)
	require.NoError(t, m.Up())

	_, file, _, _ := runtime.Caller(0)
	dir := filepath.Join(filepath.Dir(file), "..")

	ignore := fmt.Sprintf(`(%s|configuration_entries|tg_migrations|repositories|users|ghas_repository_contributions|tg_meter_emissions)`, regexp.QuoteMeta(migrations.Table))

	cmd := exec.Command("script/dev-run", "bash", "-c",
		fmt.Sprintf(`cd schemas && skeema diff --allow-unsafe --ignore-table %q skeema-diff-test`, ignore),
	)

	cmd.Dir = dir
	output, err := cmd.CombinedOutput()

	require.NoError(t, err, string(output))

	require.Equal(t, batches*size, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_repositories`)))
	require.Equal(t, batches*size, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_users`)))
	require.Equal(t, batches*size, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_purchasers`)))

	d := dbtest.Data(db)

	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_entities WHERE entity_id = 1 AND entity_type = 'Business'`)))

	require.NoError(t, d.UpsertPurchaser(ctx, data.UpsertPurchaserArgs{
		OwnerID:    1,
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityID:   1,
	}))

	require.False(t, must[bool](t)(d.HasContributorsCache(ctx, 1, nil)))

	require.NoError(t, d.UpsertEntity(ctx, data.UpsertEntityArgs{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityID:   1,
		UserIDs:    []uint64{},
	}))

	// if we only care the record exists, it now does
	require.True(t, must[bool](t)(d.HasContributorsCache(ctx, 1, nil)))
	var zero time.Time
	// same as above
	require.True(t, must[bool](t)(d.HasContributorsCache(ctx, 1, &zero)))

	// a user was created after the contributors cache was last updated so the cache is not valid
	future := time.Now().Add(2 * time.Hour)
	require.False(t, must[bool](t)(d.HasContributorsCache(ctx, 1, &future)))

	// a user was created before the contributors cache was last updated so the cache is still valid
	past := time.Now().Add(-2 * time.Hour)
	require.True(t, must[bool](t)(d.HasContributorsCache(ctx, 1, &past)))
}
