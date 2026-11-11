# typed: strict
# frozen_string_literal: true

# Public: Manages the enterprise trial limit setting for users.
class EnterpriseTrialLimit
  include Limits

  sig { returns(User) }
  attr_reader :user

  limits :created_trials,
    to: -> {
      T.bind(self, EnterpriseTrialLimit)
      value = user.settings.get(:enterprise_trial_limit)
      value ? value.to_i : EnterpriseTrialLimit.default_limit
    },
    reached_when: -> {
      T.bind(self, EnterpriseTrialLimit)
      user_trial_count = Business.where(created_by_id: user.id).count
      user_trial_count >= created_trials_limit
    }

  sig { returns(Integer) }
  def self.default_limit
    UserSettings::ENTERPRISE_TRIAL_LIMIT_DEFAULT
  end

  sig { params(user: User).void }
  def initialize(user:)
    @user = user
  end

  sig { params(new_limit: Integer).void }
  def set_limit!(new_limit)
    if new_limit == EnterpriseTrialLimit.default_limit
      reset_to_default!
    else
      @user.settings.set!(:enterprise_trial_limit, new_limit.to_i)
    end
  end

  sig { void }
  def reset_to_default!
    # This should remove the user setting for enterprise_trial_limit,
    # but there isn't a public method to do that now.
    # Instead, just set the value to the default.
    @user.settings.set!(:enterprise_trial_limit, EnterpriseTrialLimit.default_limit)
  end

  sig { returns(T::Boolean) }
  def has_custom_limit?
    effective = @user.settings.get(:enterprise_trial_limit)
    effective && effective.to_i != EnterpriseTrialLimit.default_limit
  end
end
