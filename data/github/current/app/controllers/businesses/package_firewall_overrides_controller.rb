# typed: true
# frozen_string_literal: true

# Server-side controller for the per-package allow/deny overrides on the
# enterprise Package Firewall settings page.
class Businesses::PackageFirewallOverridesController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::PackageFirewallHelper

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::PackageFirewallOverridesController#create",
    "Businesses::PackageFirewallOverridesController#destroy",
  ].freeze

  allow_verified_fetch only: [:index, :create, :destroy]
  before_action :business_owner_required
  before_action :ensure_package_firewall_enabled
  before_action :parse_json_params, only: [:create, :destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:index, :create, :destroy]

  # GET /enterprises/:slug/settings/policies/package_firewall/overrides
  def index
    override_type = params[:type]
    unless VALID_OVERRIDE_TYPES.include?(override_type)
      render json: { errors: [{ field: "type", message: "must be one of: #{VALID_OVERRIDE_TYPES.join(", ")}" }] },
        status: :unprocessable_entity
      return
    end

    response = package_firewall_client.list_package_override(enterprise_id: this_business.id)
    list_key = override_type == "allow" ? :allow_list : :deny_list

    render json: serialize_package_identifiers(response, list_key), status: :ok
  rescue PackageFirewall::Twirp::BaseError => err
    Failbot.report(err)
    render json: { error: "Failed to list overrides" }, status: :internal_server_error
  end

  # POST /enterprises/:slug/settings/policies/package_firewall/overrides
  def create
    errors = validate_override_params
    if errors.any?
      render json: { errors: errors }, status: :unprocessable_entity
      return
    end

    identifier = package_identifier_from_params
    override_type = params[:type]

    allow_list = override_type == "allow" ? [identifier] : []
    deny_list = override_type == "deny" ? [identifier] : []

    response = package_firewall_client.add_package_override(
      enterprise_id: this_business.id,
      allow_list: allow_list,
      deny_list: deny_list,
    )

    this_business.instrument(:add_package_firewall_override, {
      actor: current_user,
      override: identifier.merge(type: override_type),
    })

    list_key = override_type == "allow" ? :allow_list : :deny_list
    render json: serialize_package_identifiers(response, list_key), status: :created
  rescue PackageFirewall::Twirp::InvalidArgumentError => err
    render json: { errors: [{ field: "override", message: err.msg }] }, status: :unprocessable_entity
  rescue PackageFirewall::Twirp::BaseError => err
    Failbot.report(err)
    render json: { error: "Failed to add override" }, status: :internal_server_error
  end

  # POST /enterprises/:slug/settings/policies/package_firewall/overrides/delete
  def destroy
    errors = validate_override_params
    if errors.any?
      render json: { errors: errors }, status: :unprocessable_entity
      return
    end

    identifier = package_identifier_from_params
    override_type = params[:type]

    allow_list = override_type == "allow" ? [identifier] : []
    deny_list = override_type == "deny" ? [identifier] : []

    response = package_firewall_client.delete_package_override(
      enterprise_id: this_business.id,
      allow_list: allow_list,
      deny_list: deny_list,
    )

    this_business.instrument(:delete_package_firewall_override, {
      actor: current_user,
      override: identifier.merge(type: override_type),
    })

    list_key = override_type == "allow" ? :allow_list : :deny_list
    render json: serialize_package_identifiers(response, list_key), status: :ok
  rescue PackageFirewall::Twirp::NotFoundError
    render_404
  rescue PackageFirewall::Twirp::BaseError => err
    Failbot.report(err)
    render json: { error: "Failed to delete override" }, status: :internal_server_error
  end
end
