# typed: true
# frozen_string_literal: true

class Copilot::CopilotSpaces::SuggestedCollaboratorsController < ApplicationController
  include CopilotSpaces::FeaturePreviewRedirect

  before_action :require_copilot_spaces_feature_enabled
  before_action :login_required
  before_action :require_space_admin_access
  before_action :require_org_owned_space, unless: :search_all_users_requested?
  before_action :require_xhr

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab

  def index
    json_for_suggestions = autocomplete_query.map do |suggestion|
      if suggestion.is_a?(Team)
        json_for_team(suggestion)
      elsif suggestion.is_a?(User)
        json_for_user(suggestion)
      end
    end

    render(json: { suggestions: json_for_suggestions })
  end

  private

  def autocomplete_query
    if search_all_users_requested?
      # Global search: search all GitHub users, not just org members
      options = {
        include_teams: false,
        org_members_only: false
      }
    else
      # Default org-only search
      options = {
        organization: copilot_space.owner,
        include_teams: true,
        org_members_only: true
      }
    end

    query = AutocompleteQuery.new(current_user, params[:q], **options)
    query.suggestions
  end

  def search_all_users_requested?
    params[:all_users] == "true"
  end

  def name_for_suggestion(suggestion)
    if suggestion.respond_to?(:profile) && suggestion.profile.present?
      suggestion.profile.name
    else
      suggestion.name
    end
  end

  def json_for_team(suggestion)
    {
      team: {
        id: suggestion.id,
        slug: suggestion.slug,
        name: name_for_suggestion(suggestion),
        avatarUrl: suggestion.primary_avatar_url(40)
      }
    }
  end

  def json_for_user(suggestion)
    {
      user: {
        id: suggestion.id,
        login: suggestion.display_login,
        name: name_for_suggestion(suggestion),
        avatarUrl: suggestion.primary_avatar_url(40)
      }
    }
  end

  sig { returns(CopilotSpace) }
  memoize def copilot_space
    CopilotSpace.for_owner_login_and_number!(params[:owner], params[:number])
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def require_space_admin_access
    render_404 unless copilot_space.adminable_by?(current_user)
  end

  def require_org_owned_space
    render_404 unless copilot_space.owner.is_a?(Organization)
  end
end
