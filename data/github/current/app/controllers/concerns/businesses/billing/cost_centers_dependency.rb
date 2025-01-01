# typed: strict
# frozen_string_literal: true

module Businesses::Billing::CostCentersDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include Billing::Platform::Api::Utils
  include BillingSettingsHelper
  include Businesses::AzureSubscriptions

  requires_ancestor { ApplicationController }

  abstract!

  sig { params(layout: T.nilable(String), is_stafftools_route: T::Boolean).void }
  def render_cost_centers_index(layout: nil, is_stafftools_route: false)
    active_cost_centers = []
    archived_cost_centers = []
    error = nil

    cost_centers_response = billing_platform_client.get_all_cost_centers(customer_id: customer_id)
    if cost_centers_response.is_a?(Billing::Platform::Api::Error)
      error = cost_centers_response.original_error
    else
      active_cost_centers = filter_cost_centers(
        cost_centers_response[:costCenters].select { |cc| cc[:costCenterState] == :CostCenterActive }
      )
      archived_cost_centers = filter_cost_centers(
        cost_centers_response[:costCenters].select { |cc| cc[:costCenterState] == :CostCenterArchived }
      )
    end

    has_user_scoped_cost_centers = this_business.user_scoped_cost_centers?

    payload = {
      activeCostCenters: active_cost_centers,
      adminRoles: admin_roles(this_business),
      archivedCostCenters: archived_cost_centers,
      customer: customer_payload(this_business),
      hasUserScopedCostCenters: has_user_scoped_cost_centers,
      billingAddCostCenterDescription: FeatureFlag.vexi.enabled?(:billing_add_cost_center_description, this_business, default: false)
    }
    # Surface access errors (from redirects) to the React app as a simple flag
    payload.merge!(orgOwnerAccessDenied: true) if flash[:react_cost_center_access_denied].present?
    payload.merge!(error: error) if error.present?

    kwargs = {
      payload: payload,
      page_data: { selected_link: :business_billing_vnext_cost_centers, sidebar: :billing_and_licensing },
      title: "#{this_business.name} | Cost Centers",
    }
    kwargs.merge!(layout: layout) if layout.present?

    render_react_app(**kwargs)
  rescue => e # rubocop:todo Lint/RescueException
    Failbot.report(e)
    render json: { error: "Unable to query cost centers" }, status: 500
  end

  sig { params(layout: T.nilable(String)).void }
  def render_cost_center_show(layout: nil)
    cost_center_response = billing_platform_client.get_cost_center(cost_center_key: {
      customerId: customer_id,
      uuid: cost_center_uuid
    })

    if cost_center_response.is_a?(Billing::Platform::Api::Error)
      render_react_app payload: { error: cost_center_response.original_error }
      return
    end

    cost_center = hydrate_with_relay_id(cost_center_response[:costCenter])

    kwargs = {
      payload: {
        costCenter: cost_center,
        customer: customer_payload(this_business),
        encodedAzureSubscriptionUri: azure_auth_uri(action: :edit),
        subscriptions: available_azure_subscriptions,
        isCopilotStandalone: this_business.copilot_licensing_enabled?,
        billingAddCostCenterDescription: FeatureFlag.vexi.enabled?(:billing_add_cost_center_description, this_business, default: false)
      },
      page_data: { selected_link: :business_billing_vnext_cost_centers, sidebar: :billing_and_licensing },
      title: "#{this_business.name} | #{cost_center[:name]}",
    }
    kwargs.merge!(layout: layout) if layout.present?

    render_react_app(**kwargs)
  rescue => e # rubocop:todo Lint/RescueException
    Failbot.report(e)
    render_react_app payload: { error: "Unable to query cost center" }
  end

  protected

  sig { returns(T.any(Integer, String)) }
  def cost_center_uuid
    params.require(:id)
  end

  sig { returns(String) }
  def customer_id
    this_business.customer_id.to_s
  end

  sig { params(cost_center_response: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def hydrate_with_relay_id(cost_center_response)
    grouped_resources = cost_center_response[:resources].group_by { |r| r[:type] }
    converted_resources = grouped_resources.map { |type, group| batch_fetch_resources(type, group) }.flatten
    cost_center_response.merge({ resources: converted_resources })
  end

  sig { params(resources: T::Array[{ id: String, type: Symbol }]).returns(T::Array[{ id: String, type: Symbol }]) }
  def resources_without_relay_id(resources)
    resources.map { |r| { id: Platform::Helpers::GlobalId.parse(r[:id]).id.to_s, type: r[:type] } }
  end

  sig { params(type: Symbol, resource_group: T::Array[T::Hash[Symbol, T.untyped]]).returns(T.nilable(T::Array[{ id: String, type: Symbol }])) }
  def batch_fetch_resources(type, resource_group)
    ids = resource_group.map { |r| r[:id] }
    case type
    when :Org
      Organization.where(id: ids).collect { |org| { id: org.global_relay_id, type: type } }
    when :Repo
      Repository.where(id: ids).collect { |repo| { id: repo.global_relay_id, type: type } }
    when :User
      User.where(id: ids).collect { |user| { id: user.global_relay_id, type: type } }
    end
  end

  sig { returns(T::Array[T::Hash[Symbol, String]]) }
  def available_azure_subscriptions
    billing_target = T.must(this_business.customer).billing_platform_billing_target

    if params[:dialog] && billing_target == BillingPlatform::Api::V1::BillingTarget::Azure
      azure_subscriptions_client.fetch_subscriptions.map do |subscription|
        subscription.deep_transform_keys { |key| key.to_s.camelize(:lower) }
      end
    else
      []
    end
  end

  # TODO: Can we somehow use BillingPlatform::Api::V1::CostCenterType as an enum here?
  # BillingPlatform::Api::V1::CostCenterType.constants.map { |c| BillingPlatform::Api::V1::CostCenterType.const_get(c) }
  # gives the raw values but that's a lot of work just for that
  sig { returns(Integer) }
  def cost_center_target_type
    case T.must(this_business.customer).billing_platform_billing_target
    when BillingPlatform::Api::V1::BillingTarget::Azure
      BillingPlatform::Api::V1::CostCenterType::AzureSubscription
    when BillingPlatform::Api::V1::BillingTarget::Zuora
      BillingPlatform::Api::V1::CostCenterType::ZuoraSubscription
    else
      BillingPlatform::Api::V1::CostCenterType::NoCostCenter
    end
  end

  sig { params(action: Symbol).returns(URI) }
  def azure_auth_uri(action:)
    uri = URI("https://login.microsoftonline.com/common/oauth2/v2.0/authorize")
    redirect_path = action == :new ? new_enterprise_billing_cost_center_path(this_business.slug) : edit_enterprise_billing_cost_center_path(this_business.slug)
    state_hash = {
      business_slug: this_business.slug,
      explicit_tenant_selected: false,
      redirect_path: redirect_path,
    }

    if GitHub.multi_tenant_enterprise?
      # We pass the host name with tenant so the Azure redirects will work properly in all environments including Proxima where customers have custom subdomains
      GitHub.logger.info("Setting the host name for Azure auth redirect", "gh.business.slug" => this_business.slug, "gh.app.host" => GitHub.host_name_with_tenant)
      state_hash[:host_name] = GitHub.host_name_with_tenant
    end

    state_encoded = Base64.encode64(state_hash.to_json)

    uri.query = URI.encode_www_form({
      client_id: GitHub.azure_oauth_app_id,
      # "http://localhost/enterprises/oauth_callback"
      redirect_uri: GitHub.azure_oauth_app_redirect_uri_for_businesses,
      scope: "https://management.azure.com/user_impersonation",
      response_type: "code",
      state: state_encoded,
      response_mode: "query",
      prompt: "select_account"
    })
    uri
  end

  sig { abstract.returns(Business) }
  def this_business; end

  sig { abstract.returns(Billing::Platform::Api::Client) }
  def billing_platform_client; end

  # Optional additional filtering e.g. by owner
  sig { abstract.params(cost_centers: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def filter_cost_centers(cost_centers); end
end
