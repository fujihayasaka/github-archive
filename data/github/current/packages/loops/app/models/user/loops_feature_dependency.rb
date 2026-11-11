# typed: true
# frozen_string_literal: true

module User::LoopsFeatureDependency
  include GitHub::Memoizer
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { User }

  # Determines if the user has Loops enabled. A user is enabled if they have the base feature flag
  # and if the Loops policy is available it has to be enabled.
  sig { returns(T::Boolean) }
  def loops_enabled?
    return false unless feature_enabled_globally_or_for_user?(feature_name: :copilot_pipes, subject: self)
    if Copilot::Policies::Loops.available_for?(as_copilot_user)
      Copilot::Policies::Loops.effective_value(as_copilot_user) == "enabled"
    else
      # When policy is not available, allow access if they have the base (feature management) feature flag
      true
    end
  end

  memoize def as_copilot_user
    T.bind(self, User)
    Copilot::User.new(self)
  end
end
