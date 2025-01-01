# typed: false
# frozen_string_literal: true

module InteractionBanHelper
  include ActionView::Helpers::DateHelper

  def interaction_ban_copy(repo, user, action = "comment", tooltip = false)
    RepositoryInteractionAbility.interaction_ban_copy(repo, user, action, tooltip)
  end

  # Public: The description of an interaction limit.
  #
  # ability - The RepositoryInteractionAbility for the object that the limit will affect.
  # limit - The Symbol interaction limit you want the description of;
  #         one of RepositoryInteractionAbility::INTERACTION_LIMITS.
  #
  # Returns a String.
  def interaction_limit_description(ability:, limit:)
    return unless ability.present? && limit.present?

    description = []

    case limit
    when :sockpuppet_disallowed
      phrase = if ability.organization?
        "this organization's repositories"
      elsif ability.user?
        "your repositories"
      else
        "the repository"
      end

      description << "Users that have recently created their account will be unable to interact with #{phrase}."
    when :contributors_only
      description << "Users that have not previously "

      if ability.repository?
        description << link_to("committed", contributors_graph_path(ability.object.owner.display_login, ability.object.name))
      else
        description << "committed"
      end

      description << " to the "

      if ability.repository?
        description << "#{ability.object.default_branch} branch"
      else
        description << "default branch"
      end

      if ability.organization?
        description << " of a repository in this organization will be unable to interact with that repository."
      elsif ability.user?
        description << " of one of your repositories will be unable to interact with that repository."
      else
        description << " of this repository will be unable to interact with the repository."
      end
    when :collaborators_only
      description << "Users that are not "

      if ability.repository?
        description << link_to("collaborators", repository_access_management_path(ability.object.owner.display_login, ability.object.name))
      else
        description << "collaborators"
      end

      if ability.organization?
        description << " of a repository in this organization will not be able to interact with that repository."
      elsif ability.user?
        description << " of one of your repositories will not be able to interact with that repository."
      else
        description << " will not be able to interact with the repository."
      end
    end

    safe_join(description)
  end
end
