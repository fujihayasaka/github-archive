# typed: true
# frozen_string_literal: true

class ExternalIntegrationsController < ApplicationController

  before_action :login_required
  before_action :require_multi_tenant_mode # Synchronized apps are only relevant on Proxima.
  before_action :require_owner_scoped_github_apps_feature_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Copilot,
    only: [:show]

  stylesheet_bundle :integrations

  helper_method :current_integration

  def show
    render "integrations/show"
  end

  private

  def require_multi_tenant_mode
    render_404 unless GitHub.multi_tenant_enterprise?
  end

  def require_owner_scoped_github_apps_feature_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:owner_scoped_github_apps, current_user, default: false)
  end

  memoize def current_integration
    Integration.find_external_app!(slug: integration_slug)
  end

  # Third-party apps on Proxima are owned by a special non-enterprise managed,
  # GitHub-owned organization on each Proxima stamp. The apps displayed by this
  # controller are intended to be installable by any Proxima customer and their
  # _real_ owner actually resides on Dotcom.
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def integration_slug
    # REF: https://github.com/github/github/pull/316920
    return params[:id] if GitHub::UTF8.valid_unicode3?(params[:id])

    # Scrub the invalid unicode so it doesn't trip Site::HeaderView#currently_viewed_user either
    params[:id] = GitHub::UTF8.scrubbed_unicode3(params[:id])
    nil
  end
end
