# typed: true
# frozen_string_literal: true

module Configurable
  module RepositoryDependencyUpdates
    def enable_vulnerability_updates(actor:, enroll: true)
      T.bind(self, Repository)

      SecurityProduct::ServiceManager.new(self).toggle_services(
        actor,
        services_to_enable: [[:vulnerability_updates, { skip_install: !enroll }]],
      )
    end

    def enable_vulnerability_updates_grouping(actor:, enroll: true)
      T.bind(self, Repository)
      options = { skip_install: !enroll }
      result = SecurityProduct::VulnerabilityUpdatesGrouping.new(self).enable(actor: actor, options: options)
      result.value
    end

    def enable_dependabot_on_actions(actor:, enroll: true)
      T.bind(self, Repository)
      options = { skip_install: !enroll }
      result = SecurityProduct::DependabotOnActions.new(self).enable(actor: actor, options: options)
      result.value
    end

    def enable_dependabot_self_hosted(actor:, enroll: true)
      T.bind(self, Repository)
      options = { skip_install: !enroll }
      result = SecurityProduct::DependabotSelfHosted.new(self).enable(actor: actor, options: options)
      result.value
    end

    def enable_dependabot_autofix(actor:, enroll: true)
      T.bind(self, Repository)
      options = { skip_install: !enroll }
      result = SecurityProduct::DependabotAutofix.new(self).enable(actor: actor, options: options)
      result.value
    end

    def disable_vulnerability_updates(actor:)
      T.bind(self, Repository)
      SecurityProduct::ServiceManager.new(self).toggle_services(
        actor,
        services_to_disable: [:vulnerability_updates],
      )
    end

    def disable_vulnerability_updates_grouping(actor:)
      T.bind(self, Repository)
      result = SecurityProduct::VulnerabilityUpdatesGrouping.new(self).disable(actor: actor)
      result.value
    end

    def disable_dependabot_on_actions(actor:)
      T.bind(self, Repository)
      result = SecurityProduct::DependabotOnActions.new(self).disable(actor: actor)
      result.value
    end

    def disable_dependabot_self_hosted(actor:)
      T.bind(self, Repository)
      result = SecurityProduct::DependabotSelfHosted.new(self).disable(actor: actor)
      result.value
    end

    def disable_dependabot_autofix(actor:)
      T.bind(self, Repository)
      result = SecurityProduct::DependabotAutofix.new(self).disable(actor: actor)
      result.value
    end

    def vulnerability_updates_enabled?
      T.bind(self, Repository)
      SecurityProduct::VulnerabilityUpdates.new(self).enabled?
    end

    def vulnerability_updates_grouping_enabled?
      T.bind(self, Repository)
      SecurityProduct::VulnerabilityUpdatesGrouping.new(self).enabled?
    end

    def dependabot_on_actions_enabled?
      T.bind(self, Repository)
      SecurityProduct::DependabotOnActions.new(self).enabled?
    end

    def dependabot_self_hosted_enabled?
      T.bind(self, Repository)
      SecurityProduct::DependabotSelfHosted.new(self).enabled?
    end

    def dependabot_self_hosted_feature_enabled?
      T.bind(self, Repository)
      SecurityProduct::DependabotSelfHosted.new(self).feature_enabled?
    end

    def dependabot_autofix_enabled?
      T.bind(self, Repository)
      SecurityProduct::DependabotAutofix.new(self).enabled?
    end

    def dependabot_autofix_feature_enabled?
      T.bind(self, Repository)
      SecurityProduct::DependabotAutofix.new(self).feature_enabled?
    end
  end
end
