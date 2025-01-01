# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    extend T::Sig
    extend GitHub::ResilienceMixin

    sig { params(copilot_user: T.nilable(::Copilot::User)).returns(T::Boolean) }
    def self.copilot_for_prs_enabled?(copilot_user)
      with_database_error_fallback(fallback: false) do
        next false unless copilot_user

        copilot_user.pr_summarizations_enabled?
      end
    end
  end
end
