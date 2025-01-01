# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class SearchResultItem < Platform::Unions::Base
      description "The results of a search."
      possible_types(
        Objects::Issue,
        Objects::PullRequest,
        Objects::Repository,
        Objects::User,
        Objects::Organization,
        Objects::MarketplaceListing,
        Objects::RepositoryAction,
        Objects::RepositoryStack,
        Objects::App,
        Objects::Discussion,
      )
    end
  end
end
