# typed: strict
# frozen_string_literal: true

module Codespaces
  class SparkWorkbenchConcurrencyPolicy < ConcurrencyPolicy
    include GitHub::Memoizer
    include CloudEnvironments::IConcurrencyLimiter

    sig do
      params(
        user: ::User,
        billable_owner: ::User,
        mutex: T.untyped
      ).void
    end
    def initialize(user, billable_owner:, mutex: nil)
      @copilot_user = T.let(Copilot::Public::User.new(user), Copilot::Public::User)
      max_concurrent_instances = if is_paid_user?
        Workbench::SparkCloudspaces::Dials::MaximumInstancesForPaidUser.new(force_cache_miss: true).value
      else
        Workbench::SparkCloudspaces::Dials::MaximumInstancesForFreeUser.new(force_cache_miss: true).value
      end
      mutex ||= GitHub::Redis::ConcurrencySafeMutex.new("codespaces.workbench_cloud_environment_concurrency_policy.#{user.id}", timeout: 5.seconds, wait: 0.5.seconds, sleep: 0.1.seconds)
      super(user, billable_owner: billable_owner, max_concurrent_instances: max_concurrent_instances, mutex: mutex)
    end

    # Temporary custom reserve_capacity to allow for feature-flagged behavior.
    sig { override(allow_incompatible: true).params(sku: Codespaces::Skus::Sku, location: String, blk: T.proc.returns(T.untyped)).returns(T.untyped) } # rubocop:disable Sorbet/AllowIncompatibleOverride
    def reserve_capacity(sku:, location:, &blk)
      if user.feature_enabled?(:concurrent_spark_codespace_limits)
        # Don't allow capacity when the user has hit their dev compute limit
        dev_compute_remaining = Codespaces::Access::SparkWorkbenchUsageChecker.new(user).perform.allowed?
        if !dev_compute_remaining
          send_workbench_telemetry_event(reason: Workbench::Events::AT_CODESPACE_COMPUTE_LIMIT)

          T.unsafe(blk).call(false)
        else
          super do |has_capacity|
            send_workbench_telemetry_event(reason: Workbench::Events::AT_CODESPACE_SESSION_LIMIT) unless has_capacity

            T.unsafe(blk).call(has_capacity)
          end
        end
      else
        # Jumping through a lil hoop for Sorbet, because it doesn't like that the abstract method sig
        # doesn't call out a yielded argument.
        T.unsafe(blk).call(true)
      end
    end

    sig { returns(T::Array[Codespace]) }
    memoize def running_codespaces
      user.codespaces.consuming_compute.visible_to_workbench_cloud_environments(user).to_a
    end

    sig { returns(String) }
    def policy_name
      "spark_workbench_concurrency_limit"
    end

    sig { returns(T::Boolean) }
    def has_capacity?
      return true unless user.feature_enabled?(:concurrent_spark_codespace_limits)

      running_codespaces.count < max_concurrent_instances
    end

    private

    sig { returns(T::Boolean) }
    memoize def is_paid_user?
      @copilot_user.has_paid_access?
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def concurrency_report
      current_instance_count = running_codespaces.count
      tags = [
        "paid_user:#{is_paid_user?}",
        "current_instance_count:#{current_instance_count}",
        "max_concurrent_instances:#{max_concurrent_instances}",
      ]
      GitHub.dogstats.increment("spark.codespaces.concurrency_report", tags: tags)

      # We're only limiting Spark codespaces by instance count, not cores.
      { instances: running_codespaces.count, cores: 0 }
    end

    sig { params(reason: String).void }
    def send_workbench_telemetry_event(reason:)
      return unless user.feature_enabled?(:spark_dev_compute_telemetry)

      payload = Workbench::TelemetryInstrumenter::Payload.new(
        event_data: {
          reason: reason,
        },
        event_time: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: 0),
        event_type: Workbench::Events::SPARK_USAGE_BLOCKED,
        request_id: "",
        session_id: "",
        spark_id: "",
        user_analytics_tracking_id: user.analytics_tracking_id,
        user_id: user.id,
        restricted: false
      )

      Workbench::TelemetryInstrumenter.instrument(payload)
    end
  end
end
