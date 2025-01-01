# typed: false
# frozen_string_literal: true

class TopicsController < ApplicationController
  TOPIC_REPOS_PER_PAGE = 20
  include GitHub::RateLimitedRequest

  before_action :add_csp_exceptions, only: [:show]
  before_action :redirect_to_normalized_topic_name, only: [:show]
  before_action :disable_on_proxima, only: [:index, :autocomplete]

  # :site bundle dependency should be transitioned to only :explore
  stylesheet_bundle :site
  stylesheet_bundle :explore, :dashboard, :discussions

  rate_limit_requests \
    only: [:show],
    if: :request_is_rate_limited?,
    key: :topics_rate_limit_key,
    max: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_MAX,
    ttl: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_TTL

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:autocomplete]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  CSP_EXCEPTIONS = {
    frame_src: ["www.youtube.com"],
    img_src: [
      ExploreFeed::Event::FEED_URL,
    ],
  }

  include RepositoryControllerMethods

  def index
    context_region_preset context_region

    featured_topics_sample = Topic.not_flagged.curated.with_logo.featured_and_shuffled
    popular_topics = Topic
      .not_flagged
      .popular_on_public_repositories(Topic::NUMBER_OF_POPULAR_TOPICS)
    topic_results = Topic
      .featured_and_sorted_alphabetically
      .paginate(per_page: Topic.per_page, page: params.fetch(:page, 1))

    if request.xhr?
      render partial: "topics/featured_topics", locals: {
        featured_topics_sample: featured_topics_sample,
        popular_topics: popular_topics,
        topic_results: topic_results
      }
    else
      render "topics/index", locals: {
        featured_topics_sample: featured_topics_sample,
        popular_topics: popular_topics,
        topic_results: topic_results
      }
    end
  end

  def show
    if proxima?
      return redirect_to search_path(q: "topic:#{params[:topic_name]}", type: "Repositories")
    end

    context_region_preset context_region

    topic_name = params[:topic_name]
    topic = Topic.find_or_build_by_name(topic_name)

    if topic.blank? || topic.flagged?
      render_404
    else
      events = ExploreFeed::Event.all.upcoming_or_current.for_topic(topic.or_alias_source.name)
      spotlights = ExploreFeed::Spotlight.all.current.for_topic(topic.or_alias_source.name)
      marketplace_listings = Marketplace::Listing.with_category(topic_name).verified_and_shuffled
      marketplace_category = Marketplace::Category.for_slug(topic_name).first
      repository_results = repository_query(repository_query_string).execute

      preload_repo_associations(repository_results.models)

      sort = params[:s].presence || "stars"
      direction = params[:o].presence || "desc"
      language = params[:l].presence

      respond_to do |format|
        format.html do
          if request.xhr?
            render partial: "topics/paginated_repositories", locals: {
              sort: sort,
              direction: direction,
              language: language,
              marketplace_listings: marketplace_listings,
              marketplace_category: marketplace_category,
              repository_results: repository_results,
              topic: topic,
              spotlights: spotlights,
              events: events,
              sponsorability_by_repo_id: get_sponsorability_by_repo_id(repository_results),
              sponsoring_status_by_repo_id: get_sponsoring_status_by_repo_id(repository_results)
            }
          else
            render "topics/show", locals: {
              sort: sort,
              direction: direction,
              language: language,
              marketplace_listings: marketplace_listings,
              marketplace_category: marketplace_category,
              repository_results: repository_results,
              all_repository_count_for_languages: all_repository_count_for_languages,
              topic: topic,
              spotlights: spotlights,
              events: events,
              sponsorability_by_repo_id: get_sponsorability_by_repo_id(repository_results),
              sponsoring_status_by_repo_id: get_sponsoring_status_by_repo_id(repository_results)
            }
          end
        end

        # We need to protect against the case where a user tries to use a period in a topic name, which is
        # interpreted as the requested format (e.g. `/topics/node.js` instead of `/topics/nodejs`).
        # See https://github.com/github/communities/issues/1135
        format.all do
          flash[:error] = "Invalid topic name: topics cannot contain periods."
          redirect_to topics_path
        end
      end
    end
  end

  def autocomplete # rubocop:todo GitHub/UseRestfulActions
    return head :not_acceptable unless logged_in?

    topic_names = RepositoryTopic.autocompleted_names(
      repository: current_repository,
      query: params[:q],
      viewer: current_user
    )

    respond_to do |format|
      format.html_fragment do
        render partial: "topics/autocomplete", formats: :html, locals: {
          topic_names: topic_names
        }
      end
    end
  end

  private

  def disable_on_proxima
    render_404 if proxima?
  end

  def context_region
    proxima? ? :topics : :explore
  end

  def proxima?
    GitHub.multi_tenant_enterprise?
  end

  def preload_repo_associations(repositories)
    Configurable.preload_configuration(repositories)
    GitHub::PrefillAssociations.prefill_associations(repositories, [:open_graph_image])

    if logged_in?
      GitHub::PrefillAssociations.prefill_batch_method(repositories, :starred_by?, current_user)
    end
  end

  def repository_query(query_phrase)
    Search::Queries::RepoQuery.new(
      current_user: current_user,
      user_session: user_session,
      remote_ip: request.remote_ip,
      aggregations: true,
      phrase: query_phrase,
      page: params.fetch(:page, 1),
      per_page: TOPIC_REPOS_PER_PAGE,
      include_topics: true,
    )
  end

  def all_repository_count_for_languages
    all_repositories_language_results = repository_query(base_repository_query_string).execute
    all_repositories_language_results.total
  end

  def base_repository_query_string
    "topic:#{params[:topic_name]} fork:true is:public"
  end

  def repository_query_string
    query_bits = [base_repository_query_string]
    valid_sort_param = params[:s].present? && params[:s].split.size == 1
    valid_order_param = %w(asc desc).include?(params[:o])
    if valid_sort_param && valid_order_param
      query_bits << "sort:#{params[:s]}-#{params[:o]}"
    elsif valid_sort_param
      query_bits << "sort:#{params[:s]}"
    end
    query_bits << "language:#{params[:l]}" if params[:l].present?
    query_bits << params[:q] if params[:q].present?
    query_bits.join(" ")
  end

  def parsed_issues_query
    [[:is, "open"], [:is, "issue"]]
  end
  helper_method :parsed_issues_query

  def redirect_to_normalized_topic_name
    if Topic.normalize(params[:topic_name]) != params[:topic_name]
      redirect_to("/topics/#{Topic.normalize(params[:topic_name])}", status: 301)
    end
  end

  # Private: Determine for each repository search result whether the repo's owner can be
  # sponsored on GitHub Sponsors.
  #
  # repository_results - a Search::Results
  #
  # Returns a Hash of Repository ID => Boolean.
  def get_sponsorability_by_repo_id(repository_results)
    return {} unless GitHub.sponsors_enabled?

    repo_owner_ids_by_repo_id = get_repo_owner_ids_by_repo_id(repository_results)
    repo_owner_ids = repo_owner_ids_by_repo_id.values.uniq
    sponsorable_repo_owner_ids = User.sponsorable_user_ids_from(repo_owner_ids,
      viewer: current_user, limit: -1)
    repo_owner_ids_by_repo_id
      .map { |repo_id, owner_id| [repo_id, sponsorable_repo_owner_ids.include?(owner_id)] }
      .to_h
  end

  # Private: Determine for each repository search result whether the repo's owner is
  # currently being sponsored on GitHub Sponsors by the current user.
  #
  # repository_results - a Search::Results
  #
  # Returns a Hash of Repository ID => Boolean.
  def get_sponsoring_status_by_repo_id(repository_results)
    return {} unless GitHub.sponsors_enabled? && logged_in?

    repo_owner_ids_by_repo_id = get_repo_owner_ids_by_repo_id(repository_results)
    repo_owner_ids = repo_owner_ids_by_repo_id.values.uniq
    sponsor_status_by_sponsorable_id = Sponsorship.sponsor_status_by_sponsorable_id(
      sponsorable_ids: repo_owner_ids,
      sponsor_id: current_user.id
    )
    repo_owner_ids_by_repo_id
      .map { |repo_id, owner_id| [repo_id, sponsor_status_by_sponsorable_id[owner_id]] }
      .to_h
  end

  # Private: Get a hash of repo owner IDs for each repository search result.
  #
  # Returns a Hash of Repository ID => User/Organization ID.
  def get_repo_owner_ids_by_repo_id(repository_results)
    repos = repository_results.results.map { |result| result["_model"] }
    repos.map { |repo| [repo.id, repo.owner_id] }.to_h
  end

  def request_is_rate_limited?
    !logged_in?
  end

  def topics_rate_limit_key
    key_base = "#{self.class.to_s.underscore}:#{action_name}"
    actor_identifier = request.env.fetch("HTTP_X_SSL_JA3_HASH", nil)
    actor_identifier = request.remote_ip if actor_identifier.blank?
    "#{key_base}:#{actor_identifier}"
  end
end
