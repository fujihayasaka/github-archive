# typed: true
# frozen_string_literal: true

class Api::GitHubApps < Api::App

  get "/app/:app_id", operation_id: "apps/get-by-slug" do
    app = find_app!
    org = app.owner if app.owner.organization? && app.private?

    control_access :github_app_viewer,
      resource: app,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # This doesn't currently have any effect since the org is not defined in the URL request
      # Passing this to ensure that any changes to these checks does not enforce OAP
      # unless the app is private
      enforce_oauth_app_policy: app.private?

    if app.private? && org &&
      requestor_governed_by_oauth_application_policy? && !org.allows_oauth_application?(current_app_via_oauth)

      log_oap_restriction(oauth_app: current_app_via_oauth, org: org)
      error_options = {
        message: oauth_policy_error_message(org),
        documentation_url: @documentation_url,
      }
      deliver_error!(403, error_options)
    end

    deliver :integration_hash, app
  end

  private

  def find_app!
    if (app = env[GitHub::Routers::Api::ThisAppKey])
      app
    else
      app = Integration.find_by(id: params[:app_id])
      record_or_404(app)
    end

    # An app should not be present in the database without an owner.
    #
    # If we hit this case, it's either a cross-tenant request or
    # an orphaned app.
    deliver_error!(404) unless app.owner.present?

    app
  end
end
