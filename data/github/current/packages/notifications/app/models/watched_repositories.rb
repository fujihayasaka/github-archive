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
  # include_fine_grained_pat_restrictions - Boolean that adds exclusions for repositories
  #                                        in organizations that restrict fine-grained PATs.
  #
  # Returns a WillPaginate::Collection of Repository instances.
  def user_via_granular_actor_paginate(current_user, options = {}, include_fine_grained_pat_restrictions: false)
    violating_ids = granular_actor_violating_ids(
      current_user,
      include_fine_grained_pat_restrictions:,
    )

    exclusion_type = include_fine_grained_pat_restrictions ? :granular_actor_fine_grained_pat : :granular_actor

    query(
      page:           options[:page],
      per_page:       options[:per_page],
      excluding:      violating_ids,
      exclusion_type: exclusion_type,
    )
  end

  # Public: Paginate public watched repositories with restrictions
  # for a granular actor acting on behalf of current_user.
  def public_user_via_granular_actor_paginate(current_user, options = {}, include_fine_grained_pat_restrictions: false)
    violating_ids = granular_actor_violating_ids(
      current_user,
      include_fine_grained_pat_restrictions:,
    )

    exclusion_type = include_fine_grained_pat_restrictions ? :public_granular_actor_fine_grained_pat : :public_granular_actor

    query(
      page:           options[:page],
      per_page:       options[:per_page],
      excluding:      (public_only_violating_ids + violating_ids).uniq,
      exclusion_type: exclusion_type,
    )
  end

  # Public: Paginate all watched repositories with classic personal
  # access token restrictions.
  #
  # options - The Hash of options.
  #           :page - The Integer page of repositories to get (default: 1).
  #           :per_page - The Integer of how many repositories to get per page (default: 30).
  #
  # Returns a WillPaginate::Collection of Repository instances.

  def classic_pat_paginate(options = {})
    violating_ids = classic_pat_violating_ids

    query(
      page:           options[:page],
      per_page:       options[:per_page],
      excluding:      violating_ids,
      exclusion_type: :classic_pat,
    )
  end

  # Public: Paginate public watched repositories with classic PAT restrictions.
  def public_classic_pat_paginate(options = {})
    query(
      page:           options[:page],
      per_page:       options[:per_page],
      excluding:      (public_only_violating_ids + classic_pat_violating_ids).uniq,
      exclusion_type: :public_classic_pat,
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
      exclusion_type: :oauth_app_policy,
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
    query({
      page: options[:page],
      per_page: options[:per_page],
      excluding: public_only_violating_ids,
      exclusion_type: :public_only,
    })
  end

  private

  def public_only_violating_ids
    GitHub.dogstats.distribution_time("newsies.pat_filter.duration", tags: ["filter_type:public_only"]) do
      # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
      repo_ids = @user.associated_repository_ids(include_oauth_restriction: false)
      # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      Repository.batched_scope(:id, values: repo_ids) { |s| s.private_scope }.pluck(:id)
    end
  end

  def classic_pat_violating_ids
    GitHub.dogstats.distribution_time("newsies.pat_filter.duration", tags: ["filter_type:classic_pat"]) do
      subscribed_repo_ids = Notifications::Subscriptions.repository_subscription_ids(
        @user.id
      )
      return [] if subscribed_repo_ids.nil?

      org_ids = Repository.where(id: subscribed_repo_ids).distinct.pluck(:owner_id)

      orgs = Organization.where(id: org_ids)
      Configurable.preload_configuration(orgs) if orgs.any?
      restricted_org_ids = orgs.select(&:legacy_personal_access_tokens_restricted?).map(&:id)
      return [] if restricted_org_ids.empty?

      Repository.where(id: subscribed_repo_ids, owner_id: restricted_org_ids).pluck(:id)
    end
  end

  def granular_actor_violating_ids(current_user, include_fine_grained_pat_restrictions:)
    GitHub.dogstats.distribution_time("newsies.pat_filter.duration", tags: ["filter_type:fine_grained_pat"]) do
      subscribed_repo_ids = Notifications::Subscriptions.repository_subscription_ids(
        @user.id
      )
      return [] if subscribed_repo_ids.nil?

      private_repo_ids = Repository.private_scope.where(id: subscribed_repo_ids).pluck(:id)

      repo_ids = ProgrammaticActor::RepositoryFilter.perform(
        actor: current_user, repository_ids: private_repo_ids
      )

      violating_ids = private_repo_ids - repo_ids
      return violating_ids unless include_fine_grained_pat_restrictions

      org_ids = Repository.where(id: subscribed_repo_ids).distinct.pluck(:owner_id)
      orgs = Organization.where(id: org_ids)
      Configurable.preload_configuration(orgs) if orgs.any?
      restricted_org_ids = orgs.select(&:personal_access_tokens_restricted?).map(&:id)

      fine_grained_pat_violating_ids = Repository.where(id: subscribed_repo_ids, owner_id: restricted_org_ids).pluck(:id)

      (violating_ids + fine_grained_pat_violating_ids).uniq
    end
  end

  def query(options = {})
    page = options[:page] || 1
    per_page = options[:per_page] || 30
    excluding = options.fetch(:excluding) { [] }
    exclusion_type = options.fetch(:exclusion_type) { :none }

    GitHub.dogstats.distribution(
      "newsies.list_subscriptions.exclusion_count",
      excluding.length,
      tags: ["exclusion_type:#{exclusion_type}"]
    )

    Newsies::Responses::WillPaginateCollection.new do
      count_response = Notifications::Subscriptions.count_repository_subscriptions(@user.id, excluding:)

      subscribed_response = Notifications::Subscriptions.subscribed_repositories(
        @user,
        sort: "created_at:asc",
        page: page,
        per_page: per_page,
        excluding: excluding,
      )

      subscription_count = if count_response.nil?
        raise Resiliency::Response::UnavailableError, "Failed to count subscriptions"
      else
        count_response
      end

      GitHub.dogstats.distribution(
        "newsies.list_subscriptions.user_subscription_count",
        subscription_count,
        tags: ["exclusion_type:#{exclusion_type}"]
      )

      raise Resiliency::Response::UnavailableError, "Failed to fetch subscribed repositories" if subscribed_response.nil?

      # newsies sorts subscriptions once retrieved from the database by name
      # with owner, but we want them by id
      repositories = subscribed_response.sort_by(&:id)
      WillPaginate::Collection.new(page, per_page, subscription_count).tap do |collection|
        collection.replace(repositories)
      end
    end
  end
end
