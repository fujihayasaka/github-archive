# typed: strict
# frozen_string_literal: true

class OrganizationOnboarding::TrialBannerController < ApplicationController
  include OrganizationsHelper

  before_action :ensure_user_logged_in
  before_action :ensure_not_emu
  before_action :ensure_billing_enabled_in_instance
  before_action :ensure_organization_exists
  before_action :require_organization_admin
  before_action :only_accept_xhr_requests
  before_action :without_active_global_notice

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  # Renders an appropriate trial banner for the current user, if the user is an org admin, and has no active global
  # notices. We should consider moving the enterprise cloud trial banner out of the global user notice, and into this
  # fragment.
  sig { void }
  def show
    billable_entity = this_organization&.advanced_security_billable_entity

    respond_to do |format|
      format.html_fragment do
        render AdvancedSecurity::TrialBannerComponent.new(
          billable_entity:,
          user: current_user,
          organization: this_organization,
          test_selector: "advanced-security-trial-banner",
        ), layout: false, formats: :html
      end
      format.html do
        render AdvancedSecurity::TrialBannerComponent.new(
          billable_entity:,
          user: current_user,
          organization: this_organization,
          test_selector: "advanced-security-trial-banner",
        ), layout: false
      end
    end
  end

  private

  sig { returns(T.nilable(Business)) }
  memoize def business
    return nil unless org = this_organization
    org.business
  end

  sig { void }
  def without_active_global_notice
    global_notice = current_user.global_notice.name
    return if global_notice.nil? || global_notice == "no_notice" || global_notice == "enterprise_cloud_trial"

    respond_to do |format|
      format.html_fragment { return head :ok }
      format.html { return head :ok }
    end
  end

  sig { void }
  def only_accept_xhr_requests
    return if request.xhr?

    respond_to do |format|
      format.html { return head :not_acceptable }
    end
  end

  sig { void }
  def require_organization_admin
    return unless org = this_organization
    return if org.adminable_by?(current_user)

    respond_to do |format|
      format.html_fragment { return head :ok }
      format.html { return head :ok }
    end
  end

  sig { returns(T.nilable(Organization)) }
  memoize def this_organization
    Organization.find_by(login: params[:org])
  end

  sig { void }
  def ensure_user_logged_in
    return if current_user

    respond_to do |format|
      format.html_fragment { return head :ok }
      format.html { return head :ok }
    end
  end

  sig { void }
  def ensure_organization_exists
    return if this_organization

    respond_to do |format|
      format.html_fragment { return head :ok }
      format.html { return head :ok }
    end
  end

  sig { void }
  def ensure_billing_enabled_in_instance
    return if GitHub.billing_enabled?
    respond_to do |format|
      format.html_fragment { return head :ok }
      format.html { return head :ok }
    end
  end

  sig { void }
  def ensure_not_emu
    return unless current_user.is_enterprise_managed?
    respond_to do |format|
      format.html_fragment { return head :ok }
      format.html { return head :ok }
    end
  end
end
