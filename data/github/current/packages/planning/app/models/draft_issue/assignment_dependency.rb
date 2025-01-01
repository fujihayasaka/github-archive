# typed: true
# frozen_string_literal: true

module DraftIssue::AssignmentDependency
  extend T::Helpers
  extend T::Sig
  requires_ancestor { DraftIssue }
  extend ActiveSupport::Concern

  def assigned_to?(user)
    return false unless user

    @_assigned_to ||= Hash.new do |hash, key|
      hash[key] = assignees.include?(key)
    end
    @_assigned_to[user]
  end

  # new_assignees - The Array of Users that will replace the existing list of
  #                 assignees. This should include ALL assignees you
  #                 wish to add or keep.
  #
  # Returns an Array of Users
  def assignees=(new_assignees)
    previous_assignees = assignees.reload
    removed_assignees = previous_assignees - (new_assignees || []).compact.uniq
    removed_assignments = self.assignments.where(assignee: removed_assignees).to_a

    super(new_assignees)

    new_assignees
  end

  sig { params(current_user: T.nilable(User)).returns(T::Array[MemexProjectCollaborator]) }
  def sorted_assignees_list(current_user:)
    @sorted_assignees_list ||= {}
    @sorted_assignees_list[current_user] ||= begin
      collaborators = memex_project.collaborators(current_user).filter_map do |collaborator|
        collaborator.actor if collaborator.actor.is_a?(User)
      end

      unsorted_list = if memex_project.org_owned?
        org_members = memex_project.owner.visible_users_for(current_user).includes(:profile)
        org_members + collaborators
      else
        collaborators + [memex_project.owner]
      end

      # We are calling uniq here because a given user might be part of the
      # collaborators and also an org member or owner of the project.
      list = unsorted_list.to_a.uniq.sort_by(&:display_login)

      # ensure all existing assignees are at the top of the list.
      list = assignees + (list - assignees)

      # if the current_user is assignable, pull it to the top of the list.
      if current_user && user = list.delete(current_user)
        list.unshift(user)
      end

      list
    end
  end

  def filtered_assignees_list(current_user, search_query)
    sanitized_query = ActiveRecord::Base.sanitize_sql_like(search_query)

    User
      .where(id: sorted_assignees_list(current_user: current_user))
      .filter_spam_for(current_user)
      .like_login_or_profile_name(sanitized_query)
      .by_login
  end
end
