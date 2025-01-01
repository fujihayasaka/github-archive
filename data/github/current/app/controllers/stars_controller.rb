# typed: false
# frozen_string_literal: true

class StarsController < ApplicationController

  before_action :login_required, only: :index
  before_action :ensure_user_exists, only: [:user_stars, :user_repositories, :user_topics]
  before_action :ensure_profile_visible

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:user_stars]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:user_repositories]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:user_topics]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :user_stars, :user_topics, :user_repositories], optional: true

  SORT_MAPPING = {
    "updated" => {
      "Repository" => "pushed_at",
      "Topic" => "updated_at",
    },
    "stars" => {
      "Repository" => Repository.stargazer_count_column,
      "Topic" => "stargazer_count",
    },
  }

  SORT_OPTIONS = {
    "Recently starred"       => %w[created desc],
    "Recently active"        => %w[updated desc],
    "Most stars"             => %w[stars desc],
  }

  STARS_QUERY_LIMIT = 10000

  OVERVIEW_STARS_LIMIT = 10

  def index
    user_stars
  end

  def user_stars # rubocop:todo GitHub/UseRestfulActions
    @page = "overview"

    process_user_stars_view

    render "stars/index", locals: {
      starred_by_viewer: starred_by_viewer(@star_user, @starred_repositories + @starred_topics),
    }
  end

  def user_repositories # rubocop:todo GitHub/UseRestfulActions
    @page = "repositories"

    process_user_stars_view

    render "stars/repositories", locals: {
      starred_by_viewer: starred_by_viewer(@star_user, @starred_repositories),
    }
  end

  def user_topics # rubocop:todo GitHub/UseRestfulActions
    @page = "topics"

    process_user_stars_view

    render "stars/topics", locals: {
      starred_by_viewer: starred_by_viewer(@star_user, @starred_topics),
    }
  end

  private

  def ensure_user_exists
    render_404 unless User.find_by_login(params[:user])
  end

  def process_user_stars_view
    params[:direction] ||= "desc"
    params[:sort]      ||= "created"

    @star_user = this_user
    if logged_in?
      subset = following_subset
    end

    @hidden_repo_stars = false

    repository_summary = starred_repository_summary(@star_user)

    @total_yours = 0
    @total_others = 0
    @total_topics = 0

    if logged_in?
      owned_repository_ids = []
      not_owned_repository_ids = []

      repository_summary.each_value do |r|
        if r["owner_id"] == current_user.id
          owned_repository_ids << r["id"]
        else
          not_owned_repository_ids << r["id"]
        end
      end

      @total_yours = owned_repository_ids.size
      @total_others = not_owned_repository_ids.size
      @total_topics = user_starred_topics.size

      repository_ids = case params[:filter]
      when "yours"
        owned_repository_ids
      when "others"
        not_owned_repository_ids
      when "topics"
        []
      else
        repository_summary.keys
      end

      @following ||= subset
    else
      repository_ids = repository_summary.keys
    end

    if language_id = LanguageName.where(name: params[:language]).pick(:id)
      matching_repository_ids = []

      repository_summary.each_value do |r|
        matching_repository_ids << r["id"] if r["primary_language_name_id"] == language_id
      end

      repository_ids &= matching_repository_ids
    end

    # Breakdown of starred repos by language. If the user has over STARS_QUERY_LIMIT
    # (these are always bots), we don't even bother with this expensive query
    # (for the query or in the UI) and just return an empty array.
    if @hidden_repo_stars
      @language_counts = []
    else
      @language_counts = user_languages
    end

    if @page == "overview"
      repo_stars = @star_user.stars.repositories.where("stars.starrable_id": repository_ids)
      topic_stars = topics_collection_for_specific_filters_or_languages

      if params[:q].blank?
        # Order results according to the sort and direction params given.
        starred_repositories = ordered_stars_results(repo_stars, OVERVIEW_STARS_LIMIT, repository_summary)
        starred_topics = ordered_stars_results(topic_stars, OVERVIEW_STARS_LIMIT)

        # Preload starrable associations that are used in the view.
        preload_starrable_associations(starred_repositories)
        preload_starrable_associations(starred_topics)
      else
        repo_results = user_starred_repos_via_search(OVERVIEW_STARS_LIMIT)
        topic_results = user_starred_topics_via_search(OVERVIEW_STARS_LIMIT)
        repo_ids = repo_results.map(&:id)
        topic_ids = topic_results.map(&:id)

        # Map Repos to Stars, as expected by rendering. The `repo_ids` set is at most
        # 10 (<100), so the `IN` clause shouldn't really hurt.
        found_repo_stars = repo_stars.where("stars.starrable_id": repo_ids).includes(starrable: [:owner, :mirror])
        found_topic_stars = topic_stars.where("stars.starrable_id": topic_ids)

        starred_repositories = sorted_results(found_repo_stars)
        starred_topics = sorted_results(found_topic_stars)
      end

      @starred_repositories = starred_repositories
      @starred_topics = starred_topics
    elsif @page == "repositories"
      repo_stars = @star_user.stars.repositories.where("stars.starrable_id": repository_ids)
      @starred_repositories = paginated_stars(repo_stars, "Repository", repository_summary)
    else
      topic_stars = topics_collection_for_specific_filters_or_languages
      @starred_topics = paginated_stars(topic_stars, "Topic", nil)
    end

    @sort_options = SORT_OPTIONS
    @search_params = params.slice(:filter, :language, :sort, :direction)
  end

  def ordered_stars_results(stars, limit, repository_summary = nil)
    sort = params[:sort]
    direction = params[:direction]
    sort_by_attributes = SORT_MAPPING[sort]

    results = if sort.blank? || sort == "created" || sort_by_attributes.nil?
      direction == "desc" ? stars.order(created_at: :desc, id: :desc).limit(limit) : stars.order(:created_at, :id).limit(limit)
    else
      sorted_stars_results = stars.sort_by do |entity|
        if repository_summary
          sort_attribute = sort_by_attributes[entity.starrable_type]

          # `pushed_at` can be `nil`, so we fallback to `created_at` for sorting
          if sort_attribute == "pushed_at" && !repository_summary[entity.starrable_id]["pushed_at"]
            sort_attribute = "created_at"
          end

          [repository_summary[entity.starrable_id][sort_attribute], entity.id]
        else
          [entity.starrable[sort_by_attributes[entity.starrable_type]], entity.id]
        end
      end

      if direction == "desc"
        sorted_stars_results.reverse!
      end

      limit ? sorted_stars_results.first(limit) : sorted_stars_results
    end

    results
  end

  def sorted_results(stars)
    sort = params[:sort]
    sort_by_attributes = SORT_MAPPING[sort]

    results = if sort.blank? || sort == "created" || sort_by_attributes.nil?
      stars.sort_by do |entity|
        [entity.created_at, entity.id]
      end
    else
      stars.sort_by do |entity|
        if entity.starrable_type == "Repository" && sort == "updated" && !entity.starrable["pushed_at"]
          [entity.starrable["created_at"], entity.id]
        else
          [entity.starrable[sort_by_attributes[entity.starrable_type]], entity.id]
        end
      end
    end

    if params[:direction] == "desc"
      results.reverse
    else
      results
    end
  end

  # Sanitize `params[:direction]` into `asc` or `desc`
  #
  # Returns String that's either "asc" or "desc"
  def sort_direction
    down_dir = (params[:direction] || "desc").downcase.strip
    return down_dir if %w[asc desc].include?(down_dir)
    "desc"
  end

  # Search for stars using ES instead of MySQL `LIKE` across a BLOB
  # Should only be called when there is a string query.
  def user_starred_repos_via_search(per_page)
    type = "Repositories"
    phrase = params[:q] || ""

    queries ||= Search::QueryHelper.new(phrase, type,
      current_user: current_user,
      remote_ip: request.remote_ip,
      star_user: this_user,
      facets: true,
      highlight: true,
      language: params[:language],
      sort: sort_direction,
      page: current_page,
      per_page: per_page,
      star_search: true,
      include_forks: true,
    )
    query = queries[type]

    begin
      query.execute
    rescue ElastomerClient::Client::Error => boom
      # TODO(sshirokov): Is this worth raising test/fast/linting/rescue_test.rb{EXPECTED_BAD_RESCUE_LINES}
      #                  to rescue a StandardError here?
      Failbot.report boom, app: "github-non-user-facing"
      Search::Results.empty
    end
  end

  # Search for stars using ES instead of MySQL `LIKE` across a BLOB
  # Should only be called when there is a string query.
  def user_starred_topics_via_search(per_page)
    type = "Topics"
    phrase = params[:q] || ""

    queries ||= Search::QueryHelper.new(phrase, type,
      current_user: current_user,
      remote_ip: request.remote_ip,
      page: current_page,
      per_page: per_page
    )
    query = queries[type]

    begin
      query.execute
    rescue ElastomerClient::Client::Error => boom
      Failbot.report boom, app: "github-non-user-facing"
      Search::Results.empty
    end
  end

  # Finds the stars in the set that the current user has also starred.
  #
  # This is used to determine whether to show the current user a Star or
  # Unstar button when viewing a list of another user's starred repositories.
  #
  # owner - The User whose stars we are viewing.
  # stars - An Array of Star objects to find in common with the current user.
  #
  # Returns a Set of repository IDs.
  def starred_by_viewer(owner, stars)
    return [] unless logged_in?

    repository_stars = stars.select do |star|
      star.starrable.is_a?(Repository)
    end

    repository_ids = if current_user.feature_enabled?(:limit_user_repo_stars_query)
      repository_stars.map(&:starrable_id).take(5000)
    else
      repository_stars.map(&:starrable_id)
    end

    # Current user is viewing their own stars.
    return repository_ids if owner == current_user

    if GitHub.flipper[:stars_domain_stars].enabled?(current_user)
      current_user.starred_repository_ids(repo_ids: repository_ids).to_set
    else
      current_user.stars.repositories.where("stars.starrable_id": repository_ids).pluck(:starrable_id).to_set
    end
  end

  def following_subset
    ids = GitHub.cache.fetch("stars:following_id_subset:#{current_user.id}", ttl: 5.minutes) do
      current_user.
         following.
           not_spammy.pluck(:id).sample(14)
    end

    User.where(id: ids).shuffle
  end

  def this_user # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @this_user if defined?(@this_user)
    @this_user = User.find_by_login(params[:user]) || current_user
  end

  # The cached version of starred languages.
  def user_languages
    user = this_user
    key = "#{user.login}#{':public' unless user == current_user }" # rubocop:disable GitHub/DoNotAllowLogin login is ok as a cache key
    GitHub.cache.fetch("user:repositories:starred_count:#{key}", ttl: 5.minutes) do
      user_languages!
    end
  end

  # The counts of the languages in a user's starred repos.
  #
  # Returns a hash of form {:language_name => count}.
  def user_languages!
    user = this_user
    if user == current_user
      user.starred_repositories_by_language
    else
      user.starred_public_repositories_by_language
    end
  end

  def topics_collection_for_specific_filters_or_languages
    filters_for_repos_only = %w(yours others)

    if params[:filter].in?(filters_for_repos_only) || params[:language].present?
      Topic.none
    else
      user_starred_topics
    end
  end

  def user_starred_topics # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @user_starred_topics ||= @star_user.stars.topics
  end

  def max_pagination_page
    30
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_user
  end

  # Returns a hash with key of repository#id and repository attributes that can
  # be used to filter or sort without needing to do an additional repo query.
  #
  # { 4 => { "owner_id" => 4, "pushed_at" => "2019-06-14 13:42:03 -0400 "}, ... }
  def starred_repository_summary(user)
    starred_repo_ids = if GitHub.flipper[:stars_domain_stars].enabled?(current_user)
      user.most_recently_starred_repo_ids(STARS_QUERY_LIMIT + 1)
    else
      user.stars.repositories.order(created_at: :desc).limit(STARS_QUERY_LIMIT + 1).pluck(:starrable_id)
    end

    if starred_repo_ids.count > STARS_QUERY_LIMIT
      @hidden_repo_stars = true
    end

    repositories = if user == current_user
      accessible_starred_repo_ids = user.associated_repository_ids(repository_ids: starred_repo_ids)

      if accessible_starred_repo_ids.any?
        Repository.active.public_scope.where(id: starred_repo_ids - accessible_starred_repo_ids).or(Repository.active.where(id: accessible_starred_repo_ids))
      else
        Repository.active.public_scope.where(id: starred_repo_ids)
      end
    else
      Repository.active.public_scope.where(id: starred_repo_ids)
    end

    rows = repositories.pluck(:id, :owner_id, :created_at, :primary_language_name_id, :pushed_at, Repository.stargazer_count_column)
    GitHub.dogstats.distribution("starred_repository_summary_size", rows.size)

    rows.each_with_object({}) do |(id, owner_id, created_at, primary_language_name_id, pushed_at, stargazer_count), results|
      results[id] = {
        "id" => id,
        "owner_id" => owner_id,
        "created_at" => created_at,
        "primary_language_name_id" => primary_language_name_id,
        "pushed_at" => pushed_at,
        Repository.stargazer_count_column => stargazer_count,
      }
    end
  end

  # Preload starrable associations
  def preload_starrable_associations(stars)
    repo_stars = stars.select { |star| star.starrable_type == "Repository" }
    GitHub::PrefillAssociations.prefill_associations(repo_stars, :starrable)

    repos = repo_stars.map(&:starrable)
    GitHub::PrefillAssociations.prefill_associations(repos, [:owner, :mirror])
    GitHub::PrefillAssociations.prefill_batch_method(repos, :sponsorable_owner?)
    GitHub::PrefillAssociations.prefill_batch_method(repos, :owner_sponsored_by_viewer?, current_user)
  end

  def paginated_stars(stars, starrable_type, repository_summary)
    WillPaginate::Collection.create(current_page, Star.per_page) do |pager|
      if params[:q].blank?
        # Order results according to the sort and direction params given.
        stars = ordered_stars_results(stars, nil, repository_summary)
        stars_for_page = stars.drop(pager.offset).take(pager.per_page)

        # Preload starrable associations that are used in the view.
        preload_starrable_associations(stars)

        pager.replace(stars_for_page)
        pager.total_entries = stars.size unless pager.total_entries
      else
        results = if starrable_type == "Repository"
          user_starred_repos_via_search(Star.per_page)
        else
          user_starred_topics_via_search(Star.per_page)
        end
        star_ids = results.map(&:id)

        # Map Repos to Stars, as expected by rendering. The `repo_ids` set is at most
        # Star.per_page (<100), so the `IN` clause shouldn't really hurt.
        found_stars = if starrable_type == "Repository"
          stars.where("stars.starrable_id": star_ids).includes(starrable: [:owner, :mirror])
        else
          stars.where("stars.starrable_id": star_ids)
        end

        stars = sorted_results(found_stars)

        pager.replace(found_stars)
        pager.total_entries = found_stars.size
      end
    end
  end

  def ensure_profile_visible
    return render_404 if this_user.private_profile_for?(current_user)
  end
end
