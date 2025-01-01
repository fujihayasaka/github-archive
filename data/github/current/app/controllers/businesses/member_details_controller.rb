# typed: true
# frozen_string_literal: true

class Businesses::MemberDetailsController < Businesses::BusinessController
  extend T::Sig

  include TwoFactorRequirementHelper

  before_action :login_required
  before_action :business_owner_required

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::MemberDetailsController#index",
  ]

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
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
        contents[key] = render_member_details(details)
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
  #   item-0: { member_id: ID },
  #   item-1: { member_id: ID },
  #   ...
  # }
  def items
    params.require(:items).permit!.to_h
  end

  def keyed_details_from_items(items)
    member_ids = items.values.map { |item| item[:member_id]&.to_i }.compact.uniq
    details_by_member_id = \
      users(member_ids).each_with_object({}) do |member, details|
        # depending on the environment, member can be a User or a BusinessUserAccount.  If the latter, we need to resolve
        # to the underlying User.
        user = member.is_a?(BusinessUserAccount) ? member.user : member

        details[member.id] = {
          member: member,
          organizations_count: organizations_count_for(member),
          server_installations_count: server_installations_count_for(member),
          two_factor_enabled: two_factor_enabled?(user),
          active_account_two_factor_requirement: active_account_two_factor_requirement?(user),
          pending_account_two_factor_requirement: pending_account_two_factor_requirement?(user),
          account_two_factor_required_by_date: account_two_factor_required_by_date(user),
          license_type: license_type_for(member),
          cost_center: cost_center_for(user)
        }
      end

    items.transform_values do |member_params|
      details_by_member_id[member_params[:member_id]&.to_i]
    end
  end

  def users(member_ids)
    if GitHub.enterprise?
      this_business.filtered_members(current_user).where(id: member_ids)
    else
      this_business.user_accounts.where(id: member_ids).includes(:user)
    end
  end

  def organizations_count_for(member)
    this_business.enterprise_organizations_for(
      member: member, viewer: current_user
    ).count
  end

  def server_installations_count_for(member)
    return 0 if GitHub.single_business_environment? || member.nil?
    member.user_enterprise_installations.count
  end

  def license_type_for(member)
    user_id = case member
    when ::User
      member.id
    when ::BusinessUserAccount
      member.user_id
    end

    if volume_license_user_ids.include?(user_id)
      "VS subscription"
    elsif non_volume_licensed_user_ids.include?(user_id)
      "Enterprise license"
    elsif member.is_a?(::BusinessUserAccount) && server_installations_count_for(member).positive?
      # user only exists on GHES installations
      "Enterprise license"
    elsif copilot_user_ids.include?(user_id)
      "Copilot license"
    else
      "Unlicensed"
    end
  end

  sig { params(member: T.nilable(User)).returns(T.nilable(String)) }
  def cost_center_for(member)
    return nil unless show_cost_center?(this_business)
    return "Unavailable" if this_business.cost_centers.nil?
    this_business.cost_center_for(member)
  end

  memoize def volume_license_user_ids
    license_attributer.bundled_license_assignment_user_ids
  end

  memoize def non_volume_licensed_user_ids
    all_license_user_ids - volume_license_user_ids
  end

  memoize def all_license_user_ids
    license_attributer.user_ids
  end

  memoize def copilot_user_ids
    this_business.copilot_user_ids
  end

  memoize def license_attributer
    Business::LicenseAttributer.new(this_business)
  end

  memoize def any_server_installations?
    return false if GitHub.single_business_environment?
    this_business.enterprise_installations.any?
  end

  def render_member_details(details)
    return "" unless details.present?

    render_to_string(
      partial: "businesses/people/list_item_details",
      formats: [:html],
      locals: {
        member: details[:member],
        organizations_count: details[:organizations_count],
        any_server_installations: any_server_installations?,
        server_installations_count: details[:server_installations_count],
        two_factor_enabled: details[:two_factor_enabled],
        active_account_two_factor_requirement: details[:active_account_two_factor_requirement],
        pending_account_two_factor_requirement: details[:pending_account_two_factor_requirement],
        account_two_factor_required_by_date: details[:account_two_factor_required_by_date],
        license_type: details[:license_type],
        show_cost_center: show_cost_center?(this_business),
        cost_center: details[:cost_center]
      }
    )
  end
end
