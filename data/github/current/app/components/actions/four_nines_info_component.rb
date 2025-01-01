# typed: strict
# frozen_string_literal: true

class Actions::FourNinesInfoComponent < ApplicationComponent
  sig { params(account: Billing::Types::Account).void }
  def initialize(account:)
    @account = account
  end

  sig { returns(T.nilable(T::Boolean)) }
  memoize def enabled?
    # Refer to Launch for the actual implementation: https://github.com/github/launch/blob/bb2fec5/services/deploy/workflowinvoker/use_run_service.go#L65-L67
    @account.feature_enabled?(:actions_launch_run_service) ||
      @account.billable_owner.feature_enabled?(:actions_launch_run_service) ||
      (@account.plan.free? && @account.feature_enabled?(:actions_launch_run_service_free_plans)) ||
      (GitHub.dotcom_request? && @account.is_a?(Organization) && @account.display_login == "bbq-beets-four-nines") # this org is hardcoded to always be enabled, regardless of the feature flag status:  https://github.com/github/launch/blob/4d9883fc44ddb12b96d391a0b7b0767d0115ac09/services/deploy/workflowinvoker/use_run_service.go#L15-L19
  end

  sig { returns(Primer::Beta::Octicon) }
  memoize def enabled_icon
    if enabled?
      Primer::Beta::Octicon.new(icon: "check-circle-fill", color: :success)
    else
      Primer::Beta::Octicon.new(icon: "x-circle-fill", color: :danger)
    end
  end
end
