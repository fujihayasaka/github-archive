# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class RepositoryEnablementJob < ApplicationJob
    extend T::Sig
    include GitHub::Memoizer
    include SecretScanning::Features::FeatureFlagHelper

    class ToggleServicesError < StandardError; end

    queue_as :security_analysis_settings

    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    retry_on ToggleServicesError, attempts: 3, wait: :polynomially_longer

    locked_by timeout: ApplicationJob::DEFAULT_TIMEOUT, key: ->(job) do
      repository_id = job.arguments.dig(0, :repository_id)
      DEFAULT_LOCK_STRINGIFY_PROC.call([repository_id])
    end

    EMIT_BACKFILL_GROUP_REQUEST_DEFAULT = true

    # Validate inputs before performing the job to catch missing data early.
    around_perform do |job, block|
      if job.repository.nil?
        GitHub.logger.info("Repository not found.")
        next
      end

      if job.actor.nil?
        GitHub.logger.info("Actor not found.")
        next
      end

      if job.arguments.dig(0, :update_types).empty?
        GitHub.logger.info("No update_types provided.")
        next
      end

      if !SecurityProduct::Permissions::RepoAuthz.new(T.must(job.repository), actor: T.must(job.actor)).can_manage_security_products?
        GitHub.logger.info("Actor cannot manage the repository's security settings.")
        next
      end

      block.call
    ensure
      # After the job is performed, decrement the counter for each update type. Each counter is a
      # "stack" of repos to be processed. The related settings are blocked if the counter is > 0.
      #
      # after_perform is not invoked on error, so we must use around_perform to decrement the counters.
      job.arguments.dig(0, :update_types).each do |update_type|
        remaining = job.repo_counter&.decrement(update_type)
        # If this is the last repo to be processed, handle any cleanup needed.
        job.finalize_enablement(update_type) if remaining&.zero?
      end
    end

    # As the job is enqueued, increment the counter for each update type. This counter gives us
    # a "stack" of repos to-be-processed; the org is busy if the counter is > 0.
    before_enqueue do |job|
      job.arguments.dig(0, :update_types).each do |update_type|
        job.repo_counter&.increment(update_type)
      end
    end

    sig { params(repository_id: Integer, update_types: T::Array[Symbol], actor_id: Integer, update_options: T::Hash[Symbol, T.untyped], emit_backfill_group_request: T.nilable(T::Boolean)).void }
    def perform(repository_id:, update_types:, actor_id:, update_options: {}, emit_backfill_group_request: EMIT_BACKFILL_GROUP_REQUEST_DEFAULT)
      toggle_params = toggle_services_params(update_types, update_options:)

      result = Repository.throttle_writes_with_retry do
        SecurityProduct::ServiceManager
          .new(T.must(repository))
          .toggle_services_with_form_inputs(actor, params: toggle_params)
      end

      if result.error?
        GitHub.logger.error(result.error)
        raise ToggleServicesError.new if retry?(result.error)
      end

      if result.value.empty?
        GitHub.logger.info("No services enabled.")
        GitHub.dogstats.increment("security_center.enablement.noop.count", tags: all_stats_tags)
      end
    end

    sig { params(update_types: T::Array[Symbol], update_options: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, String]) }
    def toggle_services_params(update_types, update_options:)
      params = {}

      update_types.each do |update_type|
        case update_type
        when :private_vulnerability_reporting_enable_all
          params[:private_vulnerability_reporting_enabled] = "1"
        when :private_vulnerability_reporting_disable_all
          params[:private_vulnerability_reporting_enabled] = "0"
        when :dependency_graph_enable_all
          params[:dependency_graph_enabled] = "1"
        when :dependency_graph_disable_all
          params[:dependency_graph_enabled] = "0"
        when :security_alerts_enable_all
          params[:vulnerability_alerts_enabled] = "1"
        when :security_alerts_disable_all
          params[:vulnerability_alerts_enabled] = "0"
        when :vulnerability_updates_enable_all
          params[:vulnerability_updates_enabled] = "1"
        when :vulnerability_updates_disable_all
          params[:vulnerability_updates_enabled] = "0"
        when :auto_codeql_enable_all
          params[:auto_codeql_enabled] = "1"
          params[:bulk] = "1"
          params[:fail_on_manual_workflow] = "1"
          params[:auto_codeql_query_suite] = update_options[:auto_codeql_query_suite]
        when :auto_codeql_disable_all
          params[:auto_codeql_enabled] = "0"
        when :secret_scanning_enable_all
          params[:token_scanning_enabled] = "1"
          # Repo backfills shouldn't be executed because this job will emit a BackfillGroupRequest hydro event.
          params[:skip_backfill_request] = "1"
        when :secret_scanning_disable_all
          params[:token_scanning_enabled] = "0"
        when :secret_scanning_validity_checks_enable_all
          params[:token_scanning_validity_checks_enabled] = "1"
        when :secret_scanning_validity_checks_disable_all
          params[:token_scanning_validity_checks_enabled] = "0"
        when :secret_scanning_push_protection_enable_all
          params[:token_scanning_push_protection_enabled] = "1"
        when :secret_scanning_push_protection_disable_all
          params[:token_scanning_push_protection_enabled] = "0"
        when :advanced_security_enable_all
          params[:advanced_security_enabled] = "1" if GitHub.enterprise? || !repository&.public?
        when :advanced_security_disable_all
          params[:advanced_security_enabled] = "0" if GitHub.enterprise? || !repository&.public?
        end
      end

      if update_options[:enablement_action].presence == "security_coverage_page_enablement"
        params[:enablement_action] = "security_coverage_page_enablement"
      end

      params
    end

    sig { params(update_type: Symbol).void }
    def finalize_enablement(update_type)
      kwargs = arguments.first || {}

      feature_flags = []
      if repository
        if repository&.owner && feature_flag_enabled?(T.must(repository&.owner), FeatureFlags::OWNER_SERVICE_FLAGS_ON_ORG_ENABLEMENT)
          feature_flags = SecretScanning::Instrumentation::OwnerServiceFlags.new(T.must(repository&.owner)).group_backfill_service_flags
        else
          feature_flags = SecretScanning::Instrumentation::RepositoryServiceFlags.new(T.must(repository)).group_backfill_service_flags
        end
      end

      if [:secret_scanning_enable_all, :secret_scanning_disable_all].include?(update_type)
        if kwargs.fetch(:emit_backfill_group_request, EMIT_BACKFILL_GROUP_REQUEST_DEFAULT)
          GitHub.logger.info("publishing TSS backfill message")
          GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
            action: update_type == :secret_scanning_enable_all ? :START : :CANCEL,
            owner: repository&.owner,
            requested_at: Time.current.utc,
            type: :FULL,
            feature_flags: feature_flags
          })
        end
      end

    end

    protected

    sig { returns(T::Array[String]) }
    def stats_tags
      tags = []

      arguments.dig(0, :update_types).each do |update_type|
        tags << "update_type:#{update_type}"
      end

      tags
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      kwargs = arguments.first || {}

      owner = repository&.owner
      owner_tag_prefix = owner&.organization? ? "gh.org" : "gh.user"

      update_types = kwargs.dig(:update_types)

      update_options = kwargs.dig(:update_options)
      update_options = nil if update_options.blank?

      tags = {
        "gh.repo.id": repository&.id,
        "gh.repo.name": repository&.name,
        "#{owner_tag_prefix}.id": owner&.id,
        "#{owner_tag_prefix}.login": owner&.display_login,
        "gh.enduser.id": actor&.id,
        "gh.enduser.login": actor&.display_login,
        "gh.security_center.enablement.update_types": update_types.join(","),
        "gh.security_center.enablement.update_options": update_options&.map { |k, v| "#{k}:#{v}" }&.join(","),
        "gh.security_center.job.emit_backfill_group_request": kwargs.fetch(:emit_backfill_group_request, EMIT_BACKFILL_GROUP_REQUEST_DEFAULT),
      }

      tags.merge("gh.security_center.job.remaining_repo_count": repo_counter&.value(update_types.first)) if update_types.any?

      super.merge(tags)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end

    sig { returns(T.nilable(Repository)) }
    memoize def repository
      repository_id = arguments.dig(0, :repository_id)
      Repositories::Public.find_active(repository_id)
    end

    sig { returns(T.nilable(User)) }
    memoize def actor
      actor_id = arguments.dig(0, :actor_id)
      User.find_by(id: actor_id)
    end

    sig { returns(T.nilable(BlockedSettings::RepoCounter)) }
    memoize def repo_counter
      return nil unless repository
      BlockedSettings.new(T.must(repository&.owner)).repo_counter
    end

    private

    # Service-specific retry logic. Not all errors represent a failure state, not all failures are retryable.
    sig { params(error: T.untyped).returns(T::Boolean) }
    def retry?(error)
      # AutoCodeql; lack of twirp error indicates circuit breaker failure
      return true if error.is_a?(CodeScanning::AutoCodeqlError) && error.twirp_error.nil?

      false
    end
  end
end
