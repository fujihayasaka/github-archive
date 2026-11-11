# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class Domain
    class Configurations < GH::Domain::Base
      # Enqueues application of a SecurityConfiguration to a single repository.
      #
      # Optional kwargs default to `nil` and are forwarded to the job only
      # when explicitly supplied:
      #
      #   - `override_params: nil` (default)       -> kwarg omitted from payload
      #   - `override_params: {}`                  -> empty hash forwarded to job
      #   - `reason: nil` (default)                -> kwarg omitted from payload
      #   - `reason: :repo_creation`               -> symbol forwarded to job
      #   - `prevent_additional_sku_usage: nil`    -> kwarg omitted from payload
      #   - `prevent_additional_sku_usage: []`     -> treated as omitted
      #   - `prevent_additional_sku_usage: [SKU]`  -> array forwarded to job
      #
      # When the SECURITY_CONFIGURATION_ATTACHMENT_ROWS feature flag is enabled
      # for the repository's owner (organizations only), this method also creates
      # a `SecurityConfigurationAttachment` row in `:pending` state and forwards
      # the row's id to the job as `attachment_id`. When the flag is disabled,
      # no row is created and `attachment_id` is omitted from the enqueued
      # payload, preserving byte-for-byte parity with the pre-flag behavior.
      #
      # The attachment row is created and the job is enqueued without
      # transactional coupling: if `perform_later` raises after the row is
      # created, the row is left in `:pending` and will be reaped by future
      # cleanup. We accept this orphan-row risk in exchange for a simpler
      # call site.
      #
      # This asymmetry (nil is omitted, {} is forwarded) preserves the enqueued
      # job payload shape of the pre-refactor call sites, some of which
      # explicitly passed `{}` for `override_params` and expected it to reach
      # the job.
      sig do
        params(
          actor_id: Integer,
          repository: Repositories::IRepository,
          security_configuration_id: Integer,
          override_params: T.nilable(T::Hash[Symbol, String]),
          reason: T.nilable(Symbol),
          prevent_additional_sku_usage: T.nilable(T::Array[GitHub::Turboghas::SKU]),
        ).void
      end
      def enqueue_attachment(
        actor_id:,
        repository:,
        security_configuration_id:,
        override_params: nil,
        reason: nil,
        prevent_additional_sku_usage: nil
      )
        repository_id = T.must(repository.id)
        kwargs = {
          actor_id:,
          repository_id:,
          security_configuration_id:,
          override_params:,
          reason:,
          prevent_additional_sku_usage: prevent_additional_sku_usage.presence,
        }.compact

        if attachment_rows_enabled_for_owner?(repository.owner)
          kwargs[:attachment_id] = create_pending_attachment(actor_id:, repository:, security_configuration_id:).id
        end

        ApplySecurityConfigurationToRepositoryJob.perform_later(**kwargs)
      end

      # Enqueues an organization-level bulk attachment of a SecurityConfiguration.
      # The single entry point for the org-level bulk-apply / -detach / -update
      # background flow.
      #
      # When the SECURITY_CONFIGURATION_BULK_ATTACHMENT_ROWS feature flag is
      # enabled for the organization, this method also creates a
      # `SecurityConfigurationBulkAttachment` row in `:ready` state and
      # forwards its id to the job as `bulk_attachment_id`. When the flag is
      # disabled, or row creation is skipped (e.g. `:detach`, which has no
      # `security_configuration_id` to snapshot), no row is created and
      # `bulk_attachment_id` is forwarded as `nil`.
      #
      # The bulk attachment row is created and the job is enqueued without
      # transactional coupling: if `perform_later` raises after the row is
      # created, the row is left in `:ready` and will be reaped by future
      # cleanup. We accept this orphan-row risk in exchange for a simpler
      # call site.
      sig do
        params(
          security_configuration_id: T.nilable(Integer),
          organization: Organization,
          actor_id: Integer,
          action: Symbol,
          repositories: T.nilable(SecurityProductsEnablement::RepositorySelection),
          repository_query: T.nilable(String),
          override_existing_config: T::Boolean,
          user_session_id: T.nilable(Integer),
          options: T::Hash[Symbol, T.untyped],
        ).void
      end
      def enqueue_bulk_attachment(
        security_configuration_id:,
        organization:,
        actor_id:,
        action:,
        repositories: nil,
        repository_query: nil,
        override_existing_config: false,
        user_session_id: nil,
        options: {}
      )
        bulk_attachment = if bulk_attachment_rows_enabled_for_owner?(organization) && security_configuration_id
          create_ready_bulk_attachment(
            security_configuration_id:,
            organization:,
            actor_id:,
            repositories:,
            repository_query:,
            options:,
          )
        end

        OrganizationSecurityConfigurationJob.perform_later(
          security_configuration_id:,
          organization_id: organization.id,
          actor_id:,
          action:,
          repositories:,
          repository_query:,
          override_existing_config:,
          user_session_id:,
          options:,
          bulk_attachment_id: bulk_attachment&.id,
        )
      end

      # Synchronously applies a SecurityConfiguration's feature settings to a
      # single Repository. Loads the underlying records from the supplied IDs,
      # validates preconditions, and returns a Result indicating whether the
      # attachment succeeded and, if not, why.
      #
      # This method does NOT track job progress \u2014 callers that need progress
      # tracking are responsible for managing it themselves.
      #
      # Note: expected attachment failures (e.g. license/SKU validation, service
      # manager toggle errors) are returned as a failed Result. Precondition
      # failures (missing/deleted records, owner mismatches) and unexpected
      # errors (e.g. database errors from `update!`) are raised as
      # `ConfigurationAttacher::Error` subclasses so callers can apply their
      # own retry/discard semantics.
      #
      # When `attachment_id:` is supplied and the feature flag is enabled for
      # the repository's owner, this method transitions the attachment row's
      # state through `:attaching` and then to `:attached` (on success) or
      # `:failed` (on either an Error result or an unhandled exception). Rows
      # already in a terminal state are left alone (no-op on retry).
      #
      # See:
      # - https://github.com/github/security-products-enablement/issues/2797
      sig do
        params(
          actor_id: Integer,
          repository_id: Integer,
          security_configuration_id: Integer,
          service_manager_overrides: T::Hash[Symbol, String],
          reason: T.nilable(Symbol),
          disallowed_skus: T.nilable(T::Array[GitHub::Turboghas::SKU]),
          instrumentation_namespace: T.nilable(String),
          attachment_id: T.nilable(Integer),
        ).returns(SecurityProductsEnablement::ConfigurationAttacher::Result)
      end
      def attach_to_repository(
        actor_id:,
        repository_id:,
        security_configuration_id:,
        service_manager_overrides: {},
        reason: nil,
        disallowed_skus: nil,
        instrumentation_namespace: nil,
        attachment_id: nil
      )
        with_attachment_tracking(
          attachment_id:,
          repository_id:,
          security_configuration_id:,
        ) do
          attacher_kwargs = {
            actor_id:,
            repository_id:,
            security_configuration_id:,
            service_manager_overrides:,
            reason:,
            disallowed_skus:,
          }
          attacher_kwargs[:instrumentation_namespace] = instrumentation_namespace if instrumentation_namespace

          SecurityProductsEnablement::ConfigurationAttacher.new(**attacher_kwargs).attach!
        end
      end

      private

      sig { params(owner: T.nilable(Users::IUser)).returns(T::Boolean) }
      def attachment_rows_enabled_for_owner?(owner)
        return false unless owner&.organization?

        FeatureFlag.vexi.enabled?(
          SecurityProductsEnablement::FeatureFlags::SECURITY_CONFIGURATION_ATTACHMENT_ROWS,
          owner,
          default: false,
        )
      end

      sig do
        params(
          actor_id: Integer,
          repository: Repositories::IRepository,
          security_configuration_id: Integer,
        ).returns(SecurityProductsEnablement::SecurityConfigurationAttachment)
      end
      def create_pending_attachment(actor_id:, repository:, security_configuration_id:)
        owner = repository.owner
        raise ArgumentError, "expected repository owner to be a User when attachment rows are enabled" unless owner.is_a?(User)

        security_configuration = SecurityConfiguration.find(security_configuration_id)

        ActiveRecord::Base.connected_to(role: :writing) do
          SecurityProductsEnablement::SecurityConfigurationAttachment.create!(
            security_configuration:,
            security_configuration_version: security_configuration.version,
            owner:,
            actor_id:,
            business: owner.business,
            repository:,
            attachment_options: {},
            state: :pending,
          )
        end
      end

      sig do
        params(
          attachment_id: T.nilable(Integer),
          repository_id: Integer,
          security_configuration_id: Integer,
          block: T.proc.returns(SecurityProductsEnablement::ConfigurationAttacher::Result),
        ).returns(SecurityProductsEnablement::ConfigurationAttacher::Result)
      end
      def with_attachment_tracking(attachment_id:, repository_id:, security_configuration_id:, &block)
        return yield if attachment_id.nil?

        attachment = find_tracked_attachment(
          attachment_id:,
          repository_id:,
          security_configuration_id:,
        )
        # Only `:pending` rows participate in tracking. Rows already in
        # `:attaching` (concurrent retry), `:attached`, or `:failed` bypass
        # state transitions and yield directly.
        return yield if attachment.nil? || !attachment.pending?

        run_with_attachment_tracking(attachment, &block)
      end

      sig do
        params(
          attachment: SecurityProductsEnablement::SecurityConfigurationAttachment,
          block: T.proc.returns(SecurityProductsEnablement::ConfigurationAttacher::Result),
        ).returns(SecurityProductsEnablement::ConfigurationAttacher::Result)
      end
      def run_with_attachment_tracking(attachment, &block)
        attachment.update!(state: :attaching)
        result = yield
        # `update_columns` skips validations so the terminal write succeeds
        # even when the wrapped failure was itself a validation error.
        attachment.update_columns(state: result.ok? ? :attached : :failed, updated_at: Time.current)
        result
      rescue StandardError => error
        GitHub.logger.error(
          "security_products_enablement.configurations.run_with_attachment_tracking.error",
          "code.namespace" => "SecurityProductsEnablement::Domain::Configurations",
          "code.function" => "run_with_attachment_tracking",
          "gh.security_configuration.attachment.id" => attachment.id,
          "gh.repo.id" => attachment.repository_id,
          "gh.security_configuration.id" => attachment.security_configuration_id,
          "error.class" => error.class.name,
          "error.message" => error.message,
        )
        attachment.update_columns(state: :failed, updated_at: Time.current)
        raise
      end

      # Reads from the writer: the row was just created on the writer in
      # `create_pending_attachment` and may not have replicated yet.
      sig do
        params(
          attachment_id: Integer,
          repository_id: Integer,
          security_configuration_id: Integer,
        ).returns(T.nilable(SecurityProductsEnablement::SecurityConfigurationAttachment))
      end
      def find_tracked_attachment(attachment_id:, repository_id:, security_configuration_id:)
        ActiveRecord::Base.connected_to(role: :writing) do
          SecurityProductsEnablement::SecurityConfigurationAttachment.find_by(
            id: attachment_id,
            repository_id:,
            security_configuration_id:,
          )
        end
      end

      # Tagged representations of a bulk attachment's repository scope. Each
      # variant serializes via `#to_h` to the on-disk JSON shape stored in
      # `SecurityConfigurationBulkAttachment#repository_selection`.
      class RepositorySelectionAll < T::Struct
        # Serializes to the on-disk JSON shape stored in `repository_selection`.
        sig { returns(T::Hash[String, T.untyped]) }
        def to_h
          { "type" => "all" }
        end
      end

      class RepositorySelectionSelected < T::Struct
        const :ids, T::Array[Integer]

        # Serializes to the on-disk JSON shape stored in `repository_selection`.
        sig { returns(T::Hash[String, T.untyped]) }
        def to_h
          { "type" => "selected", "ids" => ids }
        end
      end

      class RepositorySelectionQuery < T::Struct
        const :query, String

        # Serializes to the on-disk JSON shape stored in `repository_selection`.
        sig { returns(T::Hash[String, T.untyped]) }
        def to_h
          { "type" => "query", "query" => query }
        end
      end

      class RepositorySelectionNone < T::Struct
        # Serializes to the on-disk JSON shape stored in `repository_selection`.
        sig { returns(T::Hash[String, T.untyped]) }
        def to_h
          { "type" => "none" }
        end
      end

      RepositorySelectionVariant = T.type_alias do
        T.any(
          RepositorySelectionAll,
          RepositorySelectionSelected,
          RepositorySelectionQuery,
          RepositorySelectionNone,
        )
      end

      sig { params(owner: T.nilable(Users::IUser)).returns(T::Boolean) }
      def bulk_attachment_rows_enabled_for_owner?(owner)
        return false unless owner&.organization?

        FeatureFlag.vexi.enabled?(
          SecurityProductsEnablement::FeatureFlags::SECURITY_CONFIGURATION_BULK_ATTACHMENT_ROWS,
          owner,
          default: false,
        )
      end

      # Creates a `:ready` bulk attachment row. The caller is responsible for
      # the feature-flag check and for short-circuiting on a nil
      # `security_configuration_id` (e.g. `:detach`, which has nothing to
      # snapshot).
      sig do
        params(
          security_configuration_id: Integer,
          organization: Organization,
          actor_id: Integer,
          repositories: T.nilable(SecurityProductsEnablement::RepositorySelection),
          repository_query: T.nilable(String),
          options: T::Hash[Symbol, T.untyped],
        ).returns(SecurityProductsEnablement::SecurityConfigurationBulkAttachment)
      end
      def create_ready_bulk_attachment(security_configuration_id:, organization:, actor_id:, repositories:, repository_query:, options:)
        security_configuration = SecurityConfiguration.find(security_configuration_id)
        actor = User.find(actor_id)

        SecurityProductsEnablement::SecurityConfigurationBulkAttachment.create!(
          security_configuration:,
          security_configuration_version: security_configuration.version,
          owner: organization,
          actor:,
          business: organization.business,
          repository_selection: repository_selection_for(repositories:, repository_query:).to_h,
          attachment_options: options,
          attachment_progress: {},
          state: :ready,
        )
      end

      # Derives the typed representation of the bulk request's repository
      # scope. Falls back to `RepositorySelectionAll` when neither a
      # `RepositorySelection` nor a non-blank query is supplied, matching the
      # implicit scope of the org-update flows that omit both.
      sig do
        params(
          repositories: T.nilable(SecurityProductsEnablement::RepositorySelection),
          repository_query: T.nilable(String),
        ).returns(RepositorySelectionVariant)
      end
      def repository_selection_for(repositories:, repository_query:)
        if repositories
          return RepositorySelectionSelected.new(ids: repositories.selected_repository_ids) if repositories.selected?
          return RepositorySelectionNone.new if repositories.none?

          return RepositorySelectionAll.new
        end

        return RepositorySelectionQuery.new(query: repository_query) if repository_query.present?

        RepositorySelectionAll.new
      end
    end
  end
end
