# typed: true
# frozen_string_literal: true

module Configurable
  module IssueTriageEnabled
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { Configurable }

    KEY = "issue_triage.enabled".freeze

    included do
      T.bind(self, T.class_of(Repository))
    end

    sig { params(actor: User).returns(T::Boolean) }
    def enable_issue_triage(actor:)
      result = config.enable!(KEY, actor)

      instrument_enable(actor) if result

      result
    end

    sig { params(actor: User).returns(T::Boolean) }
    def disable_issue_triage(actor:)
      result = config.disable!(KEY, actor)

      instrument_disable(actor) if result

      result
    end

    sig { returns(T::Boolean) }
    def issue_triage_enabled?
      config.enabled?(KEY)
    end

    # Returns the user who last enabled the triage agent on this repository.
    # Only returns the updater when the setting is currently enabled — if the
    # setting was last toggled via disable_issue_triage, returns nil.
    sig { returns(T.nilable(User)) }
    def issue_triage_enabled_by
      T.bind(self, Repository)
      return unless issue_triage_enabled?

      configuration_entries.find_by(name: KEY)&.updater
    end

    private

    sig { params(actor: T.nilable(User)).void }
    def instrument_enable(actor)
      T.bind(self, Repository)

      GlobalInstrumenter.instrument("analytics.event", {
        category: "issue_triage_agent",
        action: "triage_agent_enabled",
        label: "repository_nwo:#{name_with_display_owner} actor_id:#{actor&.id}"
      })
    end

    sig { params(actor: T.nilable(User)).void }
    def instrument_disable(actor)
      T.bind(self, Repository)

      GlobalInstrumenter.instrument("analytics.event", {
        category: "issue_triage_agent",
        action: "triage_agent_disabled",
        label: "repository_nwo:#{name_with_display_owner} actor_id:#{actor&.id}"
      })
    end
  end
end
