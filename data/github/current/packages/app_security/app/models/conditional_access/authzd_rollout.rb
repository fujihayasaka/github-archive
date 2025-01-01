# typed: true
# frozen_string_literal: true

module ConditionalAccess::AuthzdRollout
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

    # Allow individual tests to use authzd cap by enabling :use_authzd_cap_in_test and disabling :skip_authzd_cap_in_test
    # By default, authzd cap is not used in tests, for both all-features and regular execution modes
    if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      return false unless GitHub.flipper[:use_authzd_cap_in_test].enabled?
      return false if GitHub.flipper[:skip_authzd_cap_in_test].enabled?
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
    location_flag = "use_authzd_cap_global_#{location}".to_sym
    globally_enabled = GitHub.flipper[:use_authzd_cap_global].enabled? && GitHub.flipper[location_flag].enabled?
    return false unless globally_enabled

    # check if this location is enabled for the request, darkshipped
    # this is how we'll roll out requests where we do not have an actor or a target
    return true if GitHub.flipper["use_authzd_cap_darkship_#{location}".to_sym].enabled?

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

      GitHub.flipper[feature_flag_name].enabled?(actor)
    else
      # there is no flaggable actor and the darkship flag isn't enabled
      false
    end
  end

  def use_authzd_cap_filter?
    # Allow individual tests to use authzd cap by enabling :use_authzd_cap_in_test and disabling :skip_authzd_cap_in_test
    # By default, authzd cap is not used in tests, for both all-features and regular execution modes
    if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      return false unless GitHub.flipper[:use_authzd_cap_in_test].enabled?
      return false if GitHub.flipper[:skip_authzd_cap_in_test].enabled?
    end

    # when we're ready to cut dotcom/proxima over, we likely won't be reeady
    # for GHES quite yet. Adding this check here as a precaution/reminder
    # for when we remove feature flags for dotcom cutover
    return false if GitHub.enterprise?

    location_flag = "use_authzd_cap_filter_global_#{location}".to_sym
    globally_enabled = GitHub.flipper[:use_authzd_cap_filter_global].enabled? && GitHub.flipper[location_flag].enabled?
    return false unless globally_enabled

    # check if this location is enabled for the request, darkshipped
    # this is how we'll roll out requests where we do not have an actor or a target
    return true if GitHub.flipper["use_authzd_cap_filter_darkship_#{location}".to_sym].enabled?

    # get the actor for the request, and determine if it can be used for feature flag checks
    actor = authzd_cap_actor
    has_flaggable_actor = !!(actor && actor.respond_to?(:flipper_id))

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

    actor.feature_enabled?(feature_flag_name)
  end
end
