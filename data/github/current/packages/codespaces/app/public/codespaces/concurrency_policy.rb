# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class ConcurrencyPolicy
    MAX_CONCURRENT_CORES_INTERNAL = 192
    MAX_CONCURRENT_CORES_WITH_GPU = 192

    attr_reader :user, :billable_owner, :max_concurrent_instances, :max_concurrent_cores

    def initialize(user, billable_owner:, max_concurrent_instances: nil, max_concurrent_cores: nil, mutex: nil)
      @user = user
      @billable_owner = billable_owner
      # Tier.for_user returns a TierResult object
      tier = Codespaces::Tier.for_user(@user)
      tier_config = Codespaces::Tier.config_for_tier(tier, @user)
      @max_concurrent_cores = tier_config.concurrent_cores
      @max_concurrent_instances = tier_config.concurrent_codespaces

      if FeatureFlag.vexi.enabled_or_raise?(:codespaces_linux_premium_gpu, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        @max_concurrent_cores = MAX_CONCURRENT_CORES_WITH_GPU
      end

      if FeatureFlag.vexi.enabled_or_raise?(:codespaces_max_concurrent_cores, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        @max_concurrent_cores = MAX_CONCURRENT_CORES_INTERNAL
      end

      @max_concurrent_cores = max_concurrent_cores unless max_concurrent_cores.nil?
      @max_concurrent_instances = max_concurrent_instances unless max_concurrent_instances.nil?

      @mutex = if mutex
        mutex
      else
        GitHub::Redis::ConcurrencySafeMutex.new("codespaces.concurrency_policy.#{user.id}", timeout: 5.seconds, wait: 0.5.seconds, sleep: 0.1.seconds)
      end
    end

    # Reserve compute capacity for the given SKU and remain within their
    # concurrency limits.
    #
    # Calls the block with whether the capacity is available, holding a lock to
    # ensure that it remains available until after the block returns.
    def reserve_capacity(sku:, location:)
      return yield(true) if FeatureFlag.vexi.enabled_or_raise?(:codespaces_automated_testing, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      @mutex.lock do
        report = concurrency_report
        prospective_cores = report[:cores] + sku.cpus
        prospective_instances = report[:instances] + 1

        has_capacity = prospective_instances <= max_concurrent_instances && prospective_cores <= max_concurrent_cores

        begin
          yield(has_capacity)
        ensure
          report_concurrency_limit_hit(sku.name, location) unless has_capacity
        end
      end
    rescue GitHub::Redis::Mutex::LockError
      report_concurrency_lock_error_hit(sku.name, location)
      raise lock_error_exception if raise_lock_error?
    end

    def enforce_concurrency_limits!
      return 0 if FeatureFlag.vexi.enabled_or_raise?(:codespaces_automated_testing, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      report = concurrency_report
      over_limit = report[:cores] > max_concurrent_cores || report[:instances] > max_concurrent_instances
      return 0 unless over_limit

      count_to_stop = [report[:instances] - max_concurrent_instances, 1].max
      codespaces_to_stop = running_codespaces
        .sort_by(&:last_used_at)
        .take(count_to_stop)

      codespaces_to_stop.each do |codespace|
        codespace.suspend!
      end

      report_concurrency_policy_enforced(count_to_stop)

      count_to_stop
    end

    def policy_name
      "concurrency_policy"
    end

    def raise_lock_error?
      true
    end

    protected def running_codespaces
      @running_codespaces ||= Codespaces::Query.new(current_user: user).all_accessible_running_codespaces
    end

    protected def lock_error_exception
      ConcurrencyLimitError.new("You may have too many codespaces starting at the same time. Please stop some and try again.")
    end

    private

    def report_concurrency_limit_hit(sku_name, location)
      tags = [
        "location:#{location}",
        "sku_name:#{sku_name}",
        "policy_name:#{policy_name}"
      ]

      GitHub.dogstats.increment("codespaces.concurrency_policy.limit_hit", tags: tags)
      GitHub.logger.info(
        "Codespace concurrency limit hit",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.owner_id" => user.id,
        "gh.codespaces.billable_owner_id" => billable_owner.id,
        "gh.codespaces.region" => location,
        "gh.codespaces.sku_name" => sku_name,
        "gh.codespaces.concurrency.policy_name" => policy_name,
      )
    end

    def report_concurrency_policy_enforced(stopped_count)
      GitHub.dogstats.increment("codespaces.concurrency_policy.enforced")
      GitHub.logger.info(
        "Codespace concurrency enforced",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.owner_id" => user.id,
        "gh.codespaces.billable_owner_id" => billable_owner.id,
        "gh.codespaces.stopped_count" => stopped_count,
        "gh.codespaces.concurrency.policy_name" => policy_name,
      )
    end

    def report_concurrency_lock_error_hit(sku_name, location)
      tags = [
        "location:#{location}",
        "sku_name:#{sku_name}",
      ]

      GitHub.dogstats.increment("codespaces.concurrency_policy.lock_error_hit", tags: tags)
      GitHub.logger.info(
        "Codespace concurrency lock error hit",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.owner_id" => user.id,
        "gh.codespaces.billable_owner_id" => billable_owner.id,
        "gh.codespaces.region" => location,
        "gh.codespaces.sku_name" => sku_name,
      )
    end

    def concurrency_report
      @concurrency_report ||= begin
        cores = running_codespaces.reduce(0) { |cores, codespace| cores + codespace.sku.cpus }
        { instances: running_codespaces.count, cores: cores }
      end
    end
  end
end
