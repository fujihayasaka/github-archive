# typed: true
# frozen_string_literal: true

class Businesses::Organizations::OrganizationCardComponent < ApplicationComponent
  include HydroHelper

  def initialize(
    business:,
    organization:,
    show_options: false,
    subtitle: "",
    render_repo_and_member_details: false,
    render_role_in_organization: false,
    viewer_organization_ability: nil,
    transfer_in_progress: false,
    transfer_failed_recently: false
  )
    @business = business
    @organization = organization
    @show_options = show_options
    @subtitle = subtitle
    @render_repo_and_member_details = render_repo_and_member_details
    @render_role_in_organization = render_role_in_organization
    @viewer_organization_ability = viewer_organization_ability
    @transfer_in_progress = transfer_in_progress
    @transfer_failed_recently = transfer_failed_recently
  end

  private

  def render?
    @business.present? && @organization.present? && logged_in?
  end

  def org_click_hydro_attributes
    hydro_click_tracking_attributes(
      "enterprise_account.profile_organization_click", {
        enterprise_id: @business.id,
        organization_id: @organization.id,
        actor_id: current_user.id
      }
    )
  end

  def show_options_dialog?
    return false unless @show_options
    return false unless @business.owner?(current_user)

    true
  end

  def render_repo_and_member_details?
    @render_repo_and_member_details && @business.owner?(current_user)
  end

  def current_user_owner_of_organization?
    @viewer_organization_ability.to_s == "admin"
  end

  def current_user_member_of_organization?
    %w[read admin].include?(@viewer_organization_ability.to_s)
  end

  def transfer_in_progress?
    @transfer_in_progress
  end

  def transfer_failed_recently?
    @transfer_failed_recently
  end

  def render_repos_count?
    !@repos_count.nil?
  end
end
