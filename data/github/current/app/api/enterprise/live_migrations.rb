# typed: true
# frozen_string_literal: true

# Customer-facing API for Enterprise Live Migrations (ELM), exposing migration
# lifecycle endpoints to enterprise customers running the `elm` CLI against their
# GHES appliance. Surface mirrors product-specification.md §4.2.
#
# Single-tenant GHES only: authorizes against GitHub.global_business, which
# exists only in single-tenant mode, so dotcom and multi-tenant Proxima 404.
# (The Proxima/GHEC ELM surface is served by Api::Enterprise::Migrations.)
#
# Authz: each route uses control_access :standard_authorization with the
# read/write_enterprise_live_migrations FGP and forbid: true, matching the
# adjacent Api::Enterprise::Migrations controller. The operator PAT carries the
# admin:enterprise scope (the FGP's oauth_scope); on GHES that scope is held by
# site admins. PAT-only: GitHub Apps and granular-actor delegation are disabled
# (no migrator-role delegation for GA — see github/migrations-vnext#4711).
#
# WARNING: the read/write_enterprise_live_migrations FGPs are SHARED with
# Api::Enterprise::Migrations. Do not re-scope their oauth_scope here.
#
#
#   GET    /enterprise/live-migrations                       list
#   POST   /enterprise/live-migrations                       create
#   GET    /enterprise/live-migrations/:migration_id         status
#   POST   /enterprise/live-migrations/:migration_id/start   start
#   POST   /enterprise/live-migrations/:migration_id/pause   pause
#   POST   /enterprise/live-migrations/:migration_id/resume  resume
#   POST   /enterprise/live-migrations/:migration_id/cancel  cancel (= "abort")
#   POST   /enterprise/live-migrations/:migration_id/cutover cutover
class Api::Enterprise::LiveMigrations < Api::App
  before do
    # Single-tenant GHES only — global_business is nil elsewhere.
    deliver_error! 404 unless GitHub.single_tenant_enterprise?

    # TODO: once app.elm-exporter.enabled is wired
    # into the monolith as GitHub.elm_exporter_enabled?
    # gate on it here.
  end

  # --- Collection routes ---------------------------------------------------

  get "/enterprise/live-migrations", read_from_replicas: true,
      operation_id: "enterprise-admin/live-migration-list" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :read_enterprise_live_migrations,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true

    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-create" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true

    deliver_error! 501, message: "Not implemented"
  end

  # --- Single-migration routes --------------------------------------------

  get "/enterprise/live-migrations/:migration_id", read_from_replicas: true,
      operation_id: "enterprise-admin/live-migration-get" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :read_enterprise_live_migrations,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true

    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations/:migration_id/start", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-start" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true

    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations/:migration_id/pause", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-pause" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true

    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations/:migration_id/resume", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-resume" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true

    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations/:migration_id/cancel", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-cancel" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true

    deliver_error! 501, message: "Not implemented"
  end

  post "/enterprise/live-migrations/:migration_id/cutover", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-cutover" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true

    deliver_error! 501, message: "Not implemented"
  end
end
