# typed: true
# frozen_string_literal: true

class Memexes::Settings::SuggestedCollaboratorsController < Memexes::Controller
  include MemexesHelper

  before_action :login_required
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_admin_access

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    only: [:index],
    optional: true

  def index
    json_for_suggestions = valid_suggestions.map do |suggestion|
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
    options = if memex_owner.organization?
      { organization: memex_owner, include_teams: true, org_members_only: true, include_outside_collaborators: true }
    elsif current_user.is_enterprise_managed?
      { business: current_user.enterprise_managed_business }
    else
      { include_teams: false, org_members_only: false }
    end
    AutocompleteQuery.new(current_user, params[:q], **options)
  end

  def valid_suggestions
    all_suggestions = autocomplete_query.suggestions
    prefill_args = { memex_owner: memex_owner, viewer: current_user }

    teams = all_suggestions.select { |suggestion| suggestion.is_a?(Team) }
    GitHub::PrefillAssociations.prefill_batch_method(teams, :can_be_added_to_memex_project?, prefill_args)

    users = all_suggestions.select { |suggestion| suggestion.is_a?(User) }
    GitHub::PrefillAssociations.prefill_batch_method(users, :can_be_added_to_memex_project?, prefill_args)

    all_suggestions.select do |suggestion|
      !suggestion.respond_to?(:can_be_added_to_memex_project?) ||
        suggestion.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: current_user)
    end
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
end
