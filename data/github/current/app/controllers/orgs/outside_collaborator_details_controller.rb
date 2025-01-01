# typed: true
# frozen_string_literal: true

class Orgs::OutsideCollaboratorDetailsController < Orgs::Controller
  include TwoFactorRequirementHelper

  before_action :login_required
  before_action :organization_admin_required

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::OutsideCollaboratorDetailsController#index",
  ]

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    only: %i(index)

  def index
    keyed_contents = ActiveRecord::Base.connected_to(role: :reading) do
      keyed_objects = keyed_details_from_items(items)
      keyed_objects.each_with_object({}) do |(key, details), contents|
        contents[key] = render_outside_collaborator_details(details)
      end
    end

    respond_to do |wants|
      wants.json do
        render json: keyed_contents
      end
    end
  rescue ActionController::ParameterMissing
    head :bad_request
  end

  private

  # Expects params as follows:
  #
  # params[:items] = {
  #   item-0: { outside_collaborator_id: ID },
  #   item-1: { outside_collaborator_id: ID },
  #   ...
  # }
  def items
    params.require(:items).permit!.to_h
  end

  def keyed_details_from_items(items)
    outside_collaborator_ids = items.values.map { |item| item[:outside_collaborator_id]&.to_i }.compact.uniq
    details_by_outside_collaborator_id = \
      this_organization.outside_collaborators
        .where(id: outside_collaborator_ids).each_with_object({}) do |collaborator, details|
        details[collaborator.id] = {
          collaborator: collaborator,
          show_2fa: show_2fa?,
          two_factor_enabled: two_factor_enabled?(collaborator),
          active_account_two_factor_requirement: active_account_two_factor_requirement?(collaborator),
          pending_account_two_factor_requirement: pending_account_two_factor_requirement?(collaborator),
          account_two_factor_required_by_date: account_two_factor_required_by_date(collaborator),
        }
      end

    items.transform_values do |collaborator_params|
      details_by_outside_collaborator_id[collaborator_params[:outside_collaborator_id]&.to_i]
    end
  end

  def render_outside_collaborator_details(details)
    return "" unless details.present?

    render_to_string(
      partial: "orgs/outside_collaborators/list_item_details",
      formats: [:html],
      locals: {
        outside_collaborator: details[:collaborator],
        show_2fa: details[:show_2fa],
        two_factor_enabled: details[:two_factor_enabled],
        active_account_two_factor_requirement: details[:active_account_two_factor_requirement],
        pending_account_two_factor_requirement: details[:pending_account_two_factor_requirement],
        account_two_factor_required_by_date: details[:account_two_factor_required_by_date],
      },
    )
  end

  def show_2fa?
    return false if this_organization.scim_managed_enterprise?
    this_organization.adminable_by?(current_user) && GitHub.auth.two_factor_authentication_enabled?
  end
end
