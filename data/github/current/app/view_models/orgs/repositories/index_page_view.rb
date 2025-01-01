# typed: true
# frozen_string_literal: true

class Orgs::Repositories::IndexPageView < Orgs::OverviewView
  include Users::RepositoryFilteringMethods
  include ProfilesHelper
  include Issues::Domain::Provider

  SIDEBAR_MEMBERS_LIMIT = 20
  TOPIC_NAMES_PER_REPO = 7

  attr_reader :organization, :current_page, :phrase, :rate_limited, :type_filter, :language, :sort_order, :context

  def after_initialize
    @type_filter = default_type_filter unless @type_filter.present?
  end

  # Internal: Returns the count of this org's pinned repositories.
  def total_pins
    organization.pinned_repositories.public_scope.count
  end

  # Public: Returns true if the org has selected any repositories to show on
  # their profile.
  def has_pinned_repositories?
    return @has_pinned_repositories if defined? @has_pinned_repositories
    @has_pinned_repositories = total_pins > 0
  end

  def user
    organization
  end

  def show_standalone_customize_pinned_repositories?
    can_change_pinned_repositories? && !has_pinned_repositories?
  end

  def render_org_overview?
    context == "overview"
  end

  def top_language_path(language_name)
    language_param = CGI.escape(language_name.downcase)
    path = urls.org_repositories_path(organization) + "?language=#{language_param}"
    path += "&type=#{type_filter}" if type_filter.present?
    if phrase.present?
      query_param = CGI.escape(phrase)
      path += "&q=#{query_param}"
    end
    path
  end

  def sidebar_member_url(member)
    if show_admin_stuff?
      urls.org_person_path(organization, member)
    else
      urls.user_path(member)
    end
  end

  def type_filters
    valid_type_filters(viewer: current_user, user: organization, include_private: show_new_repository_button?)
  end

  def selected_sort_order(sort_order:)
    Users::RepositoryFilteringMethods::REPOSITORY_SORT_ORDERS[sort_order] || "Last updated"
  end

  def sort_order_description(sort_order:)
    selected_sort_order(sort_order: sort_order).downcase
  end

  # By default we only want to show the repositories that the org is a direct owner of, which
  # include sources and its forks. If the user actually enters a search query, then we show all
  # results (including forks of org repos by members)
  def repositories
    repository_includes = [
      :community_profile,
      :internal_repository,
      :mirror,
      :packages,
      :parent,
      :repository_license,
    ]
    repository_preloads = [:owner, :primary_language, :topics]
    @repositories ||= if phrase.present? || language.present?
      search_repos_as(
        current_user,
        page: current_page,
        type: type_filter,
        types: type_filters,
        language: language,
        sort_order: sort_order,
        repositories_scope: Repository.includes(repository_includes).preload(repository_preloads),
      )
    else
      results = filter_repos_by_type(repositories_scope, type: type_filter, types: type_filters).
        where(owner_id: organization).
        includes(repository_includes)

      results = case sort_order
      when "name"
        results.sorted_by_name
      when "stargazers"
        results.most_starred
      else
        results.recently_updated
      end
      results = results.preload(repository_preloads)
      results.paginate(page: current_page, per_page: Repository.per_page).to_a
    end
  end

  def selected_language
    helpers.get_selected_language(language)
  end

  # Public: Should we show the Top languages for all of this organization's
  # repositories?
  #
  # Returns a Boolean.
  def show_top_languages?
    top_language_names.any?
  end

  # Public: Should we cache Top languages? We only want to do this if the
  # fragment doesn't contain any user-provided input, such as a search phrase.
  #
  # Returns a Boolean.
  def cache_top_languages?
    phrase.blank?
  end

  # Public: Returns the most used languages for all of this organization's
  # repositories, private and public, sorted by weight.
  def top_language_names
    return @top_language_names if defined? @top_language_names
    @top_language_names = organization.
        repo_id_language_breakdown(repo_ids_for_current_user, 5).
        sort_by { |_lang, weight| -weight }.map { |(lang, _weight)| lang }
  end

  def top_languages_cache_key
    org_profile_cache_key(
      feature: "top_languages",
      organization: organization,
      direct_or_team_member: direct_or_team_member?,
      org_profile_overview: render_org_overview?
    )
  end

  def can_create_discussion_post?
    organization.adminable_by?(current_user)
  end

  def latest_discussion_post
    return @latest_discussion_post if defined?(@latest_discussion_post)
    @latest_discussion_post = organization.discussion_posts.visible_to(current_user).most_recent.first
  end

  def most_used_topics_cache_key
    org_profile_cache_key(
      feature: "most_used_topics",
      organization: organization,
      direct_or_team_member: direct_or_team_member?,
      org_profile_overview: render_org_overview?
    )
  end

  # Public: Should we show the most used topics for all of this organization's
  # repositories?
  #
  # Returns a Boolean.
  def show_most_used_topics?
    most_used_topics.size > 1
  end

  # Capping the number of repos+topics we aggregate to 25k, most_used_topics takes about 2s to run. This means that
  # for orgs with >25k repos, their most used topics will not be entirely accurate since we're only sampling 25k
  # of their repos. If we need 100% accuracy then this logic needs to move to a background job that runs periodically
  # and stores the result
  MAX_REPO_TOPICS_PER_ORG = 25_000
  MOST_USED_TOPICS_BATCH_SIZE = 1_000

  # Public: Returns a list of the topic names that have been most applied to this
  # organization's repositories. Only considers repositories accessible to the
  # current user.
  def most_used_topics
    return @most_used_topics if @most_used_topics

    if direct_or_team_member?
      org_repos_with_topics = org_owned_repos_scope.joins(:repository_topics)
                                                   .merge(RepositoryTopic.applied)
                                                   .limit(MAX_REPO_TOPICS_PER_ORG)
                                                   .pluck("repositories.id, repository_topics.topic_id")
                                                   .select { |repository_id, _topic_id| repo_ids_for_current_user.include?(repository_id) }
      return @most_used_topics = [] if org_repos_with_topics.count < 3
      @most_used_topics = most_used_topics_in_batches(org_repos_with_topics)
    else
      repos_with_topics = repos_for_current_user.joins(:repository_topics).merge(RepositoryTopic.applied)
      return @most_used_topics = [] if repos_with_topics.count < 3
      @most_used_topics = Topic.popular_names_for_repositories(repositories: repos_with_topics, limit: 5)
    end
  end

  def most_used_topics_in_batches(org_repos_with_topics, limit: 5)
    most_used_topics = {}
    topic_names_cache = {}

    org_repos_with_topics.each_slice(MOST_USED_TOPICS_BATCH_SIZE) do |slice|
      org_repo_ids = []
      org_topic_ids = []
      slice.each { |repository_id, topic_id| org_repo_ids << repository_id; org_topic_ids << topic_id }
      repos_with_topics = Repository.joins(:repository_topics)
                                    .where("repositories.id IN (?) AND repository_topics.topic_id IN (?)", org_repo_ids.uniq, org_topic_ids.uniq)

      topics_and_counts = Topic.popular_topics_with_counts_for_repositories(repositories: repos_with_topics, topic_names_cache:)
      topics_and_counts.each do |id, name, count|
        unless topic_names_cache.key?(id)
          topic_names_cache[id] = name
        end

        if most_used_topics.key?(id)
          most_used_topics[id] += count
        else
          most_used_topics[id] = count
        end
      end
    end

    most_used_topics = most_used_topics.map { |id, count| [topic_names_cache[id], count] }.sort_by { |name, count| [-count, name] }
    most_used_topics.take(limit).map { |name, _count| name }
  end

  def show_topic_management_link?
    direct_or_team_member?
  end

  def show_toolbar?
    # We can always search if there's public repos
    return true if any_public_repositories?
    # If no public repos and no user, we can't access anything
    return false unless current_user
    # Check if we can access any repos.
    !(show_no_repositories_for_admin? || show_no_repositories_for_member? || show_no_repositories_for_non_member?)
  end

  def show_visibility_filters?
    direct_or_team_member?
  end

  def filtering?
    return @filtering if defined? @filtering
    @filtering = filtering_repositories?(type: type_filter, phrase: phrase, language: language,
                                         types: type_filters)
  end

  def show_no_results?
    filtering? && no_repositories?
  end

  def show_no_repositories_for_member?
    no_repositories? && !filtering? && direct_or_team_member? &&
        !adminable_by_current_user?
  end

  def show_no_repositories_for_admin?
    no_repositories? && !filtering? && adminable_by_current_user?
  end

  def show_no_repositories_for_non_member?
    no_repositories? && !filtering? && !direct_or_team_member?
  end

  def show_page_too_high?
    no_repositories? && !filtering? && !first_page?
  end

  def clear_filter_params
    default_type_filter != "all" ? { type: "all" } : {}
  end

  def default_type_filter
    return "all" unless
      GitHub.flipper[:default_org_profiles_to_public_repos].enabled?(current_user) ||
      GitHub.flipper[:default_org_profiles_to_public_repos].enabled?(organization)

    if phrase.blank?
      "public"
    else
      "all"
    end
  end

  # Public: Returns true if this page has no repositories (due to pagination,
  # filtering, permissions, et al).
  def no_repositories?
    return @no_repositories if defined? @no_repositories
    @no_repositories = !repositories.any?
  end

  # Public: Returns true if the organization has at least one public repository.
  def any_public_repositories?
    public_repositories_count > 0
  end

  def sidebar_members
    return @sidebar_members if @sidebar_members

    # Grab public members first to see if we have at least enough for the preview.
    member_ids = organization.public_members.order(:id).limit(SIDEBAR_MEMBERS_LIMIT).pluck(:id)

    # If we don't have enough and allow private members, add those
    if member_ids.size < SIDEBAR_MEMBERS_LIMIT && !organization.limit_to_public_members?(current_user)
      member_ids.concat(organization.member_ids(limit: SIDEBAR_MEMBERS_LIMIT - member_ids.size))
    end

    @sidebar_members = User.where(id: member_ids)
  end

  def sidebar_teams
    return [] unless logged_in?

    organization.visible_teams_for(current_user).limit(3)
  end

  # Public: Returns a sorted list of language names that occur in the
  # repositories owned by the organization that the viewer can access.
  def language_names_for_search
    @languages_names ||= language_names_for(repos_for_current_user)
  end

  # Public: Whether we should be showing the language search dropdown
  def show_language_search?
    language_names_for_search.present?
  end

  # Public: Will more than just the search controls be shown in the header area
  # of the org profile?
  def more_than_search_in_toolbar?
    show_new_repository_button? || show_standalone_customize_pinned_repositories?
  end

  def show_new_repository_button?
    can_create_repository?
  end

  # Public: Returns true if the current user can add, remove, and reorder the
  # org's pinned repositories.
  def can_change_pinned_repositories?
    adminable_by_current_user?
  end

  # Public: Returns true if the user is viewing the first page of repositories.
  def first_page?
    current_page.nil? || current_page.to_s == "1"
  end

  # Public: Checks to see if the notification restrictions banner should be shown
  # to this user.
  #
  # Returns a Boolean
  def show_notification_restrictions_banner?
    organization.show_notification_restriction_banner?(current_user)
  end

  def org_at_seat_limit?
    organization.at_seat_limit?
  end

  def user_or_organization_restricted?
    organization.has_full_trade_restrictions? || (current_user&.has_any_trade_restrictions? && !organization.uncharged_account?)
  end

  def show_developer_program_member_badge?
    !GitHub.enterprise? && organization_developer_program_member?
  end

  def pull_request_count_for(repository_id)
    has_pull_request = true
    open_issue_and_pr_counts[[repository_id, has_pull_request]].to_i
  end

  def issue_count_for(repository_id)
    has_pull_request = false
    open_issue_and_pr_counts[[repository_id, has_pull_request]].to_i
  end

  def network_count_for(repository)
    count = public_fork_counts_for_public_roots[repository.id] ||
      full_network_counts[repository.source_id]

    count.to_i
  end

  def topic_names_for(repository_id)
    topic_names_by_repository_id[repository_id] || []
  end

  private

  def public_fork_counts_for_public_roots
    @_public_fork_counts_for_public_roots ||= Repository.public_fork_counts_for_public_roots_for(
      network_ids: repositories.pluck(:source_id),
    )
  end

  def full_network_counts
    @_full_network_counts ||= Repository.full_network_counts_for(
      source_ids: repositories.pluck(:source_id),
    )
  end

  def open_issue_and_pr_counts
    @_open_issue_and_pr_counts ||= begin
      if GitHub.flipper[:issue_dependency_removal].enabled?
        issues_domain.open_issue_and_pr_counts(repository_ids: repositories.pluck(:id))
      else
        Repository.open_issue_and_pr_counts(repository_ids: repositories.pluck(:id))
      end
    end
  end

  def topic_names_by_repository_id
    @_topic_names_by_repository_id ||= RepositoryTopic.names_for(
      repository_ids: repositories.pluck(:id),
      limit_per_repo: TOPIC_NAMES_PER_REPO,
    )
  end

  # Internal: The number of repositories in scope for this request. We cache
  # this value to save the cost of database roundtrips (even if the value is
  # cached in the DB).
  def repositories_count
    @repositories_count ||= repositories.count
  end

  # Internal: returns a repository scope that is suitable for the current user,
  # based on the user's membership within the organization and the number of
  # repositories associated with the user. Takes into consideration large
  # numbers of associated repos to prevent page slowness.
  #
  # Returns an ActiveRecord::Relation.
  def repos_for_current_user
    @repos_for_current_user ||=
      if direct_or_team_member?
        repositories_scope(org_owned_repo_ids: org_owned_repo_ids)
      else
        organization.public_repositories
      end
  end

  # Internal: returns a  list of repository ids that is suitable for the current user
  # based on the user's membership within the organization and the number of
  # repositories associated with the user. Takes into consideration large
  # numbers of associated repos to prevent page slowness.
  #
  # Returns an Array if Int
  def repo_ids_for_current_user
    @repo_ids_for_current_user ||=
      if direct_or_team_member?
        org_owned_repo_ids
      else
        organization.public_repositories.ids
      end
  end

  def org_owned_repos_scope
    Repository.owned_by(organization)
  end

  def org_owned_repo_ids
    @org_owned_repo_ids ||= org_owned_repos_scope.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
  end

  def live_search?
    !Organization::RepositoryFilter.too_many_repos?(repositories_count)
  end

  def can_create_repository?
    return @can_create_repository if defined? @can_create_repository
    @can_create_repository = organization.can_create_repository?(current_user)
  end
end
