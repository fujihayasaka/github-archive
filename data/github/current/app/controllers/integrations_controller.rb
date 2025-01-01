# typed: true
# frozen_string_literal: true

class IntegrationsController < ApplicationController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  before_action :reject_applications_owned_by_spammy!

  stylesheet_bundle :integrations

  helper_method :current_integration

  def show
    if current_integration.readable_by?(current_user)
      render "integrations/show"
    else
      render "integrations/show_restricted"
    end
  end

  private

  memoize def current_integration
    Integration.from_owner_and_slug!(
      viewer:        current_user,
      slug:          integration_slug,
      user_login:    owner_slug,
      business_slug: params[:slug],
    )
  end

  def target_for_conditional_access
    current_integration.owner
  end

  def integration_slug
    return params[:id] if GitHub::UTF8.valid_unicode3?(params[:id])

    # Scrub the invalid unicode so it doesn't trip Site::HeaderView#currently_viewed_user either
    params[:id] = GitHub::UTF8.scrubbed_unicode3(params[:id])
    nil
  end

  def owner_slug
    return unless params[:owner]

    GitHub::UTF8.valid_unicode3?(params[:owner]) ? params[:owner] : nil
  end

  def reject_applications_owned_by_spammy!
    render_404 if current_integration.hide_from_user?(current_user)
  end
end
