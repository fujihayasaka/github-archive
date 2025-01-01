# typed: strict
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("licensing.bundled_license_assignment_association_changed") do |payload|
    message = {
      change_type: serializer.enum(
        type: Hydro::Schemas::Github::Licensing::V0::BundledLicenseAssignmentAssociationChanged::ChangeType,
        value: payload[:change_type],
        default: :UNKNOWN
      ),
      subscription_id: payload[:subscription_id],
      business: serializer.business(payload[:business]),
      user_id: payload[:user_id],
      previous_user_id: payload[:previous_user_id]
    }
    publish(message, schema: "github.licensing.v0.BundledLicenseAssignmentAssociationChanged")
  end

  subscribe("business_team.enablement_toggled") do |payload|
    consuming_license = payload[:consuming_license]
    business_team = payload[:business_team]
    business = business_team.business
    product_sku = :SDLC

    message = ActiveRecord::Base.connected_to(role: :reading) do
      {
        request_context: serializer.request_context(GitHub.context.to_hash),
        consuming_license: consuming_license,
        product_sku: serializer.enum(
          type: Hydro::Schemas::Github::V1::BusinessTeamEnablementToggled::ProductSku,
          value: product_sku,
          default: :SKU_UNKNOWN
        ),
        business_team_id: business_team.id,
        business_id: business.id,
        customer_id: business.customer_id,
      }
    end

    publish(
      message,
      key: "#{business_team.id}:#{product_sku}",
      schema: "github.v1.BusinessTeamEnablementToggled",
    )
  end

  subscribe("external_identity.deprovision") do |payload|
    identity = payload[:identity]
    next unless identity.user&.is_enterprise_managed?

    message = {
      user_id: identity.user_id,
      business: serializer.business(identity.provider.business),
      suspended_at: identity.disabled_at,
    }
    publish(message, schema: "github.licensing.v0.EnterpriseManagedIdentitySuspended")
  end

  subscribe("external_identity.provision") do |payload|
    identity = payload[:identity]
    next unless identity.user&.is_enterprise_managed?

    message = {
      user_id: identity.user_id,
      business: serializer.business(identity.provider.business),
    }
    publish(message, schema: "github.licensing.v0.EnterpriseManagedIdentityUnsuspended")
  end

  subscribe("repository_secret_scanning.enable") do |payload|
    publish_advanced_security_product_toggled(payload[:repository_id], :SECRET_PROTECTION, true, false)
  end

  subscribe("repository_secret_scanning.disable") do |payload|
    publish_advanced_security_product_toggled(payload[:repository_id], :SECRET_PROTECTION, false, false)
  end

  subscribe("repository_code_security.enable") do |payload|
    publish_advanced_security_product_toggled(payload[:repository_id], :CODE_SECURITY, true, false)
  end

  subscribe("repository_code_security.disable") do |payload|
    publish_advanced_security_product_toggled(payload[:repository_id], :CODE_SECURITY, false, false)
  end

  subscribe("advanced_security.enabled") do |payload|
    publish_advanced_security_product_toggled(payload[:repository_id], :ADVANCED_SECURITY, true, true)
  end

  subscribe("advanced_security.disabled") do |payload|
    publish_advanced_security_product_toggled(payload[:repository_id], :ADVANCED_SECURITY, false, true)
  end

  subscribe("advanced_security_trial.toggled") do |payload|
    entity = if payload[:enterprise_id]
      Business.find_by(id: payload[:enterprise_id])
    elsif payload[:organization_id]
      Organization.find_by(id: payload[:organization_id])
    end

    # Update Licensify with the new customer data when GHAS converts between different states
    customer_id = Licensing::Customer.id_for(entity) if entity
    UpdateCustomerInLicensifyJob.perform_later(customer_id) if customer_id
  end
end

module Hydro::EventForwarder::LicensingExtensions
  extend T::Helpers
  requires_ancestor { Hydro::EventForwarder }

  sig { params(repository_id: Integer).returns(T::Hash[Symbol, T.untyped]) }
  def build_repository_licensing_info(repository_id)
    repo = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      T.cast(Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: repository_id)
    end

    billable_entity = repo&.owner&.advanced_security_billable_entity
    advanced_security_bundled = repo&.advanced_security_products_bundled?
    customer_id = billable_entity ? Licensing::Customer.id_for(billable_entity) : nil
    {
      advanced_security_bundled: advanced_security_bundled,
      customer_id: customer_id,
    }
  end

  sig { params(repository_id: Integer, product_sku: Symbol, feature_enabled: T::Boolean, requires_bundled: T::Boolean).void }
  def publish_advanced_security_product_toggled(repository_id, product_sku, feature_enabled, requires_bundled)
    repository_info = build_repository_licensing_info(repository_id)

    # Only publish if the bundling requirement matches
    return unless repository_info[:advanced_security_bundled] == requires_bundled

    message = {
      repository_id: repository_id,
      feature_enabled: feature_enabled,
      customer_id: repository_info[:customer_id],
      product_sku: serializer.enum(
        type: Hydro::Schemas::Github::Licensing::V0::AdvancedSecurityProductToggled::ProductSku,
        value: product_sku,
        default: :SKU_UNKNOWN
      ),
    }

    Hydro::PublishRetrier.publish(
      message,
      key: "#{repository_id}:#{product_sku}",
      schema: "github.licensing.v0.AdvancedSecurityProductToggled",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end
end

class Hydro::EventForwarder
  include Hydro::EventForwarder::LicensingExtensions
end
