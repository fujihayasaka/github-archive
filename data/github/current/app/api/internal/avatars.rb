# typed: false
# frozen_string_literal: true

# API endpoints for getting a list of avatars for a given user or organization.
# This is used by the avatar proxy to display the first valid avatar behind
# an unchanging and cacheable URL.
#
# https://github.com/github/alambic/tree/master/docs/avatars
class Api::Internal::Avatars < Api::Internal

  # TODO: Remove this preview dependency
  require_api_semantic_version "drstrange"

  # Returns the prioritized list of avatars for a user
  get "/internal/user/:user_id/avatars", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    deliver_avatar_list find_user!
  end

  # Returns the prioritized list of avatars for an OauthApplication
  get "/internal/oauth-applications/:app_id/avatars", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    app = OauthApplication.find_by_id(params[:app_id].to_i)
    return deliver_error!(404) if app.nil?
    deliver_avatar_list app
  end

  # Returns the prioritized list of avatars for an Integration
  get "/internal/integrations/:integration_id/avatars", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    integration = Integration.find_by_id(params[:integration_id].to_i)
    return deliver_error!(404) if integration.nil?
    deliver_avatar_list integration
  end

  # Returns the prioritized list of avatars for an org
  get "/internal/organizations/:org_id/avatars", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    deliver_avatar_list find_org!
  end

  # Returns the prioritized list of avatars for a team
  get "/internal/teams/:team_id/avatars", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    team = record_or_404(Team.find_by_id(int_id_param!(key: :team_id)))
    deliver_avatar_list team
  end

  # Returns the prioritized list of avatars for a business
  get "/internal/businesses/:business_id/avatars", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    business = record_or_404(Business.find_by(id: int_id_param!(key: :business_id)))
    deliver_avatar_list business
  end

  # Returns the prioritized list of avatars for a user by email
  get "/internal/user/avatars", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    email = params[:email].to_s.strip.downcase
    user = ActiveRecord::Base.connected_to(role: :reading) { User.find_by_email(email) } ||
      User.new(email: email, gravatar_email: email)
    deliver_avatar_list user
  end

  def deliver_avatar_list(owner)
    headers[HEADER_SURROGATE_KEY] = owner.avatar_list.surrogate_key
    headers[HEADER_TIMING] = GitHub.url

    items = use_fallback?(owner) ? [] : owner.avatar_list.items

    deliver_raw items
  end

  def use_fallback?(owner)
    fallback = GitHub.alambic_fallback_user
    return false if fallback.nil?
    return true if fallback == owner.try(:login)
    false
  end

  HEADER_SURROGATE_KEY = "Surrogate-Key".freeze
  HEADER_TIMING = "Timing-Allow-Origin".freeze
end
