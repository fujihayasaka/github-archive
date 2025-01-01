# typed: true
# frozen_string_literal: true

module ConditionalAccess::AuthzdRollout
  def self.opt_out_for_biz_teams?(businesses, method:, location:)
    result = any_biz_with_enterprise_teams?(businesses)
    GitHub.dogstats.count("cap.opt_out_for_biz_teams", 1, tags: ["location:#{location}", "opted_out:#{result}", "method:#{method}"])
    result
  end

  def self.any_biz_with_enterprise_teams?(businesses = [])
    businesses.each do |biz|
      return true if biz.present? && biz.erp_feature_enabled?(:enterprise_teams_org_assignment)
    end
    false
  end

  def location
    Kernel.raise("location must be implemented in including types")
  end

  def authzd_cap_actor
    Kernel.raise("authzd_cap_actor must be implemented in including types")
  end

  def target_provider
    Kernel.raise("target_provider must be implemented in including types")
  end

  def use_authzd_cap?
    result = nil

    # Authzd cap is enabled by default in tests. Individual tests can opt out by enabling :skip_authzd_cap_in_test
    if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      return false if FeatureFlag.vexi.enabled?(:skip_authzd_cap_in_test, default: false)
    end

    # when we're ready to cut dotcom/proxima over, we likely won't be ready
    # for GHES quite yet. Adding this check here as a precaution/reminder
    # for when we remove feature flags for dotcom cutover
    return false if GitHub.enterprise?

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = authzd_cap_flag_enabled?
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    GitHub.dogstats.distribution("cap.use_authzd_cap.dist", (end_time - T.must(start_time)) * 1_000, tags: ["location:#{location}", "authzd_cap_enabled:#{result}"])

    result
  end

  def authzd_cap_flag_enabled?
    ActiveRecord::Base.connected_to(role: :reading) do
      location_flag = "use_authzd_cap_global_#{location}".to_sym
      globally_enabled = FeatureFlag.vexi.enabled?(:use_authzd_cap_global, default: false) && FeatureFlag.vexi.enabled?(location_flag, default: false)
      return false unless globally_enabled

      return false if FeatureFlag.vexi.enabled?(:skip_authzd_cap_for_biz_team_preview, default: true) \
        && ConditionalAccess::AuthzdRollout.opt_out_for_biz_teams?(authzd_cap_actor_businesses, location: location, method: :enforcement)

      # check if this location is enabled for the request, darkshipped
      # this is how we'll roll out requests where we do not have an actor or a target
      return true if FeatureFlag.vexi.enabled?("use_authzd_cap_darkship_#{location}".to_sym, default: false)

      # get the actor for the request, and determine if it can be used for feature flag checks
      actor = authzd_cap_actor
      has_flaggable_actor = !!(actor && actor.respond_to?(:flipper_id))

      if has_flaggable_actor
        is_emu = actor.respond_to?(:is_enterprise_managed?) && ActiveRecord::Base.connected_to(role: :reading) { actor.is_enterprise_managed? }
        feature_flag_name = if is_emu
          "use_authzd_cap_emu_#{location}".to_sym
        else
          "use_authzd_cap_non_emu_#{location}".to_sym
        end

        FeatureFlag.vexi.enabled?(feature_flag_name, actor, default: false)
      else
        # there is no flaggable actor and the darkship flag isn't enabled
        false
      end
    end
  end

  def use_authzd_cap_filter?
    ActiveRecord::Base.connected_to(role: :reading) do
      # Allow individual tests to skip authzd cap by enabling :skip_authzd_cap_in_test.
      # Note: authzd cap is enabled by default in tests.
      if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        return false if FeatureFlag.vexi.enabled?(:skip_authzd_cap_in_test, default: false)
      end

      # get the actor for the request, and determine if it can be used for feature flag checks
      actor = authzd_cap_actor
      has_flaggable_actor = !!(actor && actor.respond_to?(:flipper_id))

      return false if FeatureFlag.vexi.enabled?(:skip_authzd_cap_for_biz_team_preview, default: false) \
        && ConditionalAccess::AuthzdRollout.opt_out_for_biz_teams?(authzd_cap_actor_businesses, location: location, method: :filter)

      # when we're ready to cut dotcom/proxima over, we likely won't be ready
      # for GHES quite yet. Adding this check here as a precaution/reminder
      # for when we remove feature flags for dotcom cutover
      return false if GitHub.enterprise?

      location_flag = "use_authzd_cap_filter_global_#{location}".to_sym
      globally_enabled = FeatureFlag.vexi.enabled?(:use_authzd_cap_filter_global, default: false) && FeatureFlag.vexi.enabled?(location_flag, default: false)
      return false unless globally_enabled

      # check if this location is enabled for the request, darkshipped
      # this is how we'll roll out requests where we do not have an actor or a target
      return true if FeatureFlag.vexi.enabled?("use_authzd_cap_filter_darkship_#{location}".to_sym, default: false)

      # if we've made it here and there isn't a flaggable actor there's nothing more to check
      return false if !has_flaggable_actor

      # if we've determined this request to be emu related, we use a different feature flag
      # so that we can rollout non-emu requests first, enabling by percentage and then
      # we can enable EMU specific requests by emu_group custom gates
      is_emu_request = actor.respond_to?(:is_enterprise_managed?) && actor.is_enterprise_managed?
      feature_flag_name = if is_emu_request
        "use_authzd_cap_filter_emu_#{location}".to_sym
      else
        "use_authzd_cap_filter_non_emu_#{location}".to_sym
      end

      actor.feature_flag_enabled?(feature_flag_name, default: false)
    end
  end

  private

  def authzd_cap_actor_businesses
    a = authzd_cap_actor
    return [] unless a
    businesses = case a
    when Integration, Bot
      a.async_owner.then do |owner|
        async_businesses(owner)
      end
    when OauthApplication
      a.async_user.then do |user|
        async_businesses(user)
      end
    when GitAuth::SSHKey, PublicKey
      if a.repository_id
        if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
          Repositories.domain.by_id(a.repository_id)
        else
          Repository.find_by(id: a.repository_id)
        end.then do |repo|
          repo.async_owner.then do |owner|
            async_businesses(owner)
          end
        end
      else
        User.find_by(id: a.user_id).then do |user|
          async_businesses(user)
        end
      end
    when User
      async_businesses(a)
    else
      Promise.resolve([])
    end

    Array.wrap(businesses.sync)
  end

  def async_businesses(actor)
    if actor.is_a?(Organization)
      actor.async_business
    elsif actor.is_a?(User)
      actor.async_businesses
    elsif actor.is_a?(Business)
      Promise.resolve(actor)
    else
      Promise.resolve([])
    end
  end
end
