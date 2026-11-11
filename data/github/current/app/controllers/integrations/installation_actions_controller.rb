# typed: true
# frozen_string_literal: true

# This powers the "Install" button on the GitHub Apps main landing page.
# Example: https://github.com/apps/stale

class Integrations::InstallationActionsController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  before_action :reject_applications_owned_by_spammy!

  def show
    view = create_view_model(Integrations::SelectTargetView, integration: current_integration, page: 1)
    render "integrations/installation_actions/show", locals: { view: view }, layout: false
  end

  private

  memoize def current_integration
    return Integration.find_external_app!(slug: params[:id]) if installing_external_app?

    Integration.from_owner_and_slug!(
      viewer:        current_user,
      slug:          params[:id],
      user_login:    params[:owner],
      business_slug: params[:slug],
    )
  end

  # TODO: This method is duplicated in IntegrationInstallationsController. If
  # you ever feel tempted to duplicated this code then it's time to extract it.
  def installing_external_app?
    return false unless GitHub.multi_tenant_enterprise?

    app_prefix = GitHub.enterprise? ? "github-apps" : "apps"
    external_app_path = "/#{app_prefix}/#{GitHub.proxima_external_apps_owner_slug}"

    request.path.start_with?(external_app_path)
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access if installing_external_app? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    current_integration.owner
  rescue ActiveRecord::RecordNotFound
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def reject_applications_owned_by_spammy!
    render_404 if current_integration&.hide_from_user?(current_user)
  end
end
