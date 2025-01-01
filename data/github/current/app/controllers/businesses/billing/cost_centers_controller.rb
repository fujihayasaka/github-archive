# typed: strict
# frozen_string_literal: true

class Businesses::Billing::CostCentersController < Businesses::BillingsController
  include ApplicationController::VerifiedFetchDependency
  include Billing::Platform::Api::Utils
  include Businesses::Billing::Concerns::CostCenters

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index, :show, :new, :edit]

  allow_verified_fetch only: [:index, :create, :update, :destroy]

  before_action :set_organizations, only: [:new, :edit]
  before_action :validate_resources, only: [:create, :update]

  rescue_from Billing::Platform::Api::UpsertBudgetRequest::InvalidRequestError do
    render json: { error: "Invalid request" }, status: 400
  end

  sig { returns(String) }
  def self.react_bundle_name
    "billing-app"
  end

  sig { void }
  def index
    render_cost_centers_index(layout: "react_business")
  end

  sig { void }
  def show
    render_cost_center_show(layout: "react_business")
  end

  sig { void }
  def new
    render_react_app payload: {
      adminRoles: admin_roles(this_business),
      customer: customer_payload(this_business),
      subscriptions: available_azure_subscriptions,
      uri: azure_auth_uri(action: :new),
      isCopilotStandalone: this_business.copilot_licensing_enabled?,
    }, page_data: { selected_link: :business_billing_vnext_cost_centers }, title: "New Cost Center", layout: "react_business", ssr: true
  end

  sig { void }
  def create
    cost_centers = billing_platform_client.get_all_cost_centers(customer_id: customer_id)[:costCenters].select { |cc| cc[:costCenterState] == :CostCenterActive }
    resources = resources_without_relay_id(create_params[:resources])
    if has_overlapping_resources?(cost_centers, resources)
      return render json: { error: "Selected resources belong to an existing cost center" }, status: 400
    end
    response = billing_platform_client.create_cost_center(
        customer_id: customer_id,
        name: create_params[:name],
        resources: resources,
        target_id: create_params[:targetId],
        target_type: cost_center_target_type,
      )
    if response.is_a?(Billing::Platform::Api::Error)
      instrument_create_cost_center("error", response.message)

      return render json: { error: response.original_error.msg.capitalize }, status: 500
    end

    instrument_create_cost_center("success")
    render_react_app payload: {}, ssr: true
  rescue => e # rubocop:todo Lint/GenericRescue
    Failbot.report(e)
    render json: { error: "Unable to create cost center" }, status: 500
  end

  sig { void }
  def edit
    cost_center_response = billing_platform_client.get_cost_center(cost_center_key: {
      customerId: customer_id,
      uuid: cost_center_uuid
    })
    if cost_center_response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to load cost center (#{cost_center_response.original_error})" }, status: 500
    end

    render_react_app payload: {
      adminRoles: admin_roles(this_business),
      customer: customer_payload(this_business),
      costCenter: hydrate_with_relay_id(cost_center_response[:costCenter]),
      uri: azure_auth_uri(action: :edit),
      subscriptions: available_azure_subscriptions,
      isCopilotStandalone: this_business.copilot_licensing_enabled?,
    }, page_data: { selected_link: :business_billing_vnext_cost_centers }, title: "Edit Cost Center", layout: "react_business", ssr: true
  end

  sig { void }
  def update
    cost_centers = billing_platform_client.get_all_cost_centers(customer_id: customer_id)[:costCenters].select { |cc| cc[:costCenterState] == :CostCenterActive }
    cost_centers_without_current = cost_centers.reject { |cc| cc[:uuid] == update_params[:uuid] }
    if has_overlapping_resources?(cost_centers_without_current, resources_without_relay_id(update_params[:resourcesToAdd]))
      return render json: { error: "One or more selected resources are already associated to a Cost Center" }, status: 400
    end
    response = billing_platform_client.update_cost_center(
        key: {
          customer_id: customer_id,
          target_id: update_params[:originalTargetId].to_s,
          target_type: cost_center_target_type,
          uuid: update_params[:uuid],
        },
        target_id: update_params[:targetId].to_s,
        name: update_params[:name],
        resources_to_add: resources_without_relay_id(update_params[:resourcesToAdd]),
        resources_to_remove: resources_without_relay_id(update_params[:resourcesToRemove]),
      )
    if response.is_a?(Billing::Platform::Api::Error)
      instrument_update_cost_center("error", response.message)
      return render json: { error: response.original_error.msg.capitalize }, status: 500
    end

    instrument_update_cost_center("success")
    render_react_app payload: {}, ssr: true
  rescue => e # rubocop:todo Lint/GenericRescue
    Failbot.report(e)
    render json: { error: "Unable to update cost center" }, status: 500
  end

  sig { void }
  def destroy
    cost_center_response = billing_platform_client.archive_cost_center(cost_center_key: {
      customerId: customer_id,
      uuid: cost_center_uuid.to_s,
    })

    audit_log_payload = {
      business: this_business,
      customer_id: this_business.customer_id.to_s,
      uuid: cost_center_uuid.to_s,
    }
    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to delete cost center" }, status: 500
    end

    GitHub.instrument "billing.cost_center_delete", audit_log_payload.merge({ status: "success" })
    render_react_app payload: {}, ssr: true
  end

  sig { void }
  def list # rubocop:disable GitHub/UseRestfulActions
    cost_centers_response = billing_platform_client.get_all_cost_centers(customer_id: customer_id)
    if cost_centers_response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to load cost centers" }, status: 500
    end

    cost_centers = cost_centers_response[:costCenters]

    render json: cost_centers
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def create_params
    ActionController::Parameters.new(json_body).permit(
      :name,
      :targetId,
      :uuid,
      resources: [:id, :type],
    ).to_h
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def update_params
    ActionController::Parameters.new(json_body).permit(
      :name,
      :originalTargetId,
      :targetId,
      resourcesToAdd: [:id, :type],
      resourcesToRemove: [:id, :type],
    ).to_h.merge(uuid: params[:id])
  end

  sig { returns(T::Hash[String, T.untyped]) }
  memoize def json_body
    ActiveSupport::JSON.decode(T.must(request).body.read)
  end

  # Filter cost centers by org ownership
  sig { override.params(cost_centers: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def filter_cost_centers(cost_centers)
    cost_centers.reject do |c|
      case admin_role
      when "enterprise_org_owner"
        resource_types = c[:resources].map { |r| r[:type] }.uniq.compact
        !resource_types.include?(:Repo)
      end
    end
  end

  sig { void }
  def validate_resources
    resources = if action_name == "create"
      resources_without_relay_id(create_params[:resources])
    else
      resources_without_relay_id(update_params[:resourcesToAdd] | update_params[:resourcesToRemove])
    end

    if resources.any? { |r| get_target_entity_from_id(target_type: r[:type], target_id: r[:id]).nil? }
      return render json: { error: "Invalid target" }, status: 400
    end

    any_resources_not_owned_by_user = resources.group_by { |r| r[:type] }.any? do |type, entries|
      !targets_owned_by_user?(
        target_type: type,
        target_ids: entries.map { |e| e[:id] },
        current_user: current_user,
        this_entity: this_business
      )
    end

    if any_resources_not_owned_by_user
      render_404
    end
  end

  sig { params(status: String, error: T.nilable(String)).void }
  def instrument_create_cost_center(status, error = nil)
    args = {
      user: current_user,
      customer_id: customer_id,
      business: this_business,
      name: create_params[:name],
      resources_count: create_params[:resources].length,
      target_id: create_params[:targetId],
      status: status,
    }
    args[:error_message] = error if error

    GitHub.instrument "billing.cost_center_create", args
  end

  sig { params(status: String, error: T.nilable(String)).void }
  def instrument_update_cost_center(status, error = nil)
    args = {
     actor: current_user,
      customer_id: customer_id,
      business: this_business,
      name: update_params[:name],
      added_resources_count: update_params[:resourcesToAdd].length,
      removed_resources_count: update_params[:resourcesToRemove].length,
      target_id: update_params[:targetId],
      uuid: update_params[:uuid],
      status: status,
    }
    args[:error_message] = error if error

    GitHub.instrument "billing.cost_center_update", args
  end

  sig { params(existing_cost_centers: T::Array[T::Hash[Symbol, T.untyped]], resources: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Boolean) }
  def has_overlapping_resources?(existing_cost_centers, resources)
    # Get all repo IDs in the upsert cost center data.
    # We also combine all the upserted org repos into the repo IDs array
    # as we want to only check collisions on repo IDs to make the logic simpler.
    incoming_repo_ids = resources.filter_map { |resource| resource[:id].to_i if resource[:type] == "Repo" }
    incoming_org_ids = resources.filter_map { |resource| resource[:id].to_i if resource[:type] == "Org" }

    # Find if resources on the upsert data already exist in existing cost center resources.
    # To do this, we grab repo and org IDs from the existing cost center and add all the org
    # repo IDs to the repo ID list. This allows us to verify scenarios where I am trying to create a cost
    # center with a repo but there is already a cost center with that repo's org.
    existing_resources = existing_cost_centers.map { |cost_center| cost_center[:resources] }.flatten
    existing_repo_ids = existing_resources.filter_map { |resource| resource[:id].to_i if resource[:type] == :Repo }
    existing_org_ids = existing_resources.filter_map { |resource| resource[:id].to_i if resource[:type] == :Org }

    # Add all cost center org repo IDs to the repo ID list to check for overlaps
    Organization.where(id: incoming_org_ids).each do |org|
      incoming_repo_ids.push(*org.repositories.pluck(:id))
    end
    Organization.where(id: existing_org_ids).each do |org|
      existing_repo_ids.push(*org.repositories.pluck(:id))
    end

    repo_ids_overlap = !(incoming_repo_ids & existing_repo_ids).empty?
    repo_ids_overlap
  end
end
