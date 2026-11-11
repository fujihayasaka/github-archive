# typed: true
# frozen_string_literal: true

class Stafftools::AuthorizationsController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  PAGE_LIMIT = 10

  before_action :ensure_user_exists
  before_action :ensure_authorization_exists

  layout "layouts/stafftools/user/security"

  def show
    accesses = OauthAccessTokens.domain.by_authorization_id_paginated(current_authorization.id, page: current_page, per_page: PAGE_LIMIT)

    render "stafftools/authorizations/show", locals: {
      accesses: accesses,
      application: current_authorization.application,
      authorization: current_authorization
    }
  end

  def destroy
    current_authorization.destroy_with_explanation(:site_admin, entry_point: :stafftools_authorizations_controller_destroy)
    flash[:notice] = "Authorization for '#{current_authorization.application.name}' revoked"

    if current_authorization.integration_application_type?
      redirect_to authorizations_stafftools_user_apps_path(this_user)
    else
      redirect_to stafftools_user_applications_path(this_user)
    end
  end

  private

  def current_authorization
    @_authorization
  end

  def ensure_authorization_exists
    @_authorization = if params.key?(:app_id)
      integration_id = Integration.where(slug: params[:app_id]).pick(:id)
      if integration_id
        this_user.authorizations_for_kind("github_apps").find_by(application_id: integration_id, application_type: OauthAuthorization::INTEGRATION)
      end
    elsif params.key?(:application_id)
      this_user.oauth_authorizations.oauth_apps.find_by(application_id: params[:application_id])
    end

    render_404 unless @_authorization
  end
end
