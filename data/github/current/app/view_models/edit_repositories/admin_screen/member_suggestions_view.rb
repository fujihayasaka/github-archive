# typed: true
# frozen_string_literal: true

class EditRepositories::AdminScreen::MemberSuggestionsView < AutocompleteView
  include EnterpriseManagedUsersHelper
  include GitHub::Memoizer

  attr_reader :repository
  attr_reader :add_type

  def suggested_members
    if repository.organization.nil?
      # for user owned repos, do not suggest to add the repo owner as collaborator
      suggestions.to_a.delete_if do |suggestion|
        suggestion.is_a?(User) && suggestion.id == repository.owner.id
      end
    elsif repository.is_enterprise_managed? && repository.organization&.business&.emu_repository_collaborators_enabled?
      suggestions.to_a.delete_if do |suggestion|
        # remove members from other emus from sugestions
        suggestion.is_a?(User) && (suggestion.enterprise_managed_business != current_user.enterprise_managed_business)
      end
    elsif cannot_invite_outside_collaborators?
      #remove outside collaborators from sugestions
      suggestions.to_a.delete_if do |suggestion|
        suggestion.is_a?(User) && !repository.organization.member?(suggestion)
      end
    else
      suggestions
    end
  end

  memoize def org_member_ids
    org = repository.organization
    if org && org.member?(current_user)
      org.member_ids(actor_ids: suggested_user_ids)
    else
      []
    end
  end

  memoize def repo_member_ids
    repository.member_ids(actor_ids: suggested_user_ids)
  end

  def repo_team_ids
    suggested_team_ids & repository.actor_ids_for_team_on_repo
  end

  memoize def admin_ids
    org = repository.organization
    if org && org.member?(current_user)
      org.admin_ids
    else
      []
    end
  end

  memoize def invitees
    repository.invitees
  end

  def cannot_invite_outside_collaborators?
    repository.cannot_invite_outside_collaborators?(current_user)
  end

  def no_search_results_text
    entity = case add_type.to_sym
    when :user
      "a GitHub account"
    when :team
      "a team"
    else
      "a GitHub account or team"
    end
    "Could not find #{entity} matching #{query}"
  end

  def include_teams?
    add_type.to_sym == :team
  end

  def normalized_query
    if add_type.to_sym == :team
      "#{repository.owner.display_login}/#{query}"
    else
      query
    end
  end

  # Public: Overide for AutocompleteView#email_invitation?, which is
  # delegated to AutocompleteQuery.
  #
  # This override ensures that when querying teams and a user-entered query
  # of "@myteam" is provided, queries such as "myorg/@myteam" returned by
  # #normalized_query are not treated as emails.
  #
  # Returns Boolean
  def email_invitation?
    # Deliberately use query and not normalized_query when checking email query
    !suggestions? && User.valid_email?(query) && !query.start_with?("mailto:")
  end

  def can_send_email_invitation?
    GitHub.email_invitations_enabled?
  end

  def invitation_label(suggestion)
    return if org_member?(suggestion) && !repo_member?(suggestion)

    label = ""
    label += "•" if suggestion.profile_name.present?
    label += if repo_member?(suggestion)
      "Already has access to this repository"
    elsif invited?(suggestion)
      "Has a pending invitation to this repository"
    elsif !org_member?(suggestion) && repo_emu_enabled?
      "Add repository collaborator"
    elsif !org_member?(suggestion) && repo_in_organization?
      "Invite #{outside_collaborators_verbiage(repository.organization).singularize}"
    elsif !org_member?(suggestion) && !repo_in_organization?
      "Invite collaborator"
    else
      ""
    end
  end

  def repo_member?(suggestion)
    repo_member_ids.include?(suggestion.id)
  end

  def invited?(suggestion)
    invitees.include?(suggestion)
  end

  def org_member?(suggestion)
    org_member_ids.include?(suggestion.id)
  end

  private

  memoize def repo_in_organization?
    repository.in_organization?
  end

  memoize def repo_emu_enabled?
    repository.is_enterprise_managed? && repository.organization&.business&.emu_repository_collaborators_enabled?
  end

  def autocomplete_query
    @autocomplete_query ||= AutocompleteQuery.new(
      current_user,
      normalized_query,
      organization: repository.organization,
      repository: repository,
      include_teams: include_teams?,
      business: repository.owner&.enterprise_managed_business
    )
  end

  def suggested_user_ids
    suggested_members.select { |s| s.is_a?(User) }.map(&:id)
  end

  def suggested_team_ids
    suggested_members.select { |s| s.is_a?(Team) }.map(&:id)
  end
end
