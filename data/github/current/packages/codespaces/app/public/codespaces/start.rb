# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class Start < Command
    include Codespaces::RateLimitable
    include ActiveModel::Validations

    class InaccessibleError < StandardError; end

    class Job < CodespacesJob
      def perform(*args, **kwargs)
        begin
          operation = kwargs[:operation]
          with_write { T.unsafe(Start).call(*args, **kwargs) }
        rescue Codespaces::Client::BadResponseError => e
          if e.unprocessable_entity?
            operation&.mark_as_ended
          else
            operation&.mark_as_failed(failure_reason: e.status)
            raise
          end
        rescue Codespaces::ConcurrencyLimitError, Codespaces::RateLimitError, Codespaces::AsyncOperation::PendingError, Codespaces::Start::InaccessibleError
          # We don't want to escalate these errors to sentry since its expected behavior.
          # When called from a job, we don't have anything listening for the exception in order
          # to behave differently so we can just rescue it
          operation&.mark_as_ended
        rescue ActiveModel::ValidationError
          # This one's less expected so we escalate it to sentry but mark the operation as ended since it should indicate
          # more of a user error.
          operation&.mark_as_ended
          raise
        rescue Codespaces::Client::RequestError, Codespaces::VscsClient::TierCapacityUnavailableError => e
          # These are unexpected so we want to escalate them to sentry and mark the operation as failed as the user
          # is not at fault for these.
          operation&.mark_as_failed(failure_reason: e)
          raise
        rescue ActiveRecord::RecordNotFound
          operation&.mark_as_ended
        rescue => e # rubocop:disable Lint/GenericRescue
          operation&.mark_as_failed(failure_reason: e)
          raise
        end
      end
    end

    class Result
      attr_accessor :github_token, :github_token_valid_after, :codespace_token, :cascade_token, :response
      attr_reader :codespace

      def cascade_token # rubocop:todo Lint/DuplicateMethods
        environment&.cascade_token || @cascade_token
      end

      def connection
        environment&.connection
      end

      private

      def environment
        return nil unless response&.success?
        Codespaces::Environment.from_json(response.body)
      end
    end

    def self.perform_later(*args, **kwargs)
      T.unsafe(Codespaces::Start::Job).perform_later(*args, **kwargs, performed_in_background: true)
    end

    depends_on_clusters ApplicationRecord::Collab,
      ApplicationRecord::Permissions,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Configurations,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Spokes,
      ApplicationRecord::Billing


    validate :codespace_start_allowed
    validates :codespace, presence: true
    validate :access_checker_allowed
    validate :copilot_workspace_allowed

    attr_reader :codespace, :user, :session, :cap_filter, :request_cascade_token, :result, :github_token, :github_token_valid_after, :performed_in_background, :entry_point, :operation

    def initialize(codespace, user:, session: nil, cap_filter: nil, request_cascade_token: false, github_token: nil, github_token_valid_after: nil, concurrency_policy: nil, require_connection: true, performed_in_background: false, entry_point: nil, operation: nil)
      @codespace = codespace
      @user = user
      @session = session
      @cap_filter = cap_filter
      @request_cascade_token = request_cascade_token
      @result = Result.new
      @github_token = github_token
      @github_token_valid_after = github_token_valid_after
      @concurrency_policy = concurrency_policy
      @require_connection = require_connection
      @start_tracker = Codespaces::PerUserStartTracker.new(@user)
      @performed_in_background = performed_in_background
      @entry_point = entry_point
      @operation = operation
    end

    def perform
      validate!
      raise InaccessibleError, "Codespace is not accessible" unless codespace.accessible?
      codespace.ensure_no_blocking_pending_async_operation!

      with_reserved_capacity do |codespace_already_started|
        if !performed_in_background
          # only instrument audit log event and update last used when we're not in a background job
          # if we do it always then there are times we will have duplicated events when we reenqueue the command from within itself
          codespace.mark_used!
          codespace.instrument_connect
          codespace.instrument(:start_environment, actor: user) unless codespace_already_started
        end

        if github_token # This is only available when we've bumped into a delayed job below.
          result.github_token = github_token
          result.github_token_valid_after = github_token_valid_after
        else
          github_token, github_token_valid_after = Codespaces::Tokens.mint_github_token_with_estimated_validity(user, codespace, entry_point: entry_point)
          result.github_token = github_token
          result.github_token_valid_after = github_token_valid_after
        end

        result.codespace_token = Codespaces::Tokens.mint_codespace_token(scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE, user: user, codespace: codespace)
        cached_cascade_token = Codespaces::TokenCache.read_codespace_cascade_token(guid: codespace.guid, owner_id: user.id)

        # If the caller doesn't require the connection information and we already
        # have a cached Cascade token then we have everything we need and can do
        # the VSCS API call in a background job instead.
        if !@require_connection && cached_cascade_token
          unless codespace_already_started
            self.class.perform_later(
              codespace,
              user: user,
              session: session,
              github_token: result.github_token,
              github_token_valid_after: result.github_token_valid_after,
              request_cascade_token: true, entry_point: entry_point,
              operation: operation,
            )
          end

          if codespace_already_started && operation
            operation.mark_as_ended
          end

          result.cascade_token = cached_cascade_token
          return result
        end

        secrets = T.let([], Array)
        # We want to skip rate limiting on increment if the user just started this codespace because
        # VSCS allows multiple starts to the same codespace with no problem and there are multiple places
        # in our two codebases that do this on retry and otherwise. If we don't skip it for starting the same codespace,
        # we end up rate limiting users unnecessarily.
        skip_rate_limiting_increment = @start_tracker.codespace_most_recently_started?(codespace)

        # The reason we're rate limiting down here is because `self.class.perform_later`
        # called above reenqueues this command as an async job. If we rate limit before that call,
        # then we'd end up counting those requests twice against a user's rate limit.
        with_rate_limiting(user, skip_increment: skip_rate_limiting_increment) do
          begin
            secrets = Codespaces::Secret.assemble(codespace)
          rescue Secrets::Error => e
            Codespaces::ErrorReporter.report(e)
          end
        end

        # Send idle timeout minutes to be applied
        applicable_idle_timeout_result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
            user: user,
            billable_owner: codespace.billable_owner,
            repository: codespace.repository,
            requested_idle_timeout_minutes: codespace.environment_data.auto_shutdown_delay_minutes,
            codespace_id: codespace.id
          )

        result.response, expiration = client.start_environment(
          codespace.guid,
          github_token: result.github_token,
          codespace_token: result.codespace_token,
          sku_name: codespace.sku_name,
          secrets: secrets,
          request_cascade_token: request_cascade_token,
          repository: codespace.repository,
          billable_owner: codespace.billable_owner,
          auto_shutdown_delay_minutes: applicable_idle_timeout_result,
          failover_details: Codespaces::GetFailoverDetails.call(user:, region: codespace.location, vscs_target: codespace.vscs_target, is_copilot_workspace: codespace.copilot_workspace?),
          uses_storage_v2: uses_storage_v2
        )
        if operation
          operation.mark_as_started
        end

        if result.response.success?
          # I can't think of any reason we'd want to track starts or update the environment JSON with the result of
          # a failed API call here... so let's just not do that.
          json = GitHub::JSON.parse(result.response.body)
          env = Codespaces::Environment.from_json(json)

          ActiveRecord::Base.connected_to(role: :writing) do
            codespace.update!(
              environment_data: env,
            ) if env.present?
            @start_tracker.track_start(codespace)
          end

          if codespace.available? && operation && user&.feature_enabled?(:codespaces_start_already_started)
            # If we're trying to start a codespace that is already available we won't get the expected webhook for the
            # state transition plus it's effectively a no-op so we can just mark it as succeeded here.
            operation.mark_as_succeeded
          end

          Codespaces::Events.start(codespace)

          clear_last_known_stop_notice_cache(codespace)
        end
        result
      end
    rescue Codespaces::Client::BadResponseError => e
      if codespace.async_operations.update_storage.completed.any? &&
          e.error_body.to_s.match?(/Cannot transition to SKU/)
        # If we have a completed update storage operation but hit this error then it's likely the resize storage
        # job actually worked but we failed to properly update the SKU on our side. Double check what the service
        # thinks the SKU is and update it accordingly before retrying.
        env = client.fetch_environment!(codespace.guid)
        actual_sku = env["skuName"]
        actual_state = env["state"]
        if codespace.sku_name != actual_sku
          # Set our sku_name to what the service is actually on...
          ActiveRecord::Base.connected_to(role: :writing) do
            codespace.update!(sku_name: actual_sku)
          end
          retry
        end
      end
      raise
    rescue Codespaces::ConcurrencyLimitError, Codespaces::RateLimitError, InaccessibleError => e
      if operation
        # These errors are expected user error and we don't want to count them as failures.
        ActiveRecord::Base.connected_to(role: :writing) do
          operation.mark_as_ended
        end
      end

      raise e
    end

    private

    # Ensures that if we reserve capacity for this codespace by manipulating its state we restore the original state in
    # the event of an error thrown by the start block (e.g. a bad response from VSCS).
    def with_reserved_capacity(&block)
      if codespace.consuming_compute?
        # If the codespace is already consuming compute then the capacity's allocated and we don't need to
        # speculatively reserve capacity since it's already counted.
        yield(true)
      else
        # We will be starting this so we need to reserve capacity for it ahead of time.
        concurrency_policy.reserve_capacity(sku: codespace.sku, location: codespace.location) do |has_capacity|
          if has_capacity || (codespace.copilot_workspace? && codespace.owner.feature_enabled?(:codespaces_cwtp_no_limits))
            original_state = codespace.environment_data&.state
            set_environment_state!(Codespaces::Vscs::State::STARTING)
            begin
              yield(false)
            rescue StandardError => e # rubocop:disable Lint/GenericRescue
              # Something blew up while trying to start the environment so we need to restore our original state to
              # avoid counting this codespace against the user's quota on future Start attempts.
              set_environment_state!(original_state)
              raise e
            end
          else
            # Without capacity, we never changed the state to ::STARTING, so we can just raise.
            if codespace.copilot_workspace? && !codespace.owner.feature_enabled?(:codespaces_cwtp_no_limits)
              raise Codespaces::CopilotWorkspaceConcurrencyLimitError
            else
              raise Codespaces::ConcurrencyLimitError
            end
          end
        end
      end
    end

    def set_environment_state!(state)
      ActiveRecord::Base.connected_to(role: :writing) do
        codespace.merge_environment_data!({ state: state })
      end
    end

    def write_cascade_token_cache(expiration:)
      Codespaces::TokenCache.write_codespace_cascade_token(
        owner_id: user.id,
        guid: codespace.guid,
        token: result.cascade_token,
        expiration: expiration,
      )
    end

    def clear_last_known_stop_notice_cache(codespace)
      Codespaces::LastKnownStopNoticeCache.clear(
        billable_owner_id: codespace.billable_owner_id
      )
    end

    def client
      Codespaces::VscsClient.for_codespace(codespace)
    end

    def concurrency_policy
      @concurrency_policy ||= if codespace.copilot_workspace? && !codespace.owner.feature_enabled?(:codespaces_cwtp_no_limits)
        Codespaces::CopilotWorkspaceConcurrencyPolicy.new(codespace.owner, billable_owner: codespace.billable_owner)
      else
        Codespaces::ConcurrencyPolicy.new(codespace.owner, billable_owner: codespace.billable_owner)
      end
    end

    def codespace_start_allowed
      errors.add(:base, :unavailable, message: "Starting codespaces is temporarily unavailable.") if codespace.owner&.feature_enabled?(:codespaces_disable_starts)
    end

    def access_checker_allowed
      usage = Codespaces::AccessChecker.from_codespace(codespace)

      usage_result = usage.run_check(
        sku_name: codespace.sku_name,
        dev_container: codespace.dev_container,
      )

      return if usage_result.allowed?

      error_message = if codespace.copilot_workspace? && usage_result.disallowed_by_entitlements?
        "You've reached your Copilot Workspace usage limit."
      elsif usage_result.disallowed_by_spending_limit?
        "You've reached your spending limit for this period."
      elsif usage_result.disallowed_by_entitlements?
        "You're at 100% of your included usage for this billing period."
      elsif usage_result.disallowed_by_payment_method?
        "There seems to be an issue with your payment method."
      elsif usage_result.disallowed_by_billing?
        "There is a billing issue that is preventing you from starting this codespace."
      elsif usage_result.disallowed_by_machine_policy?
        "This codespace is currently using a machine type disallowed by your organization settings. Please update the codespace's machine type or export your changes to a branch."
      elsif usage_result.disallowed_by_image_policy?
        "This codespace uses a dev container image disallowed by your organization settings. Please export your changes to a branch."
      else
        # We should never hit this currently but this is a fallback in case in the future
        # a new kind of AllowedResult error isn't handled.
        "You are not allowed to start this codespace."
      end

      if usage_result.disallowed_by_billing?
        errors.add(:base, :billing, message: error_message)
      elsif usage_result.disallowed_by_machine_policy? || usage_result.disallowed_by_image_policy?
        errors.add(:base, :policy, message: error_message)
      else
        errors.add(:base, message: error_message)
      end
    end

    def copilot_workspace_allowed
      return unless codespace.copilot_workspace?
      return unless codespace.owner.present?
      return if codespace.owner.feature_enabled?(:copilot_workspace)

      raise Codespaces::CopilotWorkspaceFeatureDisabledError
    end

    def uses_storage_v2
      return false if codespace.environment_data&.features.nil?
      codespace.environment_data[:features]["useStorageV2"] == "true"
    end

    def dd_tags
      tags = super
      tags << "codespaces_use_storage_v2_internal:true" if uses_storage_v2 && codespace.owner.feature_enabled?(:codespaces_developer)
      tags
    end
  end
end
