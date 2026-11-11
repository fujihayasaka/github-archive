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
    publish(message, publisher: licensing_hydro_publisher, schema: "github.licensing.v0.BundledLicenseAssignmentAssociationChanged")
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
      publisher: licensing_hydro_publisher,
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
    publish(message, publisher: licensing_hydro_publisher, schema: "github.licensing.v0.EnterpriseManagedIdentitySuspended")
  end

  subscribe("external_identity.provision") do |payload|
    identity = payload[:identity]
    next unless identity.user&.is_enterprise_managed?

    message = {
      user_id: identity.user_id,
      business: serializer.business(identity.provider.business),
    }
    publish(message, publisher: licensing_hydro_publisher, schema: "github.licensing.v0.EnterpriseManagedIdentityUnsuspended")
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

  subscribe(::Copilot::Events::COPILOT_LICENSE_ENABLEMENT_TOGGLED) do |payload|
    entity_type = payload[:assignable_entity_type]
    entity_id = payload[:assignable_entity_id]
    customer_id = payload[:customer_id]
    message = {
      assignable_entity_type: entity_type,
      assignable_entity_id: entity_id,
      customer_id: customer_id,
      is_enabled: payload[:is_enabled],
      actor: payload[:actor] ? Hydro::EntitySerializer.user(payload[:actor]) : nil,
      effective_at: Google::Protobuf::Timestamp.new(seconds: payload[:effective_at].to_i),
      pending_cancellation_date: payload[:pending_cancellation_date] ? Google::Protobuf::Timestamp.new(seconds: payload[:pending_cancellation_date].to_i) : nil,
      plan_name: payload[:plan_name],
      plan_owner_type: payload[:plan_owner_type],
      plan_owner_id: payload[:plan_owner_id],
      trial_plan: payload[:trial_plan],
      trial_end_date: payload[:trial_end_date] ? Google::Protobuf::Timestamp.new(seconds: payload[:trial_end_date].to_i) : nil,
      business_team_ids: payload[:business_team_ids] || [],
      is_disable_seat_management_enablement: payload[:is_disable_seat_management_enablement] || false,
    }

    publish(
      message,
      publisher: licensing_hydro_publisher,
      key: "#{customer_id}:#{entity_type}:#{entity_id}",
      schema: "github.licensing.v0.CopilotLicenseEnablementToggled",
    )
  end

  subscribe("repository_transfer.completed") do |payload|
    previous_billable_entity = payload[:previous_owner].advanced_security_billable_entity
    new_billable_entity = payload[:target].advanced_security_billable_entity
    previous_customer_id = Licensing::Customer.id_for(previous_billable_entity) if previous_billable_entity
    new_customer_id = Licensing::Customer.id_for(new_billable_entity) if new_billable_entity

    message = {
      repository_id: payload[:repository].id,
      previous_customer_id: previous_customer_id,
      new_customer_id: new_customer_id,
      actor: payload[:requestor].present? ? serializer.user(payload[:requestor]) : nil,
    }

    publish(
      message,
      publisher: licensing_hydro_publisher,
      key: message[:repository_id],
      schema: "github.licensing.v0.RepositoryTransferred",
    )
  end
end

module Hydro::EventForwarder::LicensingExtensions
  extend T::Helpers
  requires_ancestor { Hydro::EventForwarder }

  sig { returns(T.untyped) }
  def licensing_hydro_publisher
    if FeatureFlag.vexi.enabled?("licensing_sync_hydro_publisher", default: false)
      GitHub.sync_hydro_publisher
    else
      GitHub.hydro_publisher
    end
  end

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
      publisher: licensing_hydro_publisher,
      key: "#{repository_id}:#{product_sku}",
      schema: "github.licensing.v0.AdvancedSecurityProductToggled",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end
end

class Hydro::EventForwarder
  include Hydro::EventForwarder::LicensingExtensions
end
