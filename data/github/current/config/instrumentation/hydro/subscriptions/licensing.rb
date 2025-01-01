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

  subscribe("business_licenses.snapshot") do |payload|
    business = payload[:business]

    message = ActiveRecord::Base.connected_to(role: :reading) do
      {
        request_context: serializer.request_context(GitHub.context.to_hash),
        business: serializer.business(business),
        max_enterprise_seats: business.seats,
        filled_enterprise_seats: business.consumed_enterprise_licenses,
        max_volume_seats: business.purchased_volume_licenses,
        filled_volume_seats: business.consumed_volume_licenses
      }
    end

    publish(message, schema: "github.billing.v0.LicenseSnapshot")
  end

  subscribe("business_team.enablement_toggled") do |payload|
    consuming_license = payload[:consuming_license]
    business_team = payload[:business_team]
    business = business_team.business

    message = ActiveRecord::Base.connected_to(role: :reading) do
      {
        request_context: serializer.request_context(GitHub.context.to_hash),
        consuming_license: consuming_license,
        product_sku: serializer.enum(
          type: Hydro::Schemas::Github::V1::BusinessTeamEnablementToggled::ProductSku,
          value: :SDLC,
          default: :SKU_UNKNOWN
        ),
        business_team_id: business_team.id,
        business_id: business.id,
        customer_id: business.customer_id,
      }
    end

    publish(message, schema: "github.v1.BusinessTeamEnablementToggled")
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
    repository_info = build_repository_licensing_info(payload[:repository_id])

    if !repository_info[:advanced_security_bundled]
      message = {
        repository_id: payload[:repository_id],
        feature_enabled: true,
        customer_id: repository_info[:customer_id],
        product_sku: serializer.enum(
          type: Hydro::Schemas::Github::Licensing::V0::AdvancedSecurityProductToggled::ProductSku,
          value: :SECRET_PROTECTION,
          default: :SKU_UNKNOWN
        ),
      }

      Hydro::PublishRetrier.publish(
        message,
        partition_key: payload[:repository_id],
        schema: "github.licensing.v0.AdvancedSecurityProductToggled",
        topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
      )
    end
  end

  subscribe("repository_secret_scanning.disable") do |payload|
    repository_info = build_repository_licensing_info(payload[:repository_id])

    if !repository_info[:advanced_security_bundled]
      message = {
        repository_id: payload[:repository_id],
        feature_enabled: false,
        customer_id: repository_info[:customer_id],
        product_sku: serializer.enum(
          type: Hydro::Schemas::Github::Licensing::V0::AdvancedSecurityProductToggled::ProductSku,
          value: :SECRET_PROTECTION,
          default: :SKU_UNKNOWN
        ),
      }

      Hydro::PublishRetrier.publish(
        message,
        partition_key: payload[:repository_id],
        schema: "github.licensing.v0.AdvancedSecurityProductToggled",
        topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
      )
    end
  end

  subscribe("repository_code_security.enable") do |payload|
    repository_info = build_repository_licensing_info(payload[:repository_id])

    if !repository_info[:advanced_security_bundled]
      message = {
        repository_id: payload[:repository_id],
        feature_enabled: true,
        customer_id: repository_info[:customer_id],
        product_sku: serializer.enum(
          type: Hydro::Schemas::Github::Licensing::V0::AdvancedSecurityProductToggled::ProductSku,
          value: :CODE_SECURITY,
          default: :SKU_UNKNOWN
        ),
      }

      Hydro::PublishRetrier.publish(
        message,
        partition_key: payload[:repository_id],
        schema: "github.licensing.v0.AdvancedSecurityProductToggled",
        topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
      )
    end
  end

  subscribe("repository_code_security.disable") do |payload|
    repository_info = build_repository_licensing_info(payload[:repository_id])

    if !repository_info[:advanced_security_bundled]
      message = {
        repository_id: payload[:repository_id],
        feature_enabled: false,
        customer_id: repository_info[:customer_id],
        product_sku: serializer.enum(
          type: Hydro::Schemas::Github::Licensing::V0::AdvancedSecurityProductToggled::ProductSku,
          value: :CODE_SECURITY,
          default: :SKU_UNKNOWN
        ),
      }

      Hydro::PublishRetrier.publish(
        message,
        partition_key: payload[:repository_id],
        schema: "github.licensing.v0.AdvancedSecurityProductToggled",
        topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
      )
    end
  end

  subscribe("advanced_security.enabled") do |payload|
    repository_info = build_repository_licensing_info(payload[:repository_id])

    if repository_info[:advanced_security_bundled]
      message = {
        repository_id: payload[:repository_id],
        feature_enabled: true,
        customer_id: repository_info[:customer_id],
        product_sku: serializer.enum(
          type: Hydro::Schemas::Github::Licensing::V0::AdvancedSecurityProductToggled::ProductSku,
          value: :ADVANCED_SECURITY,
          default: :SKU_UNKNOWN
        ),
      }

      Hydro::PublishRetrier.publish(
        message,
        partition_key: payload[:repository_id],
        schema: "github.licensing.v0.AdvancedSecurityProductToggled",
        topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
      )
    end
  end

  subscribe("advanced_security.disabled") do |payload|
    repository_info = build_repository_licensing_info(payload[:repository_id])

    if repository_info[:advanced_security_bundled]
      message = {
        repository_id: payload[:repository_id],
        feature_enabled: false,
        customer_id: repository_info[:customer_id],
        product_sku: serializer.enum(
          type: Hydro::Schemas::Github::Licensing::V0::AdvancedSecurityProductToggled::ProductSku,
          value: :ADVANCED_SECURITY,
          default: :SKU_UNKNOWN
        ),
      }

      Hydro::PublishRetrier.publish(
        message,
        partition_key: payload[:repository_id],
        schema: "github.licensing.v0.AdvancedSecurityProductToggled",
        topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
      )
    end
  end
end

module Hydro::EventForwarder::LicensingExtensions
  extend T::Helpers
  requires_ancestor { Hydro::EventForwarder }

  sig { params(repository_id: Integer).returns(T::Hash[Symbol, T.untyped]) }
  def build_repository_licensing_info(repository_id)
    repo = Repository.find_by(id: repository_id)
    billable_entity = repo&.owner&.advanced_security_billable_entity
    advanced_security_bundled = repo&.advanced_security_products_bundled?
    customer_id = billable_entity ? Licensing::Customer.id_for(billable_entity) : nil
    {
      advanced_security_bundled: advanced_security_bundled,
      customer_id: customer_id,
    }
  end
end

class Hydro::EventForwarder
  include Hydro::EventForwarder::LicensingExtensions
end
