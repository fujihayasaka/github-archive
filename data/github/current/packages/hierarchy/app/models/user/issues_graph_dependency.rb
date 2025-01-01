# typed: false
# frozen_string_literal: true

module User::IssuesGraphDependency
  extend ActiveSupport::Concern

  # Public: converts a user object into a hash representation that the issues
  # graph service uses to store the user on the graph.
  #
  # Returns a Hash
  def to_hierarchy_model
    {
      id: id,
      login: display_login,
      avatarUrl: primary_avatar_url
    }
  end
end
