# typed: true
# frozen_string_literal: true

class Hovercards::IntegrationsController < ApplicationController
  include Hovercards::ConditionalAccessMethods

  before_action :require_xhr, only: :show
  before_action :find_current_integration!, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    render "hovercards/integrations/show", locals: {
      current_integration: current_integration,
      app_url: app_url,
      truncated_description: truncated_description,
      installation_user: installation_user,
      installation_org: installation_org,
      is_authorized_agent: is_authorized_agent?
    }, layout: false
  end

  private

  def find_current_integration!
    render_404 unless current_integration
  end

  memoize def current_integration
    agents.find { |agent| agent[:slug] == integration_slug }
  end

  def target_for_conditional_access
    if current_integration
      current_integration.owner
    else
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end

  def is_authorized_agent?
    IntegrationAgent.integrations_authorized_for_user(current_user).include?(current_integration)
  end

  def integration_slug
    return params[:id] if GitHub::UTF8.valid_unicode3?(params[:id])

    # Scrub the invalid unicode so it doesn't trip Site::HeaderView#currently_viewed_user either
    params[:id] = GitHub::UTF8.scrubbed_unicode3(params[:id])
    nil
  end

  memoize def agents
    return @agents if @agents
    @agents = helpers.get_integration_agents(sso_organizations)
  end

  memoize def app_url
    if current_integration.marketplace_listing.present?
      marketplace_listing_path(integration_slug)
    else
      gh_app_path(current_integration, current_user)
    end
  end

  memoize def sso_organizations
    orgs = Organization.where(id: saml_for_user.protected_organization_ids)

    orgs.map do |org|
      {
        id: org.id.to_s,
        login: org.display_login,
        avatarUrl: org.primary_avatar_url
      }
    end
  end

  memoize def truncated_description
    return current_integration.description if current_integration.description.length <= 150
    current_integration.description[0, 150] + "..."
  end

  memoize def installation_user
    current_user&.display_login if current_integration.installed_on?(current_user)
  end

  memoize def installation_org
    org_installation = current_integration.installations.find { |org| org.target.type == "Organization" }
    org_installation.target.display_login if org_installation.present?
  end
end
