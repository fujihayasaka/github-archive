# typed: strict
# frozen_string_literal: true

module Copilot
  module Instrumentation
    module CodeReview
      include Helpers

      # Emitted when a user changes any Copilot Code Review repository-level
      # setting. Carries before/after snapshots of all CCR repo settings so
      # consumers can diff which fields changed.
      #
      # old_settings is nil when no settings rows existed for the repo before
      # this change (first-write); otherwise a complete snapshot of all 6
      # settings. new_settings is always a complete snapshot.
      sig do
        params(
          repo: ::Repository,
          actor: ::User,
          old_settings: T.nilable(T::Hash[String, String]),
          new_settings: T::Hash[String, String],
        ).void
      end
      def instrument_code_review_repository_settings_updated(repo:, actor:, old_settings:, new_settings:)
        instrument(::Copilot::Events::CODE_REVIEW_REPOSITORY_SETTINGS_UPDATED, {
          repo: repo,
          actor: actor,
          old_settings: old_settings,
          new_settings: new_settings,
        })
      end
    end
  end
end
