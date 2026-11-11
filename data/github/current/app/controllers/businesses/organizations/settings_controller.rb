# typed: true
# frozen_string_literal: true

class Businesses::Organizations::SettingsController < Businesses::BusinessController
  include EnterpriseManagedUsersHelper

  before_action :business_owner_required, unless: :saml_identity_provider_setting?
  before_action :read_enterprise_sso_required, if: :saml_identity_provider_setting?
  before_action :only_accept_xhr_requests
  before_action :valid_setting_viewer_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    only: [:show]

  def show
    respond_to do |format|
      format.html_fragment do
        render Businesses::Organizations::SettingsComponent.new(
          business: this_business,
          setting: setting,
        ), layout: false, formats: :html
      end
      format.html do
        render Businesses::Organizations::SettingsComponent.new(
          business: this_business,
          setting: setting,
        ), layout: false
      end
    end
  end

  private

  def only_accept_xhr_requests
    return if request.xhr?

    respond_to do |format|
      format.html { return head :not_acceptable }
    end
  end

  def setting
    params[:setting].to_s
  end

  def valid_setting_viewer_required
    if setting == "members_can_view_dependency_insights"
      render_404 unless this_business&.dependency_insights_enabled_for?(current_user)
    end
  end

  def saml_identity_provider_setting?
    setting == "saml_identity_provider"
  end
end
