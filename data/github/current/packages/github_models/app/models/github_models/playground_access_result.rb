# typed: strict
# frozen_string_literal: true

module GitHubModels
  # Public: PlaygroundAccessResult returns whether or not a user can access the GitHub Models Playground
  # and backing Azure APIs, and if not, the reason why.
  class PlaygroundAccessResult < T::Struct
    const :accessible, T::Boolean
    const :reason, T.nilable(Symbol)

    sig { params(user: T.nilable(::User)).returns(PlaygroundAccessResult) }
    def self.for(user)
      return inaccessible_result(:no_user) unless user.present?

      emu_business = if user.is_enterprise_managed?
        user.enterprise_managed_business
      elsif user.organization? && T.cast(user, Organization).enterprise_managed_user_enabled?
        user.business
      end

      if emu_business
        return inaccessible_result(:standalone_business) if emu_business.copilot_licensing_enabled?
        return inaccessible_result(:emu_disabled) unless emu_business.models_access_enabled?
      end

      return inaccessible_result(:blocked) if GitHubModels.domain.blocks.exists?(user)
      return inaccessible_result(:spammy) if user.spammy?
      return inaccessible_result(:suspended) if user.suspended?
      return inaccessible_result(:trade_restrictions) if user.has_any_trade_restrictions?

      return inaccessible_result(:copilot_blocked) if Copilot::User.new(user).administrative_blocked?

      if user.feature_flag_enabled?(:project_neutron_emergency_restrict_access, default: false)
        creation_time = user.created_at || Time.current
        return inaccessible_result(:temporary_restriction) if creation_time > 10.days.ago
      end

      accessible_result
    end

    sig { params(reason: Symbol).returns(PlaygroundAccessResult) }
    def self.inaccessible_result(reason)
      new(accessible: false, reason: reason)
    end

    sig { returns(PlaygroundAccessResult) }
    def self.accessible_result
      new(accessible: true, reason: nil)
    end

    sig { returns(T::Boolean) }
    def accessible?
      accessible
    end
  end
end
