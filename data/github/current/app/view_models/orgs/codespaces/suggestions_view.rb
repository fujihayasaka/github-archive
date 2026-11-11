# typed: true
# frozen_string_literal: true

class Orgs::Codespaces::SuggestionsView < AutocompleteView

  attr_reader :user_logins_with_access
  attr_reader :team_slugs_with_access

  def suggestions
    all_suggestions = super

    # Remove any suggested users who have been already added as selected users.
    all_suggestions.delete_if { |user| user_logins_with_access.include? user.try(:display_login) }
    all_suggestions.delete_if { |team| team_slugs_with_access.include? team.try(:slug) }
  end
end
