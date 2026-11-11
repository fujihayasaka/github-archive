# typed: true
# frozen_string_literal: true

module Starlike
  extend ActiveSupport::Concern

  # Public: The User who is creating or deleting the star, for use in Hydro instrumentation.
  attr_accessor :actor

  # Public: A case-insensitive String describing the context in which the star is being created or deleted, for use in
  # Hydro instrumentation.
  #
  # Valid values for a gist star: "context_type_unknown", "repository", "discovery_feed", "repo_stargazers",
  # "user_stars", "trending", "api", "gist", "other"; see lib/hydro/schemas/github/v1/gist_star_pb.rb
  #
  # Valid values for a repository star: "context_type_unknown", "repository", "discovery_feed", "repo_stargazers",
  # "user_stars", "trending", "api", "gist", "other", "news_feed", "user_list", "collections";
  # see lib/hydro/schemas/github/v1/repository_star_pb.rb
  #
  # Valid values for a topic star: "context_type_unknown", "repository", "discovery_feed", "repo_stargazers",
  # "user_stars", "trending", "api", "gist", "other", "topic"; see lib/hydro/schemas/github/v1/topic_star_pb.rb
  attr_accessor :hydro_context_type

  # Public: Get Hydro event attributes to represent starring or unstarring an entity.
  #
  # entity - the Repository, Topic, or Gist for the star
  # actor - the User who took the action
  # context - String context for where the action took place on the site
  #
  # Returns a Hash.
  def hydro_attributes_for(entity:, actor:, context:)
    {
      actor: actor,
      star: self,
      entity: entity,
      stars_count: entity.stargazer_count,
      context: context || "other",
      owner: entity.try(:owner),
    }
  end
end
