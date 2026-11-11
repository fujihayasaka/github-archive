# typed: strict
# frozen_string_literal: true

# Manage whether or not copilot code review is able to be used in repositories owned by the business
module Configurable
  module CodeReviewRepositoryAccess
    extend T::Helpers

    requires_ancestor { ApplicationRecord::Base }

    KEY = "code_review_repository_access"

    sig { params(actor: User).void }
    def enable_code_review_repository_access(actor:)
      raise ArgumentError, "code_review_repository_access can only be configured on a Business" unless is_a?(Business)
      T.bind(self, Business)

      # Delete the config to enable access, as the config is enabled when the user blocks access
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("code_review_repository_access.enable")
      GitHub.instrument(
          "code_review_repository_access.enable",
          { user: actor, business: self })
    end

    sig { params(actor: User, force: T::Boolean).void }
    def disable_code_review_repository_access(actor:, force: false)
      raise ArgumentError, "code_review_repository_access can only be configured on a Business" unless is_a?(Business)
      T.bind(self, Business)

      # Enable the config to block access, as the config is enabled when the user blocks access
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("code_review_repository_access.disable")
      GitHub.instrument(
          "code_review_repository_access.disable",
          { user: actor, business: self })
    end

    sig { returns(T::Boolean) }
    def code_review_repository_access_enabled?
      T.bind(self, Configurable)
      !config.enabled?(KEY)
    end
  end
end
