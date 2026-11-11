# typed: true
# frozen_string_literal: true

class WatchedRepositories

  attr_reader :user

  # Public: Returns a new WatchedRepositories instance.
  #
  # user - The User instance to find watched repositories for.
  def initialize(user)
    @user = user
  end

  # Public: Paginate all watched repositories.
  #
  # options - The Hash of options.
  #           :page - The Integer page of repositories to get (default: 1).
  #           :per_page - The Integer of how many repositories to get per page (default: 30).
  #
  # Returns a WillPaginate::Collection of Repository instances.
  def paginate(options = {})
    query({
      page: options[:page],
      per_page: options[:per_page],
    })
  end

  # Public: Paginate all watched repositories with that are accessible
  # to the @user and the granular actor acting on it's behalf
  # (GitHub App, v2 PAT, etc).
  #
  # current_user - The User whose repositories we are trying to access.
  # options - The Hash of options.
  #           :page - The Integer page of repositories to get (default: 1).
  #           :per_page - The Integer of how many repositories to get per page (default: 30).
  #
  # Returns a WillPaginate::Collection of Repository instances.
  def user_via_granular_actor_paginate(current_user, options = {})
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    private_repository_scope = Repository.private_scope.where(id: @user.associated_repository_ids)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded

    repo_ids = ProgrammaticActor::RepositoryFilter.perform(
      actor: current_user, repository_ids: private_repository_scope.pluck(:id)
    )

    violating_ids = private_repository_scope.where.not(id: repo_ids).pluck(:id)

    query(
      page:      options[:page],
      per_page:  options[:per_page],
      excluding: violating_ids,
    )
  end

  # Public: Paginate all watched repositories with oauth application governance.
  #
  # oauth_application - The OauthApplication by which results should be filtered.
  # options - The Hash of options.
  #           :page - The Integer page of repositories to get (default: 1).
  #           :per_page - The Integer of how many repositories to get per page (default: 30).
  #
  # Returns a WillPaginate::Collection of Repository instances.
  def oap_paginate(oauth_application, options = {})
    oap_violating_ids = Repository.oauth_app_policy_violated_repository_ids(
      # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
      repository_ids: @user.associated_repository_ids(include_oauth_restriction: false),
      # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      repository_scope: Repository.private_scope,
      app: oauth_application,
    )

    query({
      page: options[:page],
      per_page: options[:per_page],
      excluding: oap_violating_ids,
    })
  end

  # Public: Paginate all public watched repositories.
  #
  # options - The Hash of options.
  #           :page - The Integer page of repositories to get (default: 1).
  #           :per_page - The Integer of how many repositories to get per page (default: 30).
  #
  # Returns a WillPaginate::Collection of Repository instances.
  def public_paginate(options = {})
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    repo_ids = @user.associated_repository_ids(include_oauth_restriction: false)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
    private_ids = Repository.batched_scope(:id, values: repo_ids) { |s| s.private_scope }.pluck(:id)

    query({
      page: options[:page],
      per_page: options[:per_page],
      excluding: private_ids,
    })
  end

  private

  def query(options = {})
    page = options[:page] || 1
    per_page = options[:per_page] || 30
    excluding = options.fetch(:excluding) { [] }

    Newsies::Responses::WillPaginateCollection.new do
      count_response = GitHub.newsies.count_subscriptions(@user, \
        set: :subscribed,
        excluding: excluding,
        list_type: ::Repository.name,
      )

      subscribed_response = GitHub.newsies.subscribed_repositories(@user, \
        sort: "created_at:asc",
        set: :subscribed,
        page: page,
        per_page: per_page,
        excluding: excluding,
      )

      subscription_count = count_response.value!
      # newsies sorts subscriptions once retrieved from the database by name
      # with owner, but we want them by id
      repositories = subscribed_response.value!.sort_by(&:id)
      WillPaginate::Collection.new(page, per_page, subscription_count).tap do |collection|
        collection.replace(repositories)
      end
    end
  end
end
