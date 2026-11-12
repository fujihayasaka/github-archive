# typed: true
# frozen_string_literal: true

# Customer-facing API for Enterprise Live Migrations (ELM), exposing migration
# lifecycle endpoints to enterprise customers running the `elm` CLI against their
# GHES appliance. Surface mirrors product-specification.md §4.2.
#
# Single-tenant GHES only: gated on GitHub.elm_exporter_enabled?, which requires
# single-tenant mode (GitHub.global_business is nil elsewhere) AND the exporter
# host to be wired in. dotcom and multi-tenant Proxima therefore 404. (The
# Proxima/GHEC ELM surface is served by Api::Enterprise::Migrations.)
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
# Error contract (github/migrations-vnext#4715): every endpoint renders errors
# through #live_migration_error! / #deliver_live_migration_twirp_error! so the
# JSON envelope, `code` vocabulary, and correlation_id stay uniform. The
# upstream-error → wire mapping is the pure #translate_live_migration_twirp_error
# (unit-testable without a request). Upstream message text is never forwarded.
#
# Upstream call failure modes (see the GET list route's rescue):
#   * Mvnd::ElmExporter::TwirpError — the exporter received the request and
#     returned an error. Handled: mapped to our envelope. A present-but-WRONG
#     HMAC key also lands here (server rejects the signature → :unauthenticated /
#     :permission_denied), so wrong-key misconfig is covered by this path.
#   * Mvnd::ElmExporter::HMACNotConfiguredError — the HMAC key is absent/empty, so
#     the request never left the monolith. Intentionally NOT rescued: on an
#     elm_exporter_enabled? appliance this is an operator deployment bug, and a
#     loud 500 is the correct signal. It is a plain StandardError with no
#     #code/#msg, so it must never be routed through the twirp mapper anyway.
#
# enterprise_id is resolved server-side from the PAT context (single-tenant GHES
# = GitHub.global_business) and is never honored from client input;
# #reject_client_enterprise_id! enforces this.
#
# Response conventions (github/migrations-vnext#4717): shaping lives in
# Api::Enterprise::LiveMigrationsSerializer (snake_case keys; enums -> lowercase
# prefix-stripped strings; timestamps -> ISO-8601); request parsing stays here.
# The contract is provisional (flag default-off) — revisit before GA:
#   * Cursor is passed through verbatim (`page_size`/`after` in, `next_cursor`
#     out), not renamed to the GHEC sibling's page_token/nextPageToken.
#   * `status` returns the raw MigrationStatus, so a migration may report a value
#     that isn't an accepted ?status= filter input (no combined-state mapping).
#   * The full MigrationInfo field set is exposed (incl. target_migration_id);
#     adding a field is safe later, removing one post-GA is breaking.
#
#   GET    /enterprise/live-migrations                       list
#   POST   /enterprise/live-migrations                       create
#   GET    /enterprise/live-migrations/:migration_id         status
#   POST   /enterprise/live-migrations/:migration_id/start   start
#   POST   /enterprise/live-migrations/:migration_id/pause   pause
#   POST   /enterprise/live-migrations/:migration_id/resume  resume
#   POST   /enterprise/live-migrations/:migration_id/cancel  cancel (= "abort")
#   POST   /enterprise/live-migrations/:migration_id/cutover cutover
#   POST   /enterprise/live-migrations/:migration_id/revert-cutover revert cutover
class Api::Enterprise::LiveMigrations < Api::App
  before do
    # Single-tenant GHES only — global_business is nil elsewhere.
    deliver_error! 404 unless GitHub.single_tenant_enterprise?

    # elm-exporter must be explicitly enabled via ghe-config. github/enterprise2#50256
    # injects ENTERPRISE_ELM_EXPORTER_ENABLED (from app.elm-exporter.enabled, default
    # off) and the static ELM_EXPORTER_HOST; #elm_exporter_enabled? gates on the
    # former. When disabled, the HAProxy localhost:1738 listener these endpoints rely
    # on does not exist, so 404 rather than attempt an upstream call.
    deliver_error! 404 unless GitHub.elm_exporter_enabled?
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

    # page_size is validated (1..) and clamped to 100 (default 50). `after` is an
    # opaque cursor echoed straight back as next_cursor.
    page_size = parse_page_size!(params[:page_size])

    # --- status filter: customer string -> MigrationStatus enum -------------
    status = parse_status_filter!(params[:status])

    # Only Mvnd::ElmExporter::TwirpError is rescued here. HMACNotConfiguredError
    # is intentionally left to bubble as a 500 (deploy bug; see header). A
    # present-but-wrong key arrives as a TwirpError and is handled below.
    begin
      data = GitHub.elm_exporter_client.list_migrations(
        status: status,
        page_size: page_size,
        after: params[:after].to_s,
      )
    rescue Mvnd::ElmExporter::TwirpError => e
      # Pass the INNER twirp error (responds to #code/#msg), not the wrapper.
      deliver_live_migration_twirp_error!(e.twirp_response.error,
        context_message: "Error listing migrations")
    end

    # Response shaping (incl. next_cursor omission) lives in the serializer.
    deliver_raw(Api::Enterprise::LiveMigrationsSerializer.list_migrations_hash(data), status: 200)
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

    # enterprise_id is resolved server-side, never from client input (#4715). Runs
    # after control_access so forbidden callers get a 403, not a 400.
    data = receive(Hash, required: false) || {}
    reject_client_enterprise_id!(data)

    # Validate the body BEFORE any upstream call: the first bad/missing field halts
    # with a 400 and never reaches elm-exporter (see #parse_create_migration_params!).
    params_for_create = parse_create_migration_params!(data)

    # pat_name is a REFERENCE to a stored, org-scoped credential set — never a raw
    # token. Presence is checked above; credential validity, scopes, and SAML SSO
    # are enforced UPSTREAM by design (only elm-exporter holds the credential) and
    # surface as a TwirpError. The gem is a passthrough, so build the context here.
    migrator_context = Mvnd::ElmExporter::Api::V1::MigratorContext.new(
      system_pat: Mvnd::ElmExporter::Api::V1::SystemPAT.new(
        pat_name: params_for_create.fetch(:pat_name),
      ),
    )

    # Only TwirpError is rescued (mirrors list/start/cancel); it maps through the
    # shared envelope. HMACNotConfiguredError is left to bubble as a loud 500.
    begin
      result = GitHub.elm_exporter_client.create_migration(
        migrator_context: migrator_context,
        source_organization_login: params_for_create.fetch(:source_organization_login),
        source_repository_name: params_for_create.fetch(:source_repository_name),
        target_organization_login: params_for_create.fetch(:target_organization_login),
        target_repository_name: params_for_create.fetch(:target_repository_name),
        migration_target_api_endpoint: params_for_create.fetch(:target_api_endpoint),
        target_visibility: params_for_create[:target_visibility],
      )
    rescue Mvnd::ElmExporter::TwirpError => e
      # Pass the INNER twirp error (responds to #code/#msg), not the wrapper.
      deliver_live_migration_twirp_error!(e.twirp_response.error,
        context_message: "Error creating migration")
    end

    # 201 Created. The serializer emits only { migration_id, expires_at } — no
    # submitted token can be echoed back.
    deliver_raw(Api::Enterprise::LiveMigrationsSerializer.create_migration_hash(result), status: 201)
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

    # GetMigrationStatus returns the combined exporter + target + derived view for a
    # single migration (github/migrations-vnext#4720): migration_info, target_state
    # (incl. repository_summaries / repository_progress AGGREGATE counts),
    # combined_state (user-facing status, display_message, cutover readiness), and
    # messages. Per-node failure detail is deliberately deferred to the resources
    # endpoint (github/migrations-vnext#4711), so only aggregate counts surface here.
    #
    # The server resolves a missing/empty migration_id to InvalidArgument (-> 400)
    # and an unknown id to NotFound (-> 404); the state is read straight through, so
    # we do NOT pre-validate the id here. migration_id is a UUID string and is passed
    # through verbatim (NOT .to_i — unlike the GHEC Api::Enterprise::Migrations sibling,
    # whose ids are integers). Cross-enterprise access is not reachable on
    # single-tenant GHES: the appliance has exactly one enterprise (global_business)
    # and the exporter only knows this appliance's migrations, so the single-tenant
    # gate + control_access above are the whole tenancy boundary (no separate 403).
    #
    # Mirrors the GET list / cancel rescue: only Mvnd::ElmExporter::TwirpError is
    # caught and mapped to our envelope (a present-but-wrong HMAC key surfaces here
    # as :unauthenticated/:permission_denied). HMACNotConfiguredError is intentionally
    # left to bubble as a loud 500 (operator deploy bug; see header). A reachable-but-
    # degraded target (target_unavailable -> combined_state degraded) still returns
    # 200 with that state rather than an error.
    begin
      data = GitHub.elm_exporter_client.get_migration_status(
        migration_id: params[:migration_id],
      )
    rescue Mvnd::ElmExporter::TwirpError => e
      # Pass the INNER twirp error (responds to #code/#msg), not the wrapper.
      deliver_live_migration_twirp_error!(e.twirp_response.error,
        context_message: "Error getting migration status")
    end

    # Response shaping (the deprecated top-level `status` field is dropped; only
    # migration/target_state/combined_state/messages are emitted) lives in the
    # serializer.
    deliver_raw(Api::Enterprise::LiveMigrationsSerializer.migration_status_hash(data), status: 200)
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

    # StartMigration launches backfill + live updates for a migration in a
    # startable state (CREATED/PAUSED/FAILED/VALIDATING; enforced UPSTREAM, so we
    # do NOT pre-validate the transition here). The server rejects an ineligible
    # state with FailedPrecondition (-> 409), a missing/empty id with
    # InvalidArgument (-> 400), and an unknown id with NotFound (-> 404).
    #
    # The wire StartMigrationResponse carries ONLY `success`. The proto source in
    # github/elm-exporter also defines preflight_results, but the generated Ruby
    # client we vendor (elm_exporter 0.2.0.pre.alpha) does not yet include that
    # field, so there is no per-check detail to surface here. A success: false
    # therefore means "preflight blocked the start" with no wire detail; with
    # nothing to return we map it to a generic 422 and let clients re-read GET.
    # (Revisit for a richer body if/when the gem regenerates with preflight_results.)
    #
    # Mirrors the GET list / cancel rescue: only Mvnd::ElmExporter::TwirpError is
    # caught and mapped to our envelope (a present-but-wrong HMAC key surfaces
    # here as :unauthenticated/:permission_denied). HMACNotConfiguredError is
    # intentionally left to bubble as a loud 500 (operator deploy bug; see header).
    # skip_preflight is intentionally NOT exposed to customers (operator/CLI-only).
    begin
      data = GitHub.elm_exporter_client.start_migration(
        migration_id: params[:migration_id],
      )
    rescue Mvnd::ElmExporter::TwirpError => e
      # Pass the INNER twirp error (responds to #code/#msg), not the wrapper.
      deliver_live_migration_twirp_error!(e.twirp_response.error,
        context_message: "Error starting migration")
    end

    # success: false is preflight blocking the start. No detail is available on
    # the wire (see above), so render a generic 422 rather than a misleading
    # success. failed_precondition is the closest `code` to the GET status the
    # client should consult next.
    unless data.success
      live_migration_error!(422, code: "failed_precondition",
        message: "The migration could not be started. Check the migration status for details.")
    end

    # StartMigrationResponse carries only `success`; there is no payload worth
    # returning. Per the cancel route's terminal-action convention, return 204
    # and let clients re-read state via GET rather than echoing a synthesized body.
    deliver_empty(status: 204)
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

    # PauseMigration quiesces source-load work while live event collection and
    # delivery continue. The exporter owns the lifecycle state machine and
    # validates the transition atomically:
    #
    #   in_progress / resuming -> pausing -> paused
    #   pausing                -> retry pause convergence
    #   paused                 -> idempotent success
    #
    # Other states return FailedPrecondition, which the shared error contract
    # maps to 409. A missing/empty migration_id returns InvalidArgument (400), and
    # an unknown migration returns NotFound (404). We deliberately do not perform
    # a separate status lookup here because that would duplicate the exporter's
    # state rules and introduce a time-of-check/time-of-use race.
    #
    # Only TwirpError is rescued. HMACNotConfiguredError is intentionally left to
    # bubble as a loud 500 because it represents an operator deployment error.
    begin
      data = GitHub.elm_exporter_client.pause_migration(
        migration_id: params[:migration_id],
      )
    rescue Mvnd::ElmExporter::TwirpError => e
      # Pass the INNER twirp error (responds to #code/#msg), not the wrapper.
      deliver_live_migration_twirp_error!(e.twirp_response.error,
        context_message: "Error pausing migration")
    end

    # A false response means the exporter accepted the request and began the
    # transition, but the source-load workers did not converge to paused within
    # the acknowledgement window. The durable pausing state remains retryable.
    # Return a generic 422 rather than a misleading 204; clients can inspect the
    # current state through GET and retry the pause operation.
    unless data.success
      live_migration_error!(422, code: "failed_precondition",
        message: "The migration could not be paused. Check the migration status and retry.")
    end

    # PauseMigrationResponse carries only `success`; there is no response payload
    # worth exposing. Return 204 and let clients observe the durable paused state
    # through GET /enterprise/live-migrations/:migration_id.
    deliver_empty(status: 204)
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

    # Resume = StartMigration with skip_preflight: true (github/migrations-vnext#4723).
    # resume_migration is an interim alias for that call on the StartMigration wire
    # path.
    #
    # State transition is enforced UPSTREAM (StartMigration accepts CREATED / PAUSED /
    # FAILED / VALIDATING), so we don't pre-validate: an ineligible state ->
    # FailedPrecondition (409), missing/empty id -> InvalidArgument (400), unknown id
    # -> NotFound (404).
    #
    # Unlike start, there is NO 422 path: preflight is skipped, so `success` is always
    # true on the happy path and nothing is inspected or echoed.
    begin
      GitHub.elm_exporter_client.resume_migration(
        migration_id: params[:migration_id],
      )
    rescue Mvnd::ElmExporter::TwirpError => e
      # Pass the INNER twirp error (responds to #code/#msg), not the wrapper.
      deliver_live_migration_twirp_error!(e.twirp_response.error,
        context_message: "Error resuming migration")
    end

    # resume_migration wraps StartMigrationResponse, which carries only `success`;
    # there is no payload worth returning. Per the start/cancel terminal-action
    # convention, return 204 and let clients re-read state via GET rather than
    # echoing a synthesized status the proto never sent.
    deliver_empty(status: 204)
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

    # Terminal action (github/migrations-vnext#4724): TerminateMigration cancels
    # the migration locally, aborts it on the ELM backend, and removes its work
    # items — there is no recovery. The server enforces the terminal-state rule:
    # an already-terminal migration (completed/failed/cancelled) is rejected with
    # FailedPrecondition, which the error contract maps to 409. A missing/empty
    # migration_id comes back as InvalidArgument (400); an unknown id as NotFound
    # (404). Subsequent GET reflects the terminal state.
    #
    # Mirrors the GET list route's rescue: only Mvnd::ElmExporter::TwirpError is
    # caught and mapped to our envelope (a present-but-wrong HMAC key surfaces
    # here as :unauthenticated/:permission_denied). HMACNotConfiguredError is
    # intentionally left to bubble as a loud 500 (operator deploy bug; see header).
    begin
      GitHub.elm_exporter_client.terminate_migration(
        migration_id: params[:migration_id],
      )
    rescue Mvnd::ElmExporter::TwirpError => e
      # Pass the INNER twirp error (responds to #code/#msg), not the wrapper.
      deliver_live_migration_twirp_error!(e.twirp_response.error,
        context_message: "Error cancelling migration")
    end

    # TerminateMigrationResponse only carries `success`; there is no payload worth
    # returning. Per the GHEC sibling's terminal-action convention
    # (Api::Enterprise::Migrations#abort), return 204 and let clients re-read state
    # via GET rather than echoing a synthesized status the proto never sent.
    deliver_empty(status: 204)
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

    # Async action (github/migrations-vnext#4725): CutoverToDestination locks the
    # source repo, quiesces workers, and queues finalization. Per the
    # start/resume/cancel convention we echo nothing and return 204; clients poll
    # GET :migration_id for the cutover_pending -> cutover_finalizing -> completed
    # progression.
    #
    # State is enforced UPSTREAM (only in_progress may cutover), so we don't
    # pre-validate: ineligible state -> 409, missing id -> 400, unknown id -> 404.
    #
    # Unlike start, `success` is never inspected: the server returns success:true
    # once queued (github/migrations-vnext#4769) and a real refusal arrives as a
    # FailedPrecondition (-> 409), not success:false — so there's no 422 branch.
    #
    # `force` (optional, default false) bypasses the readiness checks so an
    # operator can cut over a migration the server would otherwise report as not
    # ready. It is validated to a boolean before any upstream call.
    #
    # Only a genuinely absent body (nil) counts as omitted. receive_json skips its
    # Hash check for a falsey-but-present body (a literal JSON `false`), so guard
    # nil explicitly rather than `|| {}` — otherwise `false` would masquerade as an
    # empty object and silently initiate cutover, violating the object-only contract.
    body = receive(Hash, required: false)
    force = parse_cutover_force!(body.nil? ? {} : body)

    begin
      GitHub.elm_exporter_client.cutover_to_destination(
        migration_id: params[:migration_id],
        force: force,
      )
    rescue Mvnd::ElmExporter::TwirpError => e
      # Pass the INNER twirp error (responds to #code/#msg), not the wrapper.
      deliver_live_migration_twirp_error!(e.twirp_response.error,
        context_message: "Error initiating cutover")
    end

    # CutoverToDestinationResponse carries only success / message / cutover_pending;
    # there is no payload worth returning. Per the start / resume / cancel
    # convention, return 204 and let clients re-read state via GET rather than
    # echoing a synthesized status.
    deliver_empty(status: 204)
  end

  post "/enterprise/live-migrations/:migration_id/revert-cutover", read_from_replicas: true,
       operation_id: "enterprise-admin/live-migration-revert-cutover" do
    @route_owner = "@github/migrations-vnext"

    control_access :standard_authorization,
      resource: GitHub.global_business,
      permission: :write_enterprise_live_migrations,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true

    begin
      data = GitHub.elm_exporter_client.revert_cutover(
        migration_id: params[:migration_id],
      )
    rescue Mvnd::ElmExporter::TwirpError => e
      deliver_live_migration_twirp_error!(e.twirp_response.error,
        context_message: "Error reverting cutover")
    end

    deliver_raw({
      success: data.success,
      unarchived_source_repository: data.unarchived_source_repository,
      in_progress_cutover_terminated: data.in_progress_cutover_terminated,
      in_progress_migration_terminated: data.in_progress_migration_terminated,
    }, status: 200)
  end

  # ==========================================================================
  # Error contract (github/migrations-vnext#4715)
  # ==========================================================================

  # Stable, machine-readable `code` per upstream TWIRP error code. HTTP status
  # itself is derived from Twirp::ERROR_CODES_TO_HTTP_STATUS (see below) — we do
  # NOT maintain a parallel status table. The `elm` CLI switches on these strings,
  # so renaming a value is a breaking change.
  TWIRP_CODE_STRING = {
    invalid_argument:    "invalid_argument",
    malformed:           "invalid_argument",
    out_of_range:        "invalid_argument",
    unauthenticated:     "unauthenticated",
    permission_denied:   "permission_denied",
    not_found:           "not_found",
    bad_route:           "not_found",
    already_exists:      "conflict",
    aborted:             "conflict",
    failed_precondition: "failed_precondition",
    resource_exhausted:  "rate_limited",
    canceled:            "timeout",
    deadline_exceeded:   "timeout",
    unimplemented:       "not_implemented",
    unavailable:         "unavailable",
    internal:            "internal_error",
    unknown:             "internal_error",
    data_loss:           "internal_error",
  }.freeze
  private_constant :TWIRP_CODE_STRING

  # Our own generic, user-safe message per `code` string. We forward NOTHING from
  # the upstream error (see #deliver_live_migration_twirp_error!), so these are
  # the only messages a customer sees for an upstream failure. Keyed by the
  # `code` string (TWIRP_CODE_STRING's values) so collapsed codes share wording.
  GENERIC_MESSAGE = {
    "invalid_argument"     => "The request was invalid.",
    "unauthenticated"      => "Authentication is required.",
    "permission_denied"    => "You do not have permission to perform this action.",
    "not_found"            => "The requested migration resource was not found.",
    "conflict"             => "The request conflicts with the current state of the migration.",
    "failed_precondition"  => "The migration is not in a valid state for this action.",
    "rate_limited"         => "Rate limit exceeded. Please retry later.",
    "timeout"              => "The migration service did not respond in time. Please retry.",
    "not_implemented"      => "This operation is not yet implemented.",
    "unavailable"          => "The migration service is temporarily unavailable. Please retry later.",
    "unconfigured_secrets" => "The migration service is missing source or target credentials. Ask an organization administrator to configure the required secrets before retrying.",
    "internal_error"       => "The migration service encountered an internal error.",
  }.freeze
  private_constant :GENERIC_MESSAGE

  ERROR_DOC_PATH = "/rest/enterprise-admin/live-migrations"
  private_constant :ERROR_DOC_PATH

  # Signature of an unconfigured-secrets failure hidden inside a generic
  # `unavailable` twirp error: the exporter's kredz credential fetch reports the
  # PAT is missing (see github/migrations-vnext#6140). Matching is intentionally
  # narrow so unrelated `unavailable` errors keep their generic wording.
  UNCONFIGURED_SECRETS_PATTERN = /kredz fetch.*credential not found/mi
  private_constant :UNCONFIGURED_SECRETS_PATTERN

  # ==========================================================================
  # Request parsing (github/migrations-vnext#4717)
  # ==========================================================================

  # Accepted ?status= filter values -> MigrationStatus enum symbol, limited to the
  # seven lifecycle states (product-spec §4.3). Proto-only/combined states
  # (cutover_pending, cutover_finalizing, validating) are intentionally NOT
  # filterable even though a migration may report them. "all" is a sentinel ->
  # INVALID, which the server treats as "every state". Renaming a value is breaking.
  STATUS_FILTER = {
    "created"     => :MIGRATION_STATUS_CREATED,
    "queued"      => :MIGRATION_STATUS_QUEUED,
    "in_progress" => :MIGRATION_STATUS_IN_PROGRESS,
    "paused"      => :MIGRATION_STATUS_PAUSED,
    "completed"   => :MIGRATION_STATUS_COMPLETED,
    "failed"      => :MIGRATION_STATUS_FAILED,
    "terminated"  => :MIGRATION_STATUS_TERMINATED,
  }.freeze
  private_constant :STATUS_FILTER

  # Required string fields on the POST /enterprise/live-migrations body, paired
  # with the customer-facing label used in validation errors. Order is preserved
  # so the FIRST missing field is the one reported (deterministic 400s). These are
  # the proto-aligned snake_case names the serializer emits, NOT the `elm` CLI
  # flag spellings (github/migrations-vnext#4719). Renaming a key is breaking.
  CREATE_REQUIRED_FIELDS = {
    "source_organization_login" => "source_organization_login",
    "source_repository_name"    => "source_repository_name",
    "target_organization_login" => "target_organization_login",
    "target_repository_name"    => "target_repository_name",
    "target_api_endpoint"       => "target_api_endpoint",
    "pat_name"                  => "pat_name",
  }.freeze
  private_constant :CREATE_REQUIRED_FIELDS

  # Accepted target_visibility values -> RepositoryVisibility enum symbol. The
  # customer surface is limited to private/internal per spec §4.5 ("Target
  # visibility must be private or internal"); PUBLIC is intentionally NOT offered
  # (the target does not support public repos). Omitted/blank -> nil, so the gem
  # leaves the field unset and the server applies its INTERNAL default. Renaming a
  # value is breaking.
  VISIBILITY_FILTER = {
    "private"  => :REPOSITORY_VISIBILITY_PRIVATE,
    "internal" => :REPOSITORY_VISIBILITY_INTERNAL,
  }.freeze
  private_constant :VISIBILITY_FILTER

  private

  # Render + halt with the ELM error envelope: the standard GitHub REST body plus
  # `code` and `correlation_id`. Use directly for domain errors raised before any
  # TWIRP call (e.g. enterprise_id_not_allowed).
  def live_migration_error!(status, code:, message:)
    halt deliver_raw(
      {
        message: message,
        documentation_url: GitHub.developer_help_url + ERROR_DOC_PATH,
        status: status.to_s,
        code: code,
        correlation_id: GitHub.context[:request_id],
      },
      status: status,
    )
  end

  # Pure mapping from an upstream elm-exporter error to [status, code, message].
  # No side effects, so it is unit-testable with Twirp::Error.new(:code, "msg").
  # `error` responds to #code (Symbol) and #msg (String). `context_message` is our
  # hand-authored, safe lead; error.msg is intentionally never surfaced (see below).
  def translate_live_migration_twirp_error(error, context_message:)
    # Missing org credentials surface as a generic `unavailable` from the exporter;
    # reclassify into an actionable `unconfigured_secrets` error (github/migrations-vnext#6140).
    if unconfigured_secrets_error?(error)
      generic = GENERIC_MESSAGE.fetch("unconfigured_secrets")
      return [422, "unconfigured_secrets", "#{context_message}: #{generic}"]
    end

    status = Twirp::ERROR_CODES_TO_HTTP_STATUS[error.code] || 500
    # failed_precondition is twirp's 412 by default; here it always denotes an
    # application-state conflict, so map it to 409.
    status = 409 if error.code == :failed_precondition

    code = TWIRP_CODE_STRING.fetch(error.code, "internal_error")
    generic = GENERIC_MESSAGE.fetch(code, "The migration request could not be completed.")

    [status, code, "#{context_message}: #{generic}"]
  end

  # The exporter collapses missing-credential failures into a generic `unavailable`
  # twirp error; the only distinguishing signal is the message text. Detect that
  # narrow shape so we can reclassify it as `unconfigured_secrets`. We inspect
  # error.msg purely to classify — it is still never forwarded to the customer.
  def unconfigured_secrets_error?(error)
    error.code == :unavailable && error.msg.to_s.match?(UNCONFIGURED_SECRETS_PATTERN)
  end

  # Logs the raw upstream error (correlated by request id) and renders the envelope
  # via the pure mapper above. Forward-nothing policy: elm-exporter wraps raw Go
  # errors that can leak internals, so we never return error.msg — only a generic
  # per-code message. May be revisited if the exporter sends a user-safe signal.
  def deliver_live_migration_twirp_error!(error, context_message:)
    GitHub.logger.error("elm customer API upstream error",
      "gh.elm.twirp.code" => error.code.to_s,
      "gh.elm.twirp.msg" => error.msg,
      "gh.request_id" => GitHub.context[:request_id])

    status, code, message = translate_live_migration_twirp_error(error, context_message: context_message)
    live_migration_error!(status, code: code, message: message)
  end

  # enterprise_id is resolved server-side (single-tenant GHES = GitHub.global_business)
  # and must never be honored from client input. Reject any request body that sets it.
  def reject_client_enterprise_id!(data)
    return unless data.is_a?(Hash)
    return unless data.key?("enterprise_id") || data.key?(:enterprise_id)

    live_migration_error!(400, code: "enterprise_id_not_allowed",
      message: "enterprise_id is derived from your token and must not be included in the request.")
  end

  # Validate page_size as a positive integer, then clamp to 1..100 (default 50).
  # Unlike Api::Enterprise::Migrations#list, 0 is rejected, not rewritten to 1.
  def parse_page_size!(raw)
    return 50 if raw.nil?

    unless raw.to_s.match?(/\A\d+\z/) && raw.to_i.positive?
      live_migration_error!(400, code: "invalid_argument",
        message: "page_size must be a positive integer.")
    end

    raw.to_i.clamp(1, 100)
  end

  # Map the customer ?status= string to a MigrationStatus enum symbol.
  #   nil/empty -> nil  (no filter; server defaults to in-progress)
  #   "all"     -> :MIGRATION_STATUS_INVALID  (server lists every state)
  #   unknown   -> 400  (fail loud rather than silently widening the result set)
  def parse_status_filter!(raw)
    return nil if raw.nil? || raw.to_s.empty?
    return :MIGRATION_STATUS_INVALID if raw.to_s.casecmp?("all")

    STATUS_FILTER.fetch(raw.to_s.downcase) do
      live_migration_error!(400, code: "invalid_argument",
        message: "Unknown status filter: #{raw}.")
    end
  end

  # ==========================================================================
  # Cutover request parsing (github/migrations-vnext#4725)
  # ==========================================================================

  # The cutover body is optional; when present, `force` is the only accepted key
  # and must be a real boolean. Absent/nil -> false. Anything else -> 400, so a
  # stray string like "true" can't silently be treated as truthy.
  def parse_cutover_force!(data)
    unless data.is_a?(Hash)
      live_migration_error!(400, code: "invalid_argument",
        message: "A JSON request body is required.")
    end

    force = data.key?("force") ? data["force"] : data[:force]
    return false if force.nil?

    unless force == true || force == false
      live_migration_error!(400, code: "invalid_argument",
        message: "force must be a boolean.")
    end

    force
  end

  # ==========================================================================
  # Create request parsing (github/migrations-vnext#4719)
  # ==========================================================================

  # Validate + normalize the POST body and return a symbol-keyed hash to splat into
  # create_migration. Fail-loud: the first problem halts with a 400 before any
  # upstream call. Returns target_visibility: nil when omitted (server defaults to
  # INTERNAL). enterprise_id is already rejected before this runs.
  def parse_create_migration_params!(data)
    unless data.is_a?(Hash)
      live_migration_error!(400, code: "invalid_argument",
        message: "A JSON request body is required.")
    end

    # Required strings: present, a String, and non-blank once stripped. The first
    # offender (in CREATE_REQUIRED_FIELDS order) determines the message.
    parsed = {}
    CREATE_REQUIRED_FIELDS.each do |key, label|
      value = data[key]
      unless value.is_a?(String) && !value.strip.empty?
        live_migration_error!(400, code: "invalid_argument",
          message: "#{label} is required and must be a non-empty string.")
      end
      parsed[key.to_sym] = value.strip
    end

    # target_api_endpoint must be a valid HTTPS URL (HTTP is rejected at preflight,
    # spec constraint #20). Reuse the already-stripped value.
    parsed[:target_api_endpoint] = parse_target_api_endpoint!(parsed[:target_api_endpoint])

    # target_visibility is optional (private|internal); omitted -> nil so the gem
    # leaves it unset and the server defaults to INTERNAL.
    parsed[:target_visibility] = parse_target_visibility!(data["target_visibility"])

    parsed
  end

  # Validate target_api_endpoint as an absolute HTTPS URL with a host. HTTP and
  # malformed values are rejected here (spec §4.5 network reachability runs only
  # after this passes, upstream). Returns the trimmed URL string.
  def parse_target_api_endpoint!(raw)
    uri =
      begin
        URI.parse(raw)
      rescue URI::InvalidURIError
        nil
      end

    unless uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty?
      live_migration_error!(400, code: "invalid_argument",
        message: "target_api_endpoint must be a valid HTTPS URL.")
    end

    raw
  end

  # Map the customer target_visibility string to a RepositoryVisibility enum symbol.
  #   nil/empty -> nil  (gem leaves it unset; server defaults to INTERNAL)
  #   private/internal -> the matching enum symbol
  #   anything else (incl. "public") -> 400 (the target does not support public)
  def parse_target_visibility!(raw)
    return nil if raw.nil? || raw.to_s.strip.empty?

    VISIBILITY_FILTER.fetch(raw.to_s.strip.downcase) do
      live_migration_error!(400, code: "invalid_argument",
        message: "target_visibility must be one of: private, internal.")
    end
  end
end
