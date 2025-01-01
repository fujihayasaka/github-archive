# typed: true
# frozen_string_literal: true

class InProductMessagingOrganizationDismissNoticeController < ApplicationController
  depends_on_clusters ApplicationRecord::Domain::Users,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities

  before_action :login_required

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = %w[
    InProductMessagingOrganizationDismissNoticeController#create
  ].freeze

  # POST /in-product-messaging/organization-dismiss-notice
  # Dismisses a notice for an organization and redirects to destination URL based on key lookup
  def create
    notice = params[:notice]
    group = params[:group].present? ? params[:group].to_sym : nil
    org_id = params[:organization_id].present? ? params[:organization_id].to_i : nil

    if notice.present?
      # Use connected write role to avoid replication lag
      ActiveRecord::Base.connected_to(role: :writing) do
        if org_id
          if (org = Organization.find_by(id: org_id))
            current_user.dismiss_organization_notice(
              notice,
              org,
            )
          end
        end

        current_user.track_nudge_dismissal(id: notice, group: group, org_id: org_id)
      end
    end

    if request.xhr?
      head :ok
    else
      redirect_back(fallback_location: "/")
    end
  end

  private

  # Since we're only dismissing notices for the current user, return current_user as the target
  def resource_for_conditional_access
    return :no_target_for_conditional_access unless logged_in?
    return :no_target_for_conditional_access if GitHub::DeniedLogins.include? current_user.display_login.downcase
    current_user
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
