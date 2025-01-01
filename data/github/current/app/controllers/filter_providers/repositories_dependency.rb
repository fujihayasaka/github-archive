# typed: true
# frozen_string_literal: true

module FilterProviders::RepositoriesDependency
  extend T::Helpers
  extend T::Sig
  include GitHub::Memoizer
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
  end

  REPO_QUERY_SYMBOL = :repo
  REPO_QUERY_LIMIT = 10
  TOP_REPOSITORIES_SIZE = 2

  private

  sig { returns(T::Array[Repository]) }
  memoize def repositories_from_query
    return [] unless has_repository_context?

    repo_nwos = params[REPO_QUERY_SYMBOL]
      .split(",")
      .map { |repo_nwo| repo_nwo.include?("/") ? repo_nwo.strip.downcase : nil }
      .compact
      .uniq

    return [] if repo_nwos.empty?

    repos = Repository.with_names_with_owners(repo_nwos).limit(REPO_QUERY_LIMIT).to_a.compact

    repo_promises = repos.map do |repo|
      repo.async_readable_by?(current_user).then { |is_readable| repo.public? || is_readable ? repo : nil }
    end

    valid_repos = Promise.all(repo_promises).sync.compact
    cap_filter.authorized_resources(valid_repos)
  end

  def has_repository_context?
    params[REPO_QUERY_SYMBOL].present?
  end

  memoize def repositories_for_context
    has_repository_context? ? repositories_from_query : find_top_repositories
  end

  memoize def repository_ids_for_context
    has_repository_context? ? repository_ids_from_query : top_repo_ids
  end

  memoize def repository_ids_from_query
    repositories_from_query.pluck(:id)
  end

  memoize def top_repo_ids
    find_top_repositories.pluck(:id)
  end

  def respond_payload(json)
    respond_to do |format|
      format.json do
        render json: json
      end
    end
  end

  def find_top_repositories(page: 1, per_page: TOP_REPOSITORIES_SIZE, initial_per_page: TOP_REPOSITORIES_SIZE)
    TopRepositories
      .for(viewer: current_user, since: 1.year.ago, cap_filter: cap_filter)
      .simple_paginate(page: page, per_page: per_page, initial_per_page: initial_per_page)
  end
end
