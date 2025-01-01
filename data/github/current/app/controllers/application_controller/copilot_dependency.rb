# typed: strict
# frozen_string_literal: true

class ApplicationController
  module CopilotDependency
    extend ActiveSupport::Concern
    extend T::Helpers
    extend T::Sig
    include GitHub::Memoizer

    requires_ancestor { ApplicationController }

    # Deprecated - prefer current_copilot_user_v2
    sig { returns T.nilable(::Copilot::User) }
    memoize def current_copilot_user
      Copilot::User.new(current_user) if logged_in?
    end

    sig { returns T.nilable(T.any(::Copilot::Public::User, ::Copilot::User)) }
    memoize def current_copilot_user_v2
      if current_user.feature_enabled?(:copilot_license_checks_cached)
        Copilot::Public::User.new(current_user) if logged_in?
      else
        current_copilot_user
      end
    end
  end
end
