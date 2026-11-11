# typed: strict
# frozen_string_literal: true

class ApplicationController
  module CopilotDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { ApplicationController }

    # Deprecated - prefer current_copilot_user_v2
    sig { returns T.nilable(::Copilot::User) }
    def current_copilot_user
      return @current_copilot_user if defined?(@current_copilot_user)

      @current_copilot_user = T.let(
        (Copilot::User.new(current_user) if logged_in?),
        T.nilable(::Copilot::User)
      )
    end

    sig { returns T.nilable(T.any(::Copilot::Public::User, ::Copilot::User)) }
    def current_copilot_user_v2
      return @current_copilot_user_v2 if defined?(@current_copilot_user_v2)

      @current_copilot_user_v2 = T.let(
        (Copilot::Public::User.new(current_user) if logged_in?),
        T.nilable(T.any(::Copilot::Public::User, ::Copilot::User))
      )
    end
  end
end
