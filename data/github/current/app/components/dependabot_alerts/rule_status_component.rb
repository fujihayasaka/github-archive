# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  class RuleStatusComponent < ApplicationComponent
    extend T::Sig

    sig { returns(T.any(User, Repository)) }
    attr_reader :target

    sig { returns(VulnerabilityAlertRule) }
    attr_reader :rule

    sig { params(rule: VulnerabilityAlertRule, target: T.any(Repository, User)).void }
    def initialize(rule:, target:)
      @rule = rule
      @target = target
    end

    sig { returns(T.nilable(String)) }
    def status
      enablement.human_name
    end

    sig { returns(Symbol) }
    def scheme
      if enablement.force_enabled?
        :accent
      elsif enablement.enabled?
        :success
      else
        :default
      end
    end

    sig { returns(VulnerabilityAlertRule::Enablement) }
    memoize def enablement
      rule.enablement_for_target(target)
    end
  end
end
