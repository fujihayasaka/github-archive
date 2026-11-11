# typed: strict
# frozen_string_literal: true

# Model for tracking security configurations that were set as default for private repos
# before a GHAS trial started. This table is used by the bulk disable service to skip
# updating default configs when the trial is a sales-led trial.
class SecurityProductsEnablement::PreGhasTrialDefaultPrivateRepoSecurityConfiguration < ApplicationRecord::Domain::SecurityProductsEnablement
  belongs_to :security_configuration

  belongs_to :target, polymorphic: true
  belongs_to :billing_entity, polymorphic: true

  validates :target_id, presence: true
  validates :target_type, presence: true
  validates :billing_entity_id, presence: true
  validates :billing_entity_type, presence: true
  validates :sku_name, presence: true
  validates :trial_type, presence: true

  # Enum for trial types
  enum :trial_type, {
    sales_led: 1,
    self_led: 2,
    dfd: 3
  }

  # Scope for filtering by billing entity and SKU name
  scope :for_billable_entity_and_sku, ->(billing_entity, sku_name) {
    where(
      billing_entity_id: billing_entity.id,
      billing_entity_type: billing_entity.is_a?(Business) ? "Business" : "User",
      sku_name: sku_name
    )
  }

  sig { params(billing_entity: T.untyped, sku_name: String, trial_type: T.any(String, Symbol)).void }
  def self.capture_default_private_repo_configurations(billing_entity:, sku_name:, trial_type:)
    clear_old_default_config_records(billing_entity: billing_entity, sku_name: sku_name)

    # Convert trial_type to integer for internal use
    trial_type_int = trial_types[trial_type.to_s]
    raise ArgumentError, "Invalid trial_type: #{trial_type}" unless trial_type_int

    captured_configs = []

    # Capture default configuration for the billing entity itself
    captured_config = find_and_capture_default_private_config(
      target_id: billing_entity.id,
      target_type: billing_entity.is_a?(Business) ? "Business" : "User",
      billing_entity: billing_entity,
      sku_name: sku_name,
      trial_type_int: trial_type_int
    )
    captured_configs << captured_config if captured_config

    # If billing entity is a Business, also capture defaults for each organization
    if billing_entity.is_a?(Business)
      billing_entity.organization_memberships.find_each do |org_membership|
        org_config = find_and_capture_default_private_config(
          target_id: org_membership.organization_id,
          target_type: "User",
          billing_entity: billing_entity,
          sku_name: sku_name,
          trial_type_int: trial_type_int
        )
        captured_configs << org_config if org_config
      end
    end
  end

  sig { params(target_id: Integer, target_type: String, billing_entity: T.any(Business, Organization), sku_name: String, trial_type_int: Integer).returns(T.nilable(SecurityProductsEnablement::PreGhasTrialDefaultPrivateRepoSecurityConfiguration)) }
  def self.find_and_capture_default_private_config(target_id:, target_type:, billing_entity:, sku_name:, trial_type_int:)
    default = SecurityConfigurationDefault
      .find_by(
        target_id: target_id,
        target_type: target_type,
        default_for_new_private_repos: true
      )

    if default&.security_configuration && sku_enabled_for_configuration?(T.must(default.security_configuration), billing_entity, sku_name)
      create!(
        security_configuration_id: default.security_configuration_id,
        target_id: target_id,
        target_type: target_type,
        billing_entity_id: billing_entity.id,
        billing_entity_type: billing_entity.is_a?(Business) ? "Business" : "User",
        sku_name: sku_name,
        trial_type: trial_type_int
      )
    end
  end

  sig { params(security_configuration: SecurityConfiguration, billing_entity: T.untyped, sku_name: String).returns(T::Boolean) }
  def self.sku_enabled_for_configuration?(security_configuration, billing_entity, sku_name)
    case sku_name
    when "secret_protection"
      security_configuration.secret_protection_sku_enabled(billable_entity: billing_entity) == true
    when "code_security"
      security_configuration.code_security_sku_enabled(billable_entity: billing_entity) == true
    else
      # For unknown SKUs, default to false to be safe
      false
    end
  end

  sig { params(billing_entity: T.untyped, sku_name: String).void }
  def self.clear_old_default_config_records(billing_entity:, sku_name:)
    records_to_delete = self.for_billable_entity_and_sku(billing_entity, sku_name)

    count_to_delete = records_to_delete.count

    Rails.logger.info "PreGhasTrialDefaultPrivateRepoSecurityConfiguration: Deleting #{count_to_delete} old default config records for billing_entity_id=#{billing_entity.id}, sku_name=#{sku_name}"

    records_to_delete.delete_all
  end
end
