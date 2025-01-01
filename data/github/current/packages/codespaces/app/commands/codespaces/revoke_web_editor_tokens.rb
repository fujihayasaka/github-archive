# typed: true
# frozen_string_literal: true

module Codespaces
  # Revoke all of a user's OauthAccess and OauthAuthorization records for
  # the github.dev OauthApplication.  Intended to be called on GitHub logout
  # to ensure that github.dev activity can't happen after a GH session ends.
  class RevokeWebEditorTokens < Command
    def initialize(user:, timeout:, entry_point:)
      @user = user
      @timeout = timeout
      @entry_point = entry_point
    end

    # Sentinel return values
    module Result
      TimedOut = Class.new
      Success = Class.new
    end

    def perform
      lwe_app = Apps::Internal.oauth_application(:lightweight_web_editor) or return

      GitHub::SafeTimer.timeout(@timeout) do |timer|
        @user.oauth_authorizations.where(application: lwe_app).find_each do |authorization|
          return Result::TimedOut if timer.expired?
          authorization.destroy_with_explanation(:logged_out, entry_point: @entry_point)
        end
      end
      Result::Success
    end
  end
end
