# typed: strict
# frozen_string_literal: true

# These are Hydro event subscriptions related to Billing Platform.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("billing_platform.metered_usage") do |payload|
    metered_usage = payload
    quantity = T.let(nil, T.nilable(Float))
    quantity = metered_usage[:quantity].to_f if metered_usage[:quantity].is_a?(Numeric)
    entity = metered_usage[:entity]
    metered_usage_message = {
      sku:  metered_usage[:sku],
      quantity: quantity,
      usage_at:  Google::Protobuf::Timestamp.new(seconds: metered_usage[:usage_at].to_i, nanos: 0),
      source_uri: metered_usage[:source_uri],
      entity: {
        customer_id: entity[:customer_id],
        organization_id: entity[:organization_id],
        repo_id: entity[:repo_id],
        actor_id: entity[:actor_id],
      },
    }
    publish(metered_usage_message, schema: "billingplatform.v1.Usage")
  end

  subscribe("billing.plan_change") do |payload|
    user = User.find_by(id: payload[:user_id])
    customer = user&.customer
    if customer && customer.billed_via_billing_platform?
      ::Billing::UpdateCustomerInBillingPlatformJob.perform_later(customer)
    end
  end

  subscribe("enterprise_account.organization_remove") do |payload|
    organization = Organization.find_by id: payload[:organization_id]
    if organization && organization.feature_flag_enabled_or_raise?(:billing_org_ownership_change_events) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      enterprise = Business.find_by id: payload[:enterprise_id]
      if organization.customer.present? && enterprise.present?
        emit_org_ownership_change_event(
          organization: organization,
          source_customer_id: enterprise.customer_id,
          destination_customer_id: organization.customer&.id,
          actor_id: payload[:actor_id],
          completed_at: Time.now,
        )
      end
    end
  end

  subscribe("enterprise_account.organization_add") do |payload|
    if !payload[:new_organization]
      organization = Organization.find_by id: payload[:organization_id]
      if organization && organization.feature_flag_enabled_or_raise?(:billing_org_ownership_change_events) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        enterprise = Business.find_by id: payload[:enterprise_id]
        if organization.customer.present? && enterprise.present?
          emit_org_ownership_change_event(
            organization: organization,
            source_customer_id: organization.customer&.id,
            destination_customer_id: enterprise.customer_id,
            actor_id: payload[:actor_id],
            completed_at: Time.now,
          )
        end
      end
    end
  end

  subscribe("enterprise_account.organization_upgrade") do |payload|
    if payload[:status] == :PURCHASE_UPGRADED
      organization = Organization.find_by id: payload[:organization_id]
      if organization && organization.feature_flag_enabled_or_raise?(:billing_org_ownership_change_events) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        enterprise = Business.find_by id: payload[:enterprise_id]
        if organization.customer.present? && enterprise.present?
          emit_org_ownership_change_event(
            organization: organization,
            source_customer_id: organization.customer&.id,
            destination_customer_id: enterprise.customer_id,
            actor_id: payload[:actor_id],
            completed_at: Time.now,
          )
        end
      end
    end
  end

  subscribe("enterprise_account.organization_transfer") do |payload|
    if payload[:failed_at].nil?
      organization = Organization.find_by id: payload[:organization_id]

      if organization && organization.feature_flag_enabled_or_raise?(:billing_org_ownership_change_events) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        source_enterprise = Business.find_by id: payload[:source_enterprise_id]
        destination_enterprise = Business.find_by id: payload[:destination_enterprise_id]

        if source_enterprise.present? && destination_enterprise.present?
          emit_org_ownership_change_event(
            organization: organization,
            source_customer_id: source_enterprise.customer_id,
            destination_customer_id: destination_enterprise.customer_id,
            actor_id: payload[:actor_id],
            completed_at: payload[:completed_at],
          )
        end
      end
    end
  end
end

module Hydro::EventForwarder::BillingExtensions
  extend T::Helpers
  requires_ancestor { Hydro::EventForwarder }

  sig { params(organization: Organization, source_customer_id: T.nilable(Integer), destination_customer_id: T.nilable(Integer), actor_id: T.nilable(Integer), completed_at: T.nilable(Time)).void }
  def emit_org_ownership_change_event(organization:, source_customer_id:, destination_customer_id:, actor_id:, completed_at:)
    repository_info = get_repositories_visibilities(organization)

    message = {
      organization_id: organization.id,
      actor_id: actor_id,
      source_customer_id: source_customer_id,
      destination_customer_id: destination_customer_id,
      completed_at: completed_at,
      repositories: repository_info,
    }

    Hydro::PublishRetrier.publish(message, schema: "billingplatform.v1.OrgOwnershipChange")
  end

  sig { params(organization: Organization).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def get_repositories_visibilities(organization)
    repo_ids = organization.repositories.pluck(:id)
    repos = Repository.includes(:internal_repository)
      .select(:id, :source_id, :public)
      .where(id: repo_ids)

    repos.map do |repo|
      visibility = case repo.visibility.to_sym
      when :public
        Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility.lookup(
         Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility::PUBLIC
        )
      when :private
        Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility.lookup(
          Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility::PRIVATE
        )
      when :internal
        Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility.lookup(
          Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility::INTERNAL
        )
      else
        GitHub.logger.info(
          "billing_repo_visibility: Unexpected unknown repository visibility",
          "gh.repo.visibility" => repo.visibility.to_sym,
          "gh.repo.id" => repo.id,
        )

        Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility.lookup(
          Hydro::Schemas::Billingplatform::V1::Entities::RepositoryVisibility::VISIBILITY_UNKNOWN
        )
      end

      {
        id: repo.id,
        visibility: visibility,
      }
    end
  end
end

class Hydro::EventForwarder
  include Hydro::EventForwarder::BillingExtensions
end
