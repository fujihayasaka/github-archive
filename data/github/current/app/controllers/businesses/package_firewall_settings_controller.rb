# typed: true
# frozen_string_literal: true

# Server-side controller for the enterprise Package Firewall settings page.
# Renders the React SSR shell on GET, applies policy edits on PATCH.
class Businesses::PackageFirewallSettingsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::PackageFirewallHelper

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::PackageFirewallSettingsController#update",
  ].freeze

  allow_verified_fetch only: [:update]
  before_action :business_owner_required
  before_action :ensure_package_firewall_enabled
  before_action :parse_json_params, only: [:update]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:index, :update]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  # GET /enterprises/:slug/settings/policies/package_firewall
  def index
    policy_response = begin
      package_firewall_client.read_policy(enterprise_id: this_business.id)
    rescue PackageFirewall::Twirp::NotFoundError
      nil
    end

    overrides_response = begin
      package_firewall_client.list_package_override(enterprise_id: this_business.id)
    rescue PackageFirewall::Twirp::NotFoundError
      nil
    end

    respond_with_react(
      app_name: "package-firewall-enterprise-settings",
      payload: PackageFirewallPayload.new(
        policy: policy_response ? serialize_policy(policy_response) : {},
        allowed_packages: overrides_response ? serialize_package_identifiers(overrides_response, :allow_list) : [],
        blocked_packages: overrides_response ? serialize_package_identifiers(overrides_response, :deny_list) : [],
        viewer_can_administer: this_business.adminable_by?(current_user),
      ),
      title: "Package Firewall · #{this_business.name}",
      page_data: { selected_link: :business_package_firewall_settings, sidebar: :policies },
      layout: "react_business",
    )
  rescue PackageFirewall::Twirp::BaseError => err
    Failbot.report(err)
    render plain: "Internal Server Error", status: :internal_server_error
  end

  # PATCH /enterprises/:slug/settings/policies/package_firewall
  def update
    errors = validate_policy_params
    if errors.any?
      render json: { errors: errors }, status: :unprocessable_entity
      return
    end

    response = package_firewall_client.update_policy(
      enterprise_id: this_business.id,
      policy: policy_params,
    )

    this_business.instrument(:update_package_firewall_policy, {
      actor: current_user,
      policy: policy_params,
    })

    render json: { policy: serialize_policy(response) }, status: :ok
  rescue PackageFirewall::Twirp::InvalidArgumentError => err
    render json: { errors: [{ field: "policy", message: err.msg }] }, status: :unprocessable_entity
  rescue PackageFirewall::Twirp::BaseError => err
    Failbot.report(err)
    render json: { error: "Failed to update package firewall policy" }, status: :internal_server_error
  end

  # Payload for the SSR React shell.
  class PackageFirewallPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "packageFirewallEnterpriseSettingsRoute"
    end

    sig do
      params(
        policy: T::Hash[Symbol, T.untyped],
        allowed_packages: T::Array[T::Hash[Symbol, T.untyped]],
        blocked_packages: T::Array[T::Hash[Symbol, T.untyped]],
        viewer_can_administer: T::Boolean,
      ).void
    end
    def initialize(policy:, allowed_packages:, blocked_packages:, viewer_can_administer:)
      @policy = policy
      @allowed_packages = allowed_packages
      @blocked_packages = blocked_packages
      @viewer_can_administer = viewer_can_administer
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def payload
      {
        policy: @policy,
        allowedPackages: @allowed_packages,
        blockedPackages: @blocked_packages,
        viewerCanAdminister: @viewer_can_administer,
      }
    end
  end
end
