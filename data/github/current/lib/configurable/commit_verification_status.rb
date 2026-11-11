# typed: true
# frozen_string_literal: true

# Manage level of labeled commit signing a user would like
module Configurable
  module CommitVerificationStatus
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "commit_verification_status".freeze
    STATES = %w[disabled enabled]

    def set_commit_verification_status_state(actor: nil, state: "disabled")
      return unless STATES.include?(state)
      return disable_commit_verification_status(actor: actor) if state == "disabled"

      return unless config.set!(KEY, state, actor)
      log(actor, state)
    end

    def commit_verification_status_enabled?
      config.get(KEY).present?
    end

    def disable_commit_verification_status(actor: nil)
      return if config.get(KEY).nil?
      return unless config.delete(KEY, actor)
      log(actor, "disabled")
    end

    private

    def log(actor, state)
      GitHub.dogstats.increment("user.flag_unverified_commits.updated", tags: ["state:#{state}"])
      GitHub.logger.info(
        "Updating commit verification status",
        "code.namespace" => "Configurable::CommitVerificationStatus",
        "code.function" => "set_commit_verification_status_state",
        "gh.actor.id" => actor.id,
        "gh.commit_verification.state" => state
      )
    end
  end
end
