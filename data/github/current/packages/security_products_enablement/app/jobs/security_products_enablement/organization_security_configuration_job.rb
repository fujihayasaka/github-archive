# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class OrganizationSecurityConfigurationJob < ApplicationJob
    include GitHub::Memoizer
    include SecurityConfigurations::RepositoriesDependency
    include SecurityProductsEnablement::SecretScanningBackfillHelper

    BATCH_SIZE = 100
    VALID_ACTIONS = %i[apply detach update delete update_and_replace_repositories]

    ReposNotFoundError = Class.new(StandardError)
    TooManyRepositoriesError = Class.new(StandardError)

    attr_accessor :enqueued_any_job

    queue_as :security_configurations

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    before_enqueue do |_|
      job_progress_tracker.start
    end

    around_perform do |job, block|
      job.enqueued_any_job = false
      job_progress_tracker.start unless job_progress_tracker.in_progress?
      block.call
    ensure
      job_progress_tracker.clear unless job.enqueued_any_job
    end

    around_perform do |_job, block|
      GitHub.context.push(actor:) do
        Audit.context.push(actor:) do
          block.call
        end
      end
    end

    sig do
      params(
        security_configuration_id: T.nilable(Integer),
        organization_id: Integer,
        actor_id: Integer,
        action: Symbol,
        repository_query: T.nilable(String),
        repositories: T.nilable(RepositorySelection),
        override_existing_config: T::Boolean,
        user_session_id: T.nilable(Integer),
        options: T::Hash[Symbol, T.untyped]
      ).void
    end
    def perform(
      security_configuration_id:,
      organization_id:,
      actor_id:,
      action:,
      repository_query: nil,
      repositories: nil,
      override_existing_config: false,
      user_session_id: nil,
      options: {}
    )
      GitHub.logger.info("Beginning job")

      if !VALID_ACTIONS.include?(action)
        raise ArgumentError, "Invalid action: #{action}"
      end

      if security_configuration.nil? && action != :detach
        GitHub.logger.info("Security configuration not found.")
        return
      end

      organization = self.organization
      if organization.nil?
        GitHub.logger.info("Organization not found.")
        return
      end

      actor = self.actor
      if actor.nil?
        GitHub.logger.info("Actor not found.")
        return
      end

      if action == :update_and_replace_repositories && repositories.nil?
        GitHub.logger.info("Repositories not provided for update_and_replace_repositories action.")
        return
      end

      max_repositories_for_quick_setup = RepositorySelection::MAX_REPOSITORY_IDS_FOR_QUICK_SETUP
      if action == :update_and_replace_repositories && repositories&.selected? && repositories.selected_repository_ids.size > max_repositories_for_quick_setup
        raise TooManyRepositoriesError, "Cannot update and replace more than #{max_repositories_for_quick_setup} repositories at once"
      end

      GH.context.act_as(actor)

      if !options[:default_for_new_public_repos].nil? && !options[:default_for_new_private_repos].nil?
        SecurityConfigurationDefault.create_or_update_defaults(
          target: organization,
          default_for_new_public_repos: ActiveModel::Type::Boolean.new.cast(options[:default_for_new_public_repos]),
          default_for_new_private_repos: ActiveModel::Type::Boolean.new.cast(options[:default_for_new_private_repos]),
          security_configuration: T.must(security_configuration),
        )
      end

      case action
      when :apply
        apply_to_repositories(organization:, actor:, repositories:, repository_query:, override_existing_config:)
      when :detach
        detach_from_repositories(organization:, actor:, repositories:, repository_query:)
      when :update
        update_applied_repositories(publish_backfill_group_request: options[:publish_backfill_group_request])
      when :update_and_replace_repositories
        update_and_replace_repositories(
          organization:,
          actor:,
          repositories: T.must(repositories),
          publish_backfill_group_request: options[:publish_backfill_group_request]
        )
      end

      job_progress_tracker.lock_total_jobs
    end

    sig do
      params(
        organization: Organization,
        actor: User,
        repositories: T.nilable(RepositorySelection),
        repository_query: T.nilable(String),
        override_existing_config: T::Boolean
      ).void
    end
    def apply_to_repositories(organization:, actor:, repositories:, repository_query:, override_existing_config:)
      override_params = {}
      skip_backfill_request = T.must(security_configuration).secret_scanning_enabled?

      # If we're applying a config with secret scanning set as enabled, we want to leverage secret scanning group backfill
      # instead of sending individual backfill requests for each repo.
      if skip_backfill_request
        override_params[:skip_backfill_request] = "1"
      end

      repository_ids = repositories&.selected? ? repositories.selected_repository_ids : []

      if repository_ids.empty? && repository_query.present?
        all_repo_ids_from_search_query = T.let([], T::Array[Integer])
        each_visible_repo_id(organization:, actor:, repository_query:) do |repo_id|
          all_repo_ids_from_search_query << repo_id
        end
        prevent_additional_sku_usage = prevent_additional_sku_usage(organization, all_repo_ids_from_search_query)
      else
        GitHub.logger.info("calculating license using provided repositories")
        prevent_additional_sku_usage = prevent_additional_sku_usage(organization, repository_ids)
      end

      GitHub.logger.info("prevent_additional_sku_usage: #{prevent_additional_sku_usage}")

      parse_repositories(action: :apply, organization:, actor:, repositories:, repository_query:) do |repository_id|
        begin
          repository = Repositories::Public.find_active!(repository_id)
          enqueued_job = T.must(security_configuration).apply_to_repository(
            repository,
            actor:,
            override_existing_config:,
            override_params:,
            prevent_additional_sku_usage: prevent_additional_sku_usage.to_a
          )

          if enqueued_job
            self.enqueued_any_job = true
            job_progress_tracker.increment_jobs
            job_progress_tracker.append_repository_id(repository_id) if skip_backfill_request
          end
        rescue => error
          Failbot.report(error)
        end
      end
    end

    sig do
      params(
        organization: Organization,
        actor: User,
        repositories: T.nilable(RepositorySelection),
        repository_query: T.nilable(String),
      ).void
    end
    def detach_from_repositories(organization:, actor:, repositories:, repository_query:)
      parse_repositories(action: :detach, organization:, actor:, repositories:, repository_query:) do |repository_id|
        repository_security_configuration = RepositorySecurityConfiguration.find_by(repository_id: repository_id)
        next unless repository_security_configuration.present?

        ActiveRecord::Base.connected_to(role: :writing) { repository_security_configuration.destroy }

        # Send front-end update reflecting the new "No configuration" state:
        live_updater.repository_status(repository_id: repository_id)
      end
    end

    sig { params(publish_backfill_group_request: T.nilable(T::Boolean)).void }
    def update_applied_repositories(publish_backfill_group_request: false)
      security_config = T.must(security_configuration)
      query_scope = security_config.repository_security_configurations.applied.where(organization_id: T.must(organization&.id))

      query_scope.find_each(batch_size: BATCH_SIZE) do |repo_config|
        begin
          RepositorySecurityConfiguration.throttle_writes_with_retry { repo_config.updating! }

          ApplySecurityConfigurationToRepositoryJob.perform_later(
            actor_id: T.must(actor&.id),
            repository_id: repo_config.repository_id,
            security_configuration_id: security_config.id,
            override_params: publish_backfill_group_request ? { skip_backfill_request: "1" } : {}
          )

          self.enqueued_any_job = true
          job_progress_tracker.increment_jobs
          job_progress_tracker.append_repository_id(repo_config.repository_id) if publish_backfill_group_request
        rescue => error
          Failbot.report(error)
        end
      end
    end

    sig do
      params(
        organization: Organization,
        actor: User,
        repositories: RepositorySelection,
        publish_backfill_group_request: T.nilable(T::Boolean)
      ).void
    end
    def update_and_replace_repositories(organization:, actor:, repositories:, publish_backfill_group_request: false)
      security_config = T.must(security_configuration)

      # For the "none" case, we want to detach ALL attachments including failed ones.
      # For the "selected" case, we only detach applied (non-failed) attachments that
      # are not in the selection
      if RepositorySelection::Value::None == repositories.value
        all_attached_ids = security_config.repository_security_configurations
          .where(organization_id: organization.id)
          .pluck(:repository_id)

        detach_from_repositories(organization:, actor:, repositories: RepositorySelection.selected(all_attached_ids), repository_query: nil) if all_attached_ids.any?

      elsif RepositorySelection::Value::All == repositories.value
        apply_to_repositories(
          organization:,
          actor:,
          repositories: nil,
          repository_query: "visibility:public,private,internal",
          override_existing_config: true
        )

      elsif RepositorySelection::Value::Selected == repositories.value
        currently_attached_ids = security_config.repository_security_configurations
          .active_for_quick_setup
          .where(organization_id: organization.id)
          .pluck(:repository_id)

        repo_ids_to_detach = currently_attached_ids - repositories.selected_repository_ids
        new_repo_ids = repositories.selected_repository_ids - currently_attached_ids

        detach_from_repositories(organization:, actor:, repositories: RepositorySelection.selected(repo_ids_to_detach), repository_query: nil) if repo_ids_to_detach.any?
        update_applied_repositories(publish_backfill_group_request:)
        apply_to_repositories(
          organization:,
          actor:,
          repositories: RepositorySelection.selected(new_repo_ids),
          repository_query: nil,
          override_existing_config: true
        ) if new_repo_ids.any?

      else
        GitHub.logger.info("No action to take for state: #{repositories.value.serialize}")
      end
    end

    sig do
      params(
        action: Symbol,
        organization: Organization,
        actor: User,
        repositories: T.nilable(RepositorySelection),
        repository_query: T.nilable(String),
        blk: T.proc.params(repository_id: Integer).void
      ).void
    end
    def parse_repositories(action:, organization:, actor:, repositories:, repository_query:, &blk)
      organization = T.must(organization)
      repository_ids = repositories&.selected? ? repositories.selected_repository_ids : []

      if repository_query.present? && repository_ids.blank?
        each_visible_repo_id(organization:, actor:, repository_query:, &blk)
      else
        query_scope = organization.repositories
        query_scope = query_scope.where(id: repository_ids) if repository_ids.present?

        query_scope.in_batches(of: BATCH_SIZE) do |relation|
          relation.pluck(:id).each(&blk)
        end
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      repositories_param = arguments.dig(0, :repositories)
      repositories_value = repositories_param&.value&.serialize

      tags = {
        "gh.org.id": organization_id,
        "gh.org.login": organization&.display_login,
        "gh.enduser.id": arguments.dig(0, :actor_id),
        "gh.enduser.login": actor&.display_login,
        "gh.security_configuration.id": arguments.dig(0, :security_configuration_id),
        "gh.security_configuration.action": arguments.dig(0, :action),
        "gh.security_configuration.user_session_id": arguments.dig(0, :user_session_id),
        "gh.security_configuration.org_job.repository_query": arguments.dig(0, :repository_query),
        "gh.security_configuration.org_job.override_existing_config": arguments.dig(0, :override_existing_config),
        "gh.security_configuration.org_job.options": arguments.dig(0, :options),
        "gh.security_configuration.org_job.repositories": repositories_value
      }

      super.merge(tags)
    end

    sig { returns T.nilable(SecurityConfiguration) }
    memoize def security_configuration
      security_configuration_id = arguments.dig(0, :security_configuration_id)
      return if security_configuration_id.nil?
      SecurityConfiguration.find_by(id: security_configuration_id)
    end

    sig { returns(Integer) }
    memoize def organization_id
      arguments.dig(0, :organization_id)
    end

    sig { returns(T.nilable(Organization)) }
    memoize def organization
      return if organization_id.nil?
      Organization.find_by(id: organization_id)
    end

    sig { returns(T.nilable(User)) }
    memoize def actor
      actor_id = arguments.dig(0, :actor_id)
      return if actor_id.nil?
      User.find_by(id: actor_id)
    end

    sig { returns(T.nilable(UserSession)) }
    memoize def user_session
      user_session_id = arguments.dig(0, :user_session_id)
      return if user_session_id.nil?
      UserSession.find_by(id: user_session_id)
    end

    sig { returns(SecurityProductsEnablement::JobProgressTracker) }
    memoize def job_progress_tracker
      business_id = organization&.business&.id
      tracker = SecurityProductsEnablement::JobProgressTracker.new(organization_id, business_id:)

      if security_configuration && organization
        tracker.on_finish do |repository_ids|
          publish_secret_scanning_backfill(
            security_configuration: T.must(security_configuration),
            owner: T.must(organization),
            repository_ids:
          )
        end
      end

      tracker
    end

    sig do
      params(
      organization: Organization,
      repository_ids: T::Array[Integer]
      ).returns(T::Set[GitHub::Turboghas::SKU])
    end
    def prevent_additional_sku_usage(organization, repository_ids)
      result = T.let(Set.new, T::Set[GitHub::Turboghas::SKU])

      if organization.advanced_security_products_bundled?
        result.add(GitHub::Turboghas::SKU::Bundled) if license_limit_exceeded?(organization.advanced_security_license, repository_ids)
      else
        result.add(GitHub::Turboghas::SKU::CodeSecurity) if license_limit_exceeded?(organization.code_security, repository_ids)
        result.add(GitHub::Turboghas::SKU::SecretSecurity) if license_limit_exceeded?(organization.secret_protection, repository_ids)
      end

      result
    end

    sig do
      params(
        sku: AdvancedSecurityLicense,
        repository_ids: T::Array[Integer]
      ).returns(T::Boolean)
    end
    def license_limit_exceeded?(sku, repository_ids)
      org = T.must_because(organization) { "organization presence is validated before this method is called" }

      return false unless sku.purchased?
      return false if sku.unlimited_seats?
      return true if sku.allowance_exceeded?

      if repository_ids.empty?
        sku.enabling_for_all_repos_would_exceed_seat_allowance?
      else
        necessary_seats = sku.seat_usage_increase_if_enabled_for_repos(repository_ids)
        necessary_seats > sku.remaining_seats
      end

    rescue => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      false # fail open
    end

    sig { returns(SecurityProductsEnablement::LiveUpdatePublisher) }
    memoize def live_updater
      org = T.must_because(organization) { "organization presence is validated before this method is called" }
      SecurityProductsEnablement::LiveUpdatePublisher.new(org)
    end

    VALID_VISIBILITIES = T.let(%w[internal private public].freeze, T::Array[String])
    VISIBILITY_QUERY_PATTERN = T.let(/\Avisibility:([a-z,]+)\z/i, Regexp)

    # Yields repository IDs for the given query, using MySQL scopes for visibility-only
    # queries and falling back to ES for richer queries (e.g. "configuration:None").
    # The MySQL path avoids QueryRejectionError failures for bot actors whose GitHub App
    # installation context isn't hydrated in background jobs (see security-products-enablement#2481).
    sig do
      params(
        organization: Organization,
        actor: User,
        repository_query: String,
        blk: T.proc.params(repository_id: Integer).void
      ).void
    end
    def each_visible_repo_id(organization:, actor:, repository_query:, &blk)
      visibility_scope = resolve_visibility_scope(repository_query, organization)
      if visibility_scope
        GitHub.logger.info("resolving repositories using database visibility scope")
        visibility_scope.in_batches(of: BATCH_SIZE) do |relation|
          relation.pluck(:id).each(&blk)
        end
      else
        GitHub.logger.info("resolving repositories using search query")
        find_repo_ids_by_query(
          query: repository_query,
          organization:,
          actor:,
          user_session:,
          cap_filter: nil,
          use_cursor_pagination: true,
          &blk
        )
      end
    end

    # Resolves visibility-only queries directly via MySQL scopes, bypassing ES.
    # Case-insensitive; invalid visibility values are silently ignored (matching
    # github.com search behavior). Returns nil for non-visibility queries.
    #
    # Per-actor authorization is intentionally skipped — callers are org-level API
    # endpoints that validate org admin permissions before enqueueing (see PR #415378).
    sig { params(query: String, organization: Organization).returns(T.nilable(ActiveRecord::Relation)) }
    def resolve_visibility_scope(query, organization)
      match = query.match(VISIBILITY_QUERY_PATTERN)
      return nil unless match

      visibilities = VALID_VISIBILITIES & T.must(match[1]).downcase.split(",")
      return nil if visibilities.empty?

      repos = organization.repositories
      return repos if visibilities == VALID_VISIBILITIES

      scopes = visibilities.map do |visibility|
        case visibility
        when "public"   then repos.public_scope
        when "private"  then repos.private_not_internal_scope
        when "internal" then repos.internal_scope
        end
      end

      T.must(scopes.compact.reduce { |combined, scope| combined.or(scope) })
    end
  end
end
