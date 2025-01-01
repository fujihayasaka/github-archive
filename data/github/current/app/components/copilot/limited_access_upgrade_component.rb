# typed: strict
# frozen_string_literal: true

module Copilot
  class LimitedAccessUpgradeComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    sig { returns(Copilot::User) }
    attr_reader :copilot_user

    sig { params(copilot_user: Copilot::User).void }
    def initialize(copilot_user)
      @copilot_user = T.let(copilot_user, Copilot::User)
    end

    sig { returns(T::Boolean) }
    def render?
      return true if copilot_user.has_limited_access?
      false
    end

    sig { returns(T::Boolean) }
    def new_checklist_enabled?
      copilot_user.feature_enabled?(:copilot_ftp_settings_upgrade)
    end

    sig { returns(T::Boolean) }
    def show_free_user_checklist?
      !free_user_checklist_dismissed? && !free_user_checklist_completed?
    end

    sig { returns(T::Boolean) }
    def free_user_checklist_dismissed?
      current_user.settings.get(:copilot_free_user_checklist_dismissed)
    end

    sig { returns(T::Boolean) }
    def free_user_checklist_completed?
      free_user_checklist.all?(true)
    end

    sig { returns(T::Array[T::Boolean]) }
    def free_user_checklist
      JSON.parse(current_user.settings.get(:copilot_free_user_checklist))
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def react_partial_props
      {
        dismissed: free_user_checklist_dismissed?,
        checklistState: free_user_checklist,
        timeKey: Time.now.to_i,
      }
    end
  end
end
