# typed: true
# frozen_string_literal: true

# Customer-facing API for Enterprise Live Migrations (ELM).
#
# This controller exposes migration lifecycle endpoints to enterprise customers
# running the `elm` CLI against their GHES appliance.
#
# Gating follows the pattern established in lib/github/config/migrations_vnext.rb
# (e.g. elm_internal_webhooks_enabled?): enabled on GHES appliances only.
#
# Auth posture status:
#   - Site-admin PAT enforcement: WIRED in this PR via control_access
#     :standard_authorization with read/write_enterprise_live_migrations
#     permissions (mirrors Api::Enterprise::Migrations).
#   - Feature flag gating + multitenant enforcement: deferred to
#     github/migrations-vnext#4714 (batch 11.A.3).
#   - Real lifecycle behavior: deferred to batch 11.B
#     (github/migrations-vnext#4708) when TWIRP wiring to
#     MigrationManagerAPI is added.
#
# All routes return 501 at this stage.
#
# Lifecycle surface mirrors product-specification.md §4.2:
#
#   GET    /enterprise/live-migrations                       list
#   POST   /enterprise/live-migrations                       create
#   GET    /enterprise/live-migrations/:migration_id         status
#   POST   /enterprise/live-migrations/:migration_id/start   start
#   POST   /enterprise/live-migrations/:migration_id/pause   pause
#   POST   /enterprise/live-migrations/:migration_id/resume  resume
#   POST   /enterprise/live-migrations/:migration_id/cancel  cancel (= "abort" in epic #4067)
#   POST   /enterprise/live-migrations/:migration_id/cutover cutover
class Api::Enterprise::LiveMigrations < Api::App
  before do
    deliver_error! 404 unless GitHub.enterprise?
  end

  # --- Collection routes ---------------------------------------------------

  get "/enterprise/live-migrations", read_from_replicas: true,
      operation_id: "enterprise-admin/live-migration-list" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :read_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    # TODO(11.B): TWIRP call to MigrationManagerAPI.ListMigrations
    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-create" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    # TODO(11.B): TWIRP call to MigrationManagerAPI.CreateMigration
    deliver_error! 501, message: "Not implemented"
  end

  # --- Single-migration routes --------------------------------------------

  get "/enterprise/live-migrations/:migration_id", read_from_replicas: true,
      operation_id: "enterprise-admin/live-migration-get" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :read_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    # TODO(11.B): TWIRP call to MigrationManagerAPI.MigrationStatus
    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations/:migration_id/start", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-start" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    # TODO(11.B): TWIRP call to MigrationManagerAPI.StartMigration
    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations/:migration_id/pause", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-pause" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    # TODO(11.B): TWIRP call to MigrationManagerAPI.PauseMigration
    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations/:migration_id/resume", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-resume" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    # TODO(11.B): TWIRP call to MigrationManagerAPI.ResumeMigration
    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations/:migration_id/cancel", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-cancel" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    # TODO(11.B): TWIRP call to MigrationManagerAPI.AbortMigration
    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations/:migration_id/cutover", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-cutover" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    # TODO(11.B): TWIRP call to MigrationManagerAPI.CutoverMigration
    deliver_error! 501, message: "Not implemented"
  end
end
