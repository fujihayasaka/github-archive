# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  class FirewallAllowlist < ApplicationRecord::Copilot
    self.table_name = "copilot_firewall_allowlists"
    self.strict_loading_by_default = true

    belongs_to :resource, polymorphic: true, strict_loading: false
    belongs_to :organization, class_name: "::Organization", optional: true, strict_loading: false
    # rubocop:disable Rails/InverseOf
    belongs_to :updated_by, class_name: "::User", foreign_key: "updated_by_id", optional: true, strict_loading: false
    # rubocop:enable Rails/InverseOf

    validates :resource, presence: true
    validates :resource_type, inclusion: { in: %w[Business User Repository] }
    validates :rules, presence: true
    validate :validate_rules_format

    scope :for_organization, ->(org) { where(organization_id: org.id) }

    sig { params(resource: T.any(::Organization, ::Business, ::Repository)).returns(T.nilable(CopilotSweAgent::FirewallAllowlist)) }
    def self.for(resource)
      find_by(resource: resource)
    end

    private

    sig { void }
    def validate_rules_format
      return if rules.blank?

      unless rules.is_a?(Array)
        errors.add(:rules, "must be an array")
        return
      end

      rules.each do |rule|
        next if rule.is_a?(String) && rule.strip.empty?

        unless rule.is_a?(String)
          errors.add(:rules, "must contain only strings")
          return
        end

        valid, reason = CopilotSweAgent::FirewallRuleValidator.validate_rule(rule)
        unless valid
          errors.add(:rules, reason)
          return
        end
      end
    end
  end
end
