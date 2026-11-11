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
