# typed: true
# frozen_string_literal: true

class OauthAuthorizationsController < ApplicationController

  # We can safely skip the these filters, as we do not access any resources
  # scoped to an organization.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required

  javascript_bundle :oauth
  javascript_bundle :settings
  stylesheet_bundle :oauth

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  # It is preferable to synchronously revoke all accesses at once, so that the
  # accesses will already be gone when the user is redirected back to their
  # OAuth applications page. But, if the user has a large number of accesses, we
  # need to do it asynchronously in a job.
  MAXIMUM_ACCESSES_REVOKE_ALL = 100

  def show
    return redirect_to settings_user_applications_path unless current_authorization

    if current_authorization.integration_application_type?
      view = create_view_model(
        Oauth::AuthorizeIntegrationView,
        authorization: current_authorization,
        application: current_authorization.application
      )
      render "oauth_authorizations/show_integration", locals: { view: view }
    else
      view = create_view_model(
        Oauth::AuthorizeView,
        authorization: current_authorization,
        application: current_authorization.application
      )
      render "oauth_authorizations/show", locals: { view: view }
    end
  end

  def destroy
    return render_404 unless current_authorization
    current_authorization.destroy_with_explanation(:web_user, entry_point: :oauth_authorizations_controller_destroy)

    if request.xhr?
      head 200
    else
      respond_to do |format|
        format.html do
          application = current_authorization.application
          flash[:notice] = "#{current_authorization.safe_app.name} has been revoked from your account."
          options = {}
          # need sort from referrer url
          referrer_query = URI.parse(request.referrer).query
          if !referrer_query.nil?
            # get options from referrer
            options = CGI.parse(referrer_query)
            # options are an array, join them and comma separate the value
            options.each { |k, v| options[k] = v.map { |s| "#{s}" }.join(",") }
          end
          authorizations_index = if application.is_a?(Integration)
            settings_user_app_authorizations_path(options)
          else
            settings_user_applications_path(options)
          end
          redirect_to authorizations_index
        end
      end
    end
  end

  def report # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_authorization && GitHub.user_abuse_mitigation_enabled?
    app = current_authorization.safe_app
    if params[:revoke]
      current_authorization.destroy_with_explanation(:web_user, entry_point: :oauth_authorizations_controller_report)
      flash[:notice] = "#{app.name} has been revoked from your account."
    end

    render "oauth_authorizations/report_redirect",
      locals: { redirect_url: flavored_contact_path(flavor: "report-abuse", report: "#{app.name} #{app.id} (oauth app)") },
      layout: "layouts/redirect"
  end

  def revoke_all # rubocop:todo GitHub/UseRestfulActions
    if params[:type] == "github_apps"
      type = :github_apps
      accesses = current_user.oauth_accesses.github_apps
      display_type = "GitHub Apps"
    else
      type = :third_party
      accesses = current_user.oauth_accesses.third_party
      display_type = "OAuth Apps"
    end

    if accesses.count > MAXIMUM_ACCESSES_REVOKE_ALL
      current_user.async_revoke_oauth_tokens(type)
      flash[:notice] = "Revoking access for all #{display_type}"
    else
      current_user.revoke_oauth_tokens(type, entry_point: :oauth_authorizations_controller_revoke_all)
      flash[:notice] = "Revoked access for all #{display_type}"
    end

    if type == :github_apps
      redirect_to settings_user_app_authorizations_path
    else
      redirect_to settings_user_applications_path
    end
  end

  private

  def current_authorization # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @current_authorization ||= begin
      client_id_type = Integration.client_id_type(params[:client_id])

      if client_id_type != :none
        auth = current_user.oauth_authorizations
          .joins(:integration)
          .where(integrations: { key: params[:client_id] })
          .first

        if client_id_type == :v1
          auth
        elsif GitHub.flipper[:globally_unique_client_ids].enabled?(auth&.application&.owner)
          auth
        end
      else
        current_user.oauth_authorizations
          .joins(:oauth_application)
          .where(oauth_applications: { key: params[:client_id] })
          .first
      end
    end
  end
end
