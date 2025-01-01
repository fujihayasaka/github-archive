# typed: true
# frozen_string_literal: true

module Search
  class ResultsView
    include EscapeHelper
    include CommitHelper

    attr_reader :view, :current_repository

    # Required for platform_execute
    # cap_filter is used by the PlatformHelper
    attr_reader :current_user, :user_session, :controller_name, :action_name, :request,
                :log_data, :session, :params, :cap_filter, :defer_commit_badges

    def initialize(view, queries:, type:, search:, unscoped_search:, elastic_search_down:, current_repository:, current_user:, user_session:, controller_name:, action_name:, request:, log_data:, session:, stats_ui_enabled:, params:, cap_filter:)
      @view                = view
      @queries             = queries
      @type                = type
      @search              = search
      @unscoped_search     = unscoped_search
      @elastic_search_down = elastic_search_down
      @current_repository  = current_repository
      @current_user        = current_user

      # Required for platform_execute
      @controller_name             = controller_name
      @action_name                 = action_name
      @request                     = request
      @log_data                    = log_data
      @session                     = session
      @user_session                = user_session
      @stats_ui_enabled            = stats_ui_enabled
      @params                      = params
      @cap_filter                  = cap_filter
    end

    # Required for platform_execute
    def stats_ui_enabled?
      !!@stats_ui_enabled
    end

    # DEPRECATED: this method is invoked in PlatformHelper#platform_context
    # Consider using a Conditional Access Policy(CAP) method alternative if your intention is to filter resource(s).
    #
    # Read more: https://thehub.github.com/engineering/development-and-ops/dotcom/cap/update-callsite-to-cap-filtering
    def unauthorized_organization_ids
      cap_filter.unauthorized_resource_ids(current_user&.resources_for_cap_filter)
    end

    def repo_specific?
      !!current_repository
    end

    def code_is_searchable?
      !repo_specific? || current_repository.code_is_searchable?
    end

    def render_filter
      results.search_action_packages_enabled! if FeatureFlag.vexi.enabled_or_raise?(:search_action_packages, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      locals = {
        results: results,
        elastic_search_down:  @elastic_search_down,
      }
      case query
      when Search::Queries::UserQuery
        view.render partial: "codesearch/filters_user", locals: locals
      when Search::Queries::CodeQuery
        view.render partial: "codesearch/filters_code", locals: locals
      when Search::Queries::CommitQuery
        view.render partial: "codesearch/filters_commit", locals: locals
      when Search::Queries::IssueQuery
        view.render partial: "codesearch/filters_issue", locals: locals
      when Search::Queries::RegistryPackageQuery
        view.render partial: "codesearch/filters_package", locals: locals
      when Search::Queries::WikiQuery
        view.render partial: "codesearch/filters_wiki", locals: locals
      when Search::Queries::DiscussionQuery
        if GitHub.discussions_available_on_platform?
          view.render partial: "codesearch/filters_discussion", locals: locals
        end
      else
        view.render partial: "codesearch/filters_repo", locals: locals
      end
    end

    def render_sort
      case query
      when Search::Queries::UserQuery
        view.render partial: "codesearch/sort_user", locals: { results: results }
      when Search::Queries::CodeQuery
        view.render partial: "codesearch/sort_code", locals: {
          results: results,
          repository: repo_specific? && current_repository,
          unscoped_search: @unscoped_search,
        }
      when Search::Queries::CommitQuery
        view.render partial: "codesearch/sort_commit", locals: {
          results: results,
          repository: repo_specific? && current_repository,
          elastic_search_down: @elastic_search_down,
          unscoped_search: @unscoped_search,
        }
      when Search::Queries::IssueQuery
        view.render partial: "codesearch/sort_issue", locals: {
          results: results,
          repository: repo_specific? && current_repository,
          unscoped_search: @unscoped_search,
        }
      when Search::Queries::MarketplaceQuery
        view.render partial: "codesearch/sort_marketplace", locals: { results: results }
      when Search::Queries::RegistryPackageQuery
        view.render partial: "codesearch/sort_package", locals: {
          results: results,
          repository: repo_specific? && current_repository,
        }
      when Search::Queries::TopicQuery
        view.render partial: "codesearch/sort_topics", locals: { results: results }
      when Search::Queries::WikiQuery
        view.render partial: "codesearch/sort_wiki", locals: {
          results: results,
          repository: repo_specific? && current_repository,
          unscoped_search: @unscoped_search,
        }
      when Search::Queries::DiscussionQuery
        if GitHub.discussions_available_on_platform?
          view.render partial: "codesearch/sort_discussion", locals: {
            results: results,
            repository: repo_specific? && current_repository,
            unscoped_search: @unscoped_search,
          }
        end
      else
        locals = { results: results, unscoped_search: @unscoped_search }
        if show_topic_callout?
          locals[:show_topic_callout] = true
          locals[:linked_topic], locals[:curated_topic] = topic_callout_topics
        else
          locals[:show_topic_callout] = false
        end
        view.render partial: "codesearch/sort_repo", locals: locals
      end
    end

    def render_results
      if is_current_view("Code") && !code_is_searchable?
        view.render partial: "repository_search/not_searchable", locals: {
          results: results,
          repo_specific: repo_specific?,
        }
      else
        case query
        when Search::Queries::UserQuery
          view.render partial: "codesearch/results_user", locals: {
            results: results,
            repo_specific: repo_specific?,
          }
        when Search::Queries::TopicQuery
          # Preload for star buttons
          if current_user
            topics = results.map(&:topic)
            Stars.domain.precache_topics_starred_by_user?(topics.pluck(:id), current_user.id)
          end

          view.render partial: "codesearch/results_topic", locals: {
            results: results
          }
        when Search::Queries::CodeQuery
          view.render partial: "codesearch/results_code", locals: {
            results: results,
            repo_specific: repo_specific?,
            current_repository: current_repository,
            unscoped_search: @unscoped_search,
          }
        when Search::Queries::CommitQuery
          view.render partial: "codesearch/results_commit", locals: {
            results: results,
            repo_specific: repo_specific?,
            current_repository: current_repository,
            search: @search,
            commits: load_commits(results),
            unscoped_search: @unscoped_search,
          }
        when Search::Queries::IssueQuery
          view.render partial: "codesearch/results_issue", locals: {
            results: results,
            repo_specific: repo_specific?,
            current_repository: current_repository,
            unscoped_search: @unscoped_search,
          }
        when Search::Queries::MarketplaceQuery
          view.render partial: "codesearch/results_marketplace", locals: {
            results: results,
            search: @search,
          }
        when Search::Queries::RegistryPackageQuery
          view.render partial: "codesearch/results_package", locals: {
            results: results,
            search: @search,
            repo_specific: repo_specific?,
            current_repository: current_repository,
          }
        when Search::Queries::WikiQuery
          view.render partial: "codesearch/results_wiki", locals: {
            results: results,
            repo_specific: repo_specific?,
            unscoped_search: @unscoped_search,
          }
        when Search::Queries::DiscussionQuery
          if GitHub.discussions_available_on_platform?
            view.render partial: "codesearch/results_discussion", locals: {
              results: results,
              repo_specific: repo_specific?,
              current_repository: current_repository,
              unscoped_search: @unscoped_search,
            }
          end
        else
          view.render partial: "codesearch/results_repo", locals: {
            results: results,
            show_explore_topics: show_explore_topics?,
            repo_specific: repo_specific?,
            unscoped_search: @unscoped_search,
          }
        end
      end
    end

    def link_to_repos(**link_options)
      link_to_menu("Repositories", **link_options)
    end

    def link_to_users(**link_options)
      link_to_menu("Users", **link_options)
    end

    def link_to_code(**link_options)
      link_to_menu("Code", **link_options)
    end

    def link_to_commits(**link_options)
      link_to_menu("Commits", **link_options)
    end

    def link_to_issues(**link_options)
      link_to_menu("Issues", **link_options)
    end

    def link_to_discussions(**link_options)
      return unless GitHub.discussions_available_on_platform?

      link_options[:test_selector] = "discussions-link"
      link_to_menu("Discussions", **link_options)
    end

    def link_to_packages(**link_options)
      return unless PackageRegistryHelper.show_packages?
      link_options[:label] = "Packages"
      link_to_menu("RegistryPackages", **link_options)
    end

    def link_to_wikis(**link_options)
      link_to_menu("Wikis", **link_options)
    end

    def link_to_topics(**link_options)
      link_to_menu("Topics", **link_options)
    end

    def link_to_marketplace(**link_options)
      link_to_menu("Marketplace", **link_options)
    end

    def self.repository_for_frontend_rendering(repo)
      {
        repository: {
          id: repo.id,
          name: repo.name,
          owner_id: repo.owner_id,
          owner_login: repo.owner_display_login,
          updated_at: repo.pushed_at || repo.created_at,
          has_issues: repo.has_issues
        }
      }
    end

    private

    def query_has_topic_qualifier?
      query.qualifiers.key?(:topic) && query.qualifiers[:topic].must
    end

    # Should the 'Explore topics' section be shown?
    def show_explore_topics?
      query_has_topic_qualifier?
    end

    def topic_callout_topics
      return @topic_callout_topics if @topic_callout_topics

      linked_topic = Topic.find_by(name: topic_name_from_query)

      unless linked_topic
        @topic_callout_topics = []
        return @topic_callout_topics
      end

      curated_topic = if linked_topic.featured? && linked_topic.curated?
        linked_topic
      elsif (source_topic = linked_topic.alias_source_topic)
        source_topic if source_topic.featured? && source_topic.curated?
      end

      @topic_callout_topics = [linked_topic, curated_topic]
    end

    def topic_qualifier
      query.qualifiers[:topic].must.first
    end

    # Private: Returns a topic pulled from the search query.
    #
    # Returns a String or nil.
    def topic_name_from_query
      return @topic_name_from_query if defined? @topic_name_from_query
      topic_name = nil
      if query_has_topic_qualifier?
        topic_name = Topic.extract_featured_topic_name(topic_qualifier)
      end
      topic_name ||= Topic.extract_featured_topic_name(query.query)
      @topic_name_from_query = topic_name
    end

    # Private: Should a callout to visit a topic page be shown in the search results page?
    #
    # Only shows a callout for topics for which we have curated content that we want to feature.
    #
    # Returns a Boolean.
    def show_topic_callout?
      # Topic pages are not enabled on Enterprise.
      return false if GitHub.enterprise?

      # Don't show a callout for a particular topic when all the search results will be topics.
      return false if is_current_view("Topics")

      # Didn't find a topic in the query for which we had curated content:
      return false unless topic_name_from_query.present?

      # Ensure we found a topic to link to and a curated topic:
      linked_topic, curated_topic = topic_callout_topics
      linked_topic && curated_topic
    end

    # Returns the selected Query whose results are displayed.
    def query
      @queries[@type]
    end

    # Returns true if the `type` is for the results that are currently being
    # viewed.
    #
    # type - The type String
    def is_current_view(type)
      @type == type
    end

    def link_to_menu(type, label: nil, link_classes: "", fetch_counter: true, test_selector: nil)
      link_classes = "menu-item" if link_classes.empty?
      link_classes = "#{link_classes} selected" if is_current_view(type)
      url = view.link_to_search(type: type.downcase, p: nil, s: nil, o: nil, q: params[:q])

      label ||= type
      counter = counter(type, fetch_counter: fetch_counter)
      inner = safe_join([label, counter])

      options = { class: link_classes }
      options = options.merge(view.test_selector_data_hash(test_selector)) if test_selector

      view.link_to(inner, url, options)
    end

    def counter(type, fetch_counter: true)
      query = @queries[type]

      total = if is_current_view(type)
        if type == "Topics" && !results.includes_public_repositories?
          0
        elsif type == "Users"
          results.results.length
        elsif type == "RegistryPackages"
          results.results.length
        else
          results.total
        end
      end

      timed_out = if is_current_view(type)
        results.timed_out || results.count_truncated?
      else
        false
      end

      count = Search::CountView.new(
        query: query,
        type: type,
        count: total,
        timed_out: timed_out,
      )

      if is_current_view(type) || count.cached?
        count.render
      elsif fetch_counter
        url = view.url_with(action: "count", type: type)
        view.render(Primer::Alpha::IncludeFragment.new(src: url))
      else
        view.content_tag(:span, "", class: "d-none js-codesearch-deferred-count", "data-search-type": type)
      end
    end

    def results
      @results ||=
        begin
          query.execute
        rescue StandardError => boom # rubocop:todo Lint/RescueException
          Failbot.report(boom.with_redacting!)
          Search::Results.empty
        end
    end

    def stats_tags
      ["query_class:#{query.class.name}", "query_type:#{@type}"]
    end

    def load_commits(results)
      commit_promises = results.map do |hit|
        Platform::Loaders::GitObject.load(hit["_model"], hit["_source"]["hash"], expected_type: "commit")
      end

      commits = Promise.all(commit_promises).sync.compact

      preload_promises = commits.flat_map do |commit|
        [
          # Preload message HTML
          commit.async_message_body_html,
          commit.async_short_message_html,
          # Preload if commits have status check rollups
          commit.async_has_status_check_rollup?,
        ]
      end
      Promise.all(preload_promises).sync

      # Preload comment counts
      commits.group_by(&:repository).each do |repository, repo_commits|
        Commit.prefill_comment_counts(repo_commits, repository)
      end

      commits.index_by { |commit| [commit.repository, commit.oid] }
    end
  end
end
