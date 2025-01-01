# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  class RuleShowComponent < ApplicationComponent
    extend T::Sig

    sig { returns T.nilable(Repository) }
    attr_reader :current_repository

    sig { returns T.nilable(User) }
    attr_reader :current_organization

    sig { returns VulnerabilityAlertRule }
    attr_reader :rule

    sig do
      params(
        rule: VulnerabilityAlertRule,
        current_repository: T.nilable(Repository),
        current_organization: T.nilable(User),
      ).void
    end
    def initialize(
      rule:,
      current_repository: nil,
      current_organization: nil
    )
      if current_repository.nil? && current_organization.nil?
        raise ArgumentError, "either current_repository or current_organization must be provided"
      elsif current_repository.present? && current_organization.present?
        raise ArgumentError, "only one of current_repository or current_organization can be provided"
      end

      @rule = rule
      @current_repository = current_repository
      @current_organization = current_organization
    end

    sig { returns(T.nilable(String)) }
    def enablement_label
      target = current_repository || current_organization
      return unless target

      rule.enablement_for_target(target).human_name
    end
  end
end
