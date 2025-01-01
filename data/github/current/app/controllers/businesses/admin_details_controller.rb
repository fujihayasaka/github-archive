# typed: true
# frozen_string_literal: true

class Businesses::AdminDetailsController < Businesses::BusinessController
  include TwoFactorRequirementHelper

  before_action :login_required
  before_action :business_owner_required

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::AdminDetailsController#index",
  ]

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: %i(index)

  def index
    keyed_contents = ActiveRecord::Base.connected_to(role: :reading) do
      keyed_objects = keyed_details_from_items(items)
      keyed_objects.each_with_object({}) do |(key, details), contents|
        contents[key] = render_admin_details(details)
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
  #   item-0: { admin_id: ID },
  #   item-1: { admin_id: ID },
  #   ...
  # }
  def items
    params.require(:items).permit!.to_h
  end

  def keyed_details_from_items(items)
    admin_ids = items.values.map { |item| item[:admin_id]&.to_i }.compact.uniq
    details_by_admin_id = \
      this_business.admins.where(id: admin_ids).each_with_object({}) do |admin, details|
        details[admin.id] = {
          admin: admin,
          two_factor_enabled: two_factor_enabled?(admin),
          active_account_two_factor_requirement: active_account_two_factor_requirement?(admin),
          pending_account_two_factor_requirement: pending_account_two_factor_requirement?(admin),
          account_two_factor_required_by_date: account_two_factor_required_by_date(admin),
        }
      end

    items.transform_values do |admin_params|
      details_by_admin_id[admin_params[:admin_id]&.to_i]
    end
  end

  memoize def any_server_installations?
    return false if GitHub.single_business_environment?
    this_business.enterprise_installations.any?
  end

  def render_admin_details(details)
    return "" unless details.present?

    render_to_string(
      partial: "businesses/admins/list_item_details",
      formats: [:html],
      locals: {
        business: this_business,
        admin: details[:admin],
        role: this_business.role_for(details[:admin]),
        any_server_installations: any_server_installations?,
        two_factor_enabled: details[:two_factor_enabled],
        active_account_two_factor_requirement: details[:active_account_two_factor_requirement],
        pending_account_two_factor_requirement: details[:pending_account_two_factor_requirement],
        account_two_factor_required_by_date: details[:account_two_factor_required_by_date],
      }
    )
  end
end
