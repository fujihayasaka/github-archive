# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class OrganizationSecurityConfigurationJob < ApplicationJob
    include GitHub::Memoizer
    include SecurityConfigurations::RepositoriesDependency

    BATCH_SIZE = 100
    VALID_ACTIONS = %i[apply detach update delete]

    ReposNotFoundError = Class.new(StandardError)

    attr_accessor :enqueued_any_job

    queue_as :security_configurations

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    before_enqueue do |_|
      job_progress_tracker.start
    end

    around_perform do |job, block|
      job.enqueued_any_job = false

      block.call
    ensure
      job_progress_tracker.finish unless job.enqueued_any_job
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
        repository_ids: T.nilable(T::Array[Integer]),
        repository_query: T.nilable(String),
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
      repository_ids:,
      repository_query: nil,
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

      repository_ids = repository_ids || []

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
        apply_to_repositories(organization:, actor:, repository_ids:, repository_query:, override_existing_config:)
      when :detach
        detach_from_repositories(organization:, actor:, repository_ids:, repository_query:)
      when :update
        update_applied_repositories(publish_backfill_group_request: options[:publish_backfill_group_request])
      end
    end

    sig do
      params(
        organization: Organization,
        actor: User,
        repository_ids: T::Array[Integer],
        repository_query: T.nilable(String),
        override_existing_config: T::Boolean
      ).void
    end
    def apply_to_repositories(organization:, actor:, repository_ids:, repository_query:, override_existing_config:)
      override_params = {}
      skip_backfill_request = T.must(security_configuration).secret_scanning_enabled?

      # If we're applying a config with secret scanning set as enabled, we want to leverage secret scanning group backfill
      # instead of sending individual backfill requests for each repo.
      if skip_backfill_request
        override_params[:skip_backfill_request] = "1"
      end

      if repository_ids.empty? && repository_query.present?
        GitHub.logger.info("calculating license using search query")
        all_repo_ids_from_search_query = find_repo_ids_by_query(
          query: repository_query,
          organization:,
          actor:,
          user_session:,
          cap_filter: nil
        )
        prevent_additional_sku_usage = prevent_additional_sku_usage(organization, all_repo_ids_from_search_query)
      else
        GitHub.logger.info("calculating license using provided repository_ids")
        prevent_additional_sku_usage = prevent_additional_sku_usage(organization, repository_ids)
      end

      GitHub.logger.info("prevent_additional_sku_usage: #{prevent_additional_sku_usage}")

      parse_repository_ids(action: :apply, organization:, actor:, repository_ids:, repository_query:) do |repository_id|
        repository = Repositories::Public.find_active!(repository_id)
        enqueued_job = T.must(security_configuration).apply_to_repository(
          repository,
          actor:,
          override_existing_config:,
          override_params:,
          prevent_additional_sku_usage: prevent_additional_sku_usage.to_a
        )

        if enqueued_job
          job_progress_tracker.increment_jobs
          job_progress_tracker.append_repository_id(repository_id) if skip_backfill_request
          self.enqueued_any_job = true
        end
      end
    end

    sig do
      params(
        organization: Organization,
        actor: User,
        repository_ids: T::Array[Integer],
        repository_query: T.nilable(String),
      ).void
    end
    def detach_from_repositories(organization:, actor:, repository_ids:, repository_query:)
      parse_repository_ids(action: :detach, organization:, actor:, repository_ids:, repository_query:) do |repository_id|
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
        RepositorySecurityConfiguration.throttle_writes_with_retry { repo_config.updating! }

        ApplySecurityConfigurationToRepositoryJob.perform_later(
          actor_id: T.must(actor&.id),
          repository_id: repo_config.repository_id,
          security_configuration_id: security_config.id,
          override_params: publish_backfill_group_request ? { skip_backfill_request: "1" } : {}
        )

        job_progress_tracker.increment_jobs
        job_progress_tracker.append_repository_id(repo_config.repository_id) if publish_backfill_group_request
        self.enqueued_any_job = true
      end
    end

    sig do
      params(
        action: Symbol,
        organization: Organization,
        actor: User,
        repository_ids: T::Array[Integer],
        repository_query: T.nilable(String),
        blk: T.proc.params(repository_id: Integer).void
      ).void
    end
    def parse_repository_ids(action:, organization:, actor:, repository_ids:, repository_query:, &blk)
      organization = T.must(organization)
      if repository_query.present? && repository_ids.blank?
        repository_ids = find_repo_ids_by_query(
          query: repository_query,
          organization:,
          actor:,
          user_session:,
          cap_filter: nil,
          use_cursor_pagination: true,
          &blk
        )
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
      tags = {
        "gh.org.id": arguments.dig(0, :organization_id),
        "gh.org.login": organization&.display_login,
        "gh.enduser.id": arguments.dig(0, :actor_id),
        "gh.enduser.login": actor&.display_login,
        "gh.security_configuration.id": arguments.dig(0, :security_configuration_id),
        "gh.security_configuration.action": arguments.dig(0, :action),
        "gh.security_configuration.user_session_id": arguments.dig(0, :user_session_id),
        "gh.security_configuration.org_job.repository_ids": arguments.dig(0, :repository_ids),
        "gh.security_configuration.org_job.repository_query": arguments.dig(0, :repository_query),
        "gh.security_configuration.org_job.override_existing_config": arguments.dig(0, :override_existing_config),
        "gh.security_configuration.org_job.options": arguments.dig(0, :options)
      }

      super.merge(tags)
    end

    sig { returns T.nilable(SecurityConfiguration) }
    memoize def security_configuration
      security_configuration_id = arguments.dig(0, :security_configuration_id)
      return if security_configuration_id.nil?
      SecurityConfiguration.find_by(id: security_configuration_id)
    end

    sig { returns(T.nilable(Organization)) }
    memoize def organization
      org_id = arguments.dig(0, :organization_id)
      return if org_id.nil?
      Organization.find_by(id: org_id)
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
      business_id = T.let(nil, T.nilable(Integer))
      if organization.present?
        business_id = T.must(organization).business&.id
      end

      SecurityProductsEnablement::JobProgressTracker.new(arguments.dig(0, :organization_id), business_id)
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
  end
end
