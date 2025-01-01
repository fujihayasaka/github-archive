# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class UserSecurityConfigurationJob < ApplicationJob
    include GitHub::Memoizer
    include Repos::ListHelper
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

    sig do
      params(
        security_configuration_id: T.nilable(Integer),
        user_id: Integer,
        action: Symbol,
        repository_ids: T.nilable(T::Array[Integer]),
        override_existing_config: T::Boolean,
        user_session_id: T.nilable(Integer),
        options: T::Hash[Symbol, T.untyped]
      ).void
    end
    def perform(
      security_configuration_id:,
      user_id:,
      action:,
      repository_ids:,
      override_existing_config: false,
      user_session_id: nil,
      options: {}
    )
      GitHub.logger.info("Starting UserSecurityConfigurationJob")

      unless VALID_ACTIONS.include?(action)
        raise ArgumentError, "Invalid action: #{action}"
      end

      if security_configuration.nil? && action != :detach
        GitHub.logger.info("Security configuration not found.")
        return
      end

      user = self.user
      if user.nil?
        GitHub.logger.info("User not found.")
        return
      end


      T.cast(GH.context, GH::Context::DefaultContext).identity_context = GH::Auth::IdentityContext::ValueContext.new(user)

      if options[:default_for_new_public_repos].present? || options[:default_for_new_private_repos].present?
        SecurityConfigurationDefault.create_or_update_defaults(
          target: user,
          default_for_new_public_repos: options[:default_for_new_public_repos] || false,
          default_for_new_private_repos: options[:default_for_new_private_repos] || false,
          security_configuration: T.must(security_configuration),
        )
      end

      case action
      when :apply
        apply_to_repositories(user:, repository_ids:, override_existing_config:)
      when :detach
        detach_from_repositories(user:, repository_ids:)
      when :update
        update_applied_repositories(publish_backfill_group_request: options[:publish_backfill_group_request])
      end
    end

    sig do
      params(
        user: User,
        repository_ids: T.nilable(T::Array[Integer]),
        override_existing_config: T::Boolean
      ).void
    end
    def apply_to_repositories(user:, repository_ids:, override_existing_config:)
      override_params = {}
      skip_backfill_request = T.must(security_configuration).secret_scanning_enabled?

      override_params[:skip_backfill_request] = "1" if skip_backfill_request

      parse_repository_ids(action: :apply, user:, repository_ids:) do |repository_id|
        repository = Repositories::Public.find_active!(repository_id)
        enqueued_job = T.must(security_configuration).apply_to_repository(
          user,
          repository,
          user,
          override_existing_config:,
          override_params:,
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
        user: User,
        repository_ids: T.nilable(T::Array[Integer]),
      ).void
    end
    def detach_from_repositories(user:, repository_ids:)
      parse_repository_ids(action: :detach, user:, repository_ids:) do |repository_id|
        repository_security_configuration = RepositorySecurityConfiguration.find_by(repository_id: repository_id)
        next unless repository_security_configuration.present?

        ActiveRecord::Base.connected_to(role: :writing) { repository_security_configuration.destroy }

        # live_updater.repository_status(repository_id: repository_id)
      end
    end

    sig { params(publish_backfill_group_request: T.nilable(T::Boolean)).void }
    def update_applied_repositories(publish_backfill_group_request: false)
      security_config = T.must(security_configuration)
      query_scope = security_config.repository_security_configurations.applied.where(user_id: T.must(user&.id))

      query_scope.find_each(batch_size: BATCH_SIZE) do |repo_config|
        RepositorySecurityConfiguration.throttle_writes_with_retry { repo_config.updating! }

        ApplySecurityConfigurationToRepositoryJob.perform_later(
          actor_id: T.must(user&.id),
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
        user: User,
        repository_ids: T.nilable(T::Array[Integer]),
        blk: T.proc.params(repository_id: Integer).void
      ).void
    end
    def parse_repository_ids(action:, user:, repository_ids:, &blk)
      repos = user.repositories
      repos = repos.where(id: repository_ids) if repository_ids.present?

      repos.in_batches(of: BATCH_SIZE) do |relation|
        relation.pluck(:id).each(&blk)
      end
    end

    sig { returns(T.nilable(SecurityConfiguration)) }
    memoize def security_configuration
      SecurityConfiguration.find_by(id: arguments.dig(0, :security_configuration_id))
    end

    sig { returns(T.nilable(User)) }
    memoize def user
      User.find_by(id: arguments.dig(0, :user_id))
    end

    sig { returns(SecurityProductsEnablement::JobProgressTracker) }
    memoize def job_progress_tracker
      user_id = arguments.dig(0, :user_id)
      raise ArgumentError, "user_id is required" if user_id.nil?

      SecurityProductsEnablement::JobProgressTracker.new(user_id, nil)
    end

    # sig { returns(SecurityProductsEnablement::LiveUpdatePublisher) }
    # memoize def live_updater
    #   SecurityProductsEnablement::LiveUpdatePublisher.new(user)
    # end
  end
end
