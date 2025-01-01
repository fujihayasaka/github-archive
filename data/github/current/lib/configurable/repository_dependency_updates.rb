# typed: true
# frozen_string_literal: true

module Configurable
  module RepositoryDependencyUpdates
    def enable_vulnerability_updates(actor:, enroll: true)
      T.bind(self, Repository)
      params = { skip_vulnerability_updates_dependabot_install: !enroll, vulnerability_updates_enabled: "1" }
      SecurityProduct::ServiceManager.new(self).toggle_services_with_form_inputs(actor, params:)
    end

    def enable_vulnerability_updates_grouping(actor:, enroll: true)
      options = { skip_install: !enroll }
      result = SecurityProduct::VulnerabilityUpdatesGrouping.new(self).enable(actor: actor, options: options)
      result.value
    end

    def enable_dependabot_on_actions(actor:, enroll: true)
      options = { skip_install: !enroll }
      result = SecurityProduct::DependabotOnActions.new(self).enable(actor: actor, options: options)
      result.value
    end

    def enable_dependabot_self_hosted(actor:, enroll: true)
      options = { skip_install: !enroll }
      result = SecurityProduct::DependabotSelfHosted.new(self).enable(actor: actor, options: options)
      result.value
    end

    def enable_dependabot_autofix(actor:, enroll: true)
      options = { skip_install: !enroll }
      result = SecurityProduct::DependabotAutofix.new(self).enable(actor: actor, options: options)
      result.value
    end

    def disable_vulnerability_updates(actor:)
      T.bind(self, Repository)
      SecurityProduct::ServiceManager.new(self).toggle_services_with_form_inputs(actor, params: { vulnerability_updates_enabled: "0" })
    end

    def disable_vulnerability_updates_grouping(actor:)
      result = SecurityProduct::VulnerabilityUpdatesGrouping.new(self).disable(actor: actor)
      result.value
    end

    def disable_dependabot_on_actions(actor:)
      result = SecurityProduct::DependabotOnActions.new(self).disable(actor: actor)
      result.value
    end

    def disable_dependabot_self_hosted(actor:)
      result = SecurityProduct::DependabotSelfHosted.new(self).disable(actor: actor)
      result.value
    end

    def disable_dependabot_autofix(actor:)
      result = SecurityProduct::DependabotAutofix.new(self).disable(actor: actor)
      result.value
    end

    def vulnerability_updates_enabled?
      SecurityProduct::VulnerabilityUpdates.new(self).enabled?
    end

    def vulnerability_updates_grouping_enabled?
      SecurityProduct::VulnerabilityUpdatesGrouping.new(self).enabled?
    end

    def vulnerability_updates_grouping_feature_enabled?
      SecurityProduct::VulnerabilityUpdatesGrouping.new(self).feature_enabled?
    end

    def dependabot_on_actions_enabled?
      SecurityProduct::DependabotOnActions.new(self).enabled?
    end

    def dependabot_on_actions_feature_enabled?
      SecurityProduct::DependabotOnActions.new(self).feature_enabled?
    end

    def dependabot_self_hosted_enabled?
      SecurityProduct::DependabotSelfHosted.new(self).enabled?
    end

    def dependabot_self_hosted_feature_enabled?
      SecurityProduct::DependabotSelfHosted.new(self).feature_enabled?
    end

    def dependabot_autofix_enabled?
      SecurityProduct::DependabotAutofix.new(self).enabled?
    end

    def dependabot_autofix_feature_enabled?
      SecurityProduct::DependabotAutofix.new(self).feature_enabled?
    end

  end
end
