# typed: true
# frozen_string_literal: true

require "blackbird-client"

module BlackbirdControllerMethods
  include LanguageHelper
  include CommitHelper
  include TextHelper
  include FeatureFlagHelper
  include SiteHelper
  include BlackbirdIndexHelper
  include Search::Blackbird::Features

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { abstract.returns(T.nilable(User)) }
  def current_user; end

  sig { abstract.returns(T::Boolean) }
  def logged_in?; end

  # The following methods are to be overridden by controllers that include this module, but it is not made abstract,
  # because not all controllers need it
  sig { returns(T::Array[T.untyped]) }
  def legacy_query; []; end

  sig { returns(String) }
  def type; ""; end

  sig { returns(String) }
  def client_type; ""; end

  EXCEPTIONS = [::Twirp::Error, ::Faraday::ConnectionFailed, ::Faraday::TimeoutError, SystemCallError, RuntimeError, ArgumentError].freeze

  # The goal of caching search results is to improve the performance when a
  # user is switching between pages and tabs, potentially to pages for which
  # data has already been loaded. This expiration timeout is a middle-of-the-road
  # estimate for the amount of time a user might spend going through a particular
  # set of search results, without being so long as to disrupt the workflow of
  # adding data and then searching for it.
  @@search_cache_expiration = 5.minutes

  @@max_feedback_length = 4096

  def warm_blackbird_caches
    return head(:unauthorized) unless logged_in?

    key = BlackbirdSearch::Redis.key(
      key_prefix: BlackbirdSearch::Redis::DEFAULT_KEY_PREFIX,
      actor_id: user_session.user.id,
      session_id: user_session.hashed_key,
      ip_address: request.remote_ip
    )

    result = BlackbirdSearch::Redis.pttl(key: key)
    if !result.ok?
      GitHub.logger.error("warm blackbird caches failed", {
        "exception" => result.error,
        "code.function" => __method__,
        "code.namespace" => self.class.name,
      })
      return head(:service_unavailable)
    end

    ttl_ms = result.value!
    if ttl_ms <= 5.minutes.to_i * 1000
      BlackbirdSearch::Redis.with_redis_retry do
        BlackbirdAccessibleResourcesJob.perform_later(
          actor: T.must(current_user),
          auth_id: user_session.id,
          auth_type: :user_session,
          expires_at: nil,
          has_lock: false,
          key_prefix: BlackbirdSearch::Redis::DEFAULT_KEY_PREFIX,
          request_id: request_id,
          request_user_ip: request.remote_ip,
          session_id: user_session.hashed_key,
          token_kind: BlackbirdSearch::Client::ACCESS_TOKEN_KIND_WEB
        )
      end
      ttl_ms = 10.minutes.to_i * 1000
    end

    render(json: {
      userCacheExpiresAt: (Time.now + ttl_ms / 1000).utc.iso8601,
    })
  end

  def check_indexing_status
    nwo = params[:nwo] || ""
    repo = Repository.nwo(nwo)
    if repo.nil? || !repo.readable_by?(current_user) || !cap_filter.unauthorized([repo]).empty?
      return head :not_found
    end

    cir = CopilotIndexedRepositories.find_by(repository: repo.id)
    code_status = if cir.nil?
      :not_indexed
    else
      cir.semantic_code_search_ok? ? :indexed : :indexing
    end

    user = T.must(current_user)
    response = {
      code_status: code_status,
      docs_status: code_status, # NB: `docs_status` is deprecated
      can_index: can_index_embeddings_status(user, repo),
    }

    render json: response
  end

  def index_embeddings
    user = current_user
    return head :forbidden unless user

    nwos = !!params[:nwos] ? JSON.parse(params[:nwos]) : []
    if params[:nwo]
      nwos << params[:nwo]
    end
    nwos.each do |nwo|
      repo = Repository.nwo(nwo)
      if repo.nil?
        return head :not_found
      end
      status = trigger_embeddings_indexing(user, repo, index_code: params[:index_code], index_docs: !params[:index_code])

      return head :forbidden if status == :quota_exhausted
      return head status if status != :ok

      if Copilot::Public::User::new(user).has_ci_access?
        current_count = user.settings.get(:copilot_indexed_repo_count)
        user.settings.set!(:copilot_indexed_repo_count, current_count + 1)
      end
    end

    render json: {
      success: true,
    }
  end

  def delete_embeddings
    nwos = !!params[:nwos] ? JSON.parse(params[:nwos]) : []
    if params[:nwo]
      nwos << params[:nwo]
    end
    nwos.each do |nwo|
      repo = Repository.nwo(nwo)
      if repo.nil?
        return head :not_found
      end
      status = can_index_embeddings_status(T.must(current_user), repo)

      if status != :ok
        return head status
      end

      # Delete the CopilotIndexedRepositories record if it exists
      CopilotIndexedRepositories.where(repository_id: repo.id, organization_id: repo.owner.id).delete_all

      # Force reindexing
      BlackbirdOnboardReposJob.perform_later(T.must(T.must(current_user).id), [repo.id])
    end

    render json: {
      success: true,
    }
  end

  def refresh_blackbird_caches
    BlackbirdSearch::Redis.with_redis_retry do
      BlackbirdAccessibleResourcesJob.perform_later(
        actor: T.must(current_user),
        auth_id: user_session.id,
        auth_type: :user_session,
        expires_at: nil,
        has_lock: false,
        key_prefix: BlackbirdSearch::Redis::DEFAULT_KEY_PREFIX,
        request_id: request_id,
        request_user_ip: request.remote_ip,
        session_id: user_session.hashed_key,
        token_kind: BlackbirdSearch::Client::ACCESS_TOKEN_KIND_WEB
      )
    end

    redirect_to_return_to
  end

  def blackbird_count
    return head(:unauthorized) unless logged_in?

    if !FeatureFlag.vexi.enabled_or_raise?(:skip_search_cache, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      expires_in @@search_cache_expiration
    end

    query = params[:q] || ""
    custom_scopes = params[:saved_searches] || "[]"
    begin
      scopes = JSON.parse(custom_scopes)
    rescue JSON::ParserError
      scopes = []
    end

    if !scopes.kind_of?(Array)
      scopes = []
    end

    request_timeout = GitHub.request_timeout(T.must(request).env) - 1
    actor = ::BlackbirdSearch::Client.actor(T.must(current_user), user_session, request.remote_ip)
    proto_scopes = scopes.map { |s| ::Blackbird::Query::V1::CustomScope.new(s) }
    response = ::BlackbirdSearch::Client.count(
      T.must(current_user),
      actor: actor,
      tenant: current_tenant,
      query: query,
      custom_scopes: proto_scopes,
      experiments: experiments,
      request_timeout: Google::Protobuf::Duration.new(seconds: request_timeout),
      context: "web",
    )

    respond_to do |format|
      format.json do
        render json: response
      end
    end
  end

  def blackbird_search
    if !FeatureFlag.vexi.enabled_or_raise?(:skip_search_cache, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      expires_in @@search_cache_expiration
    end

    query = params[:q] || ""
    custom_scopes = params[:saved_searches] || "[]"
    results = nil
    page_count = nil
    errors = []
    start_time = Time.now
    current_page = 0
    result_count = 0
    protected_orgs = []
    protected_org_logins = []
    facets = []
    query_id = ""
    metadata = nil
    warn_limited_results = false

    add_react_search_feature_flags

    begin
      if params[:type].to_s.downcase == "codelegacy"
        render_react_app(
          payload: {
            results: [],
            type: "codelegacy",
            page: 1,
            page_count: 1,
            elapsed_millis: 0,
            errors: [{ message: "Legacy code search is no longer supported." }],
            result_count: 0,
            logged_in: logged_in?,
          },
          title: "Search error",
          page_data: { footer: false },
        )
        return
      end
      if client_type == Search::ClientTypes::CODE
        begin
          scopes = JSON.parse(custom_scopes)
        rescue JSON::ParserError
          scopes = []
        end

        if !scopes.kind_of?(Array)
          scopes = []
        end

        if logged_in?
          response = query_blackbird(query, scopes, experiments)

          if response[:failed]
            errors = [{ message: error_message(response[:error_message]) }]
            results = []
          else
            results = response[:results]
            errors = response[:errors]
            query_id = response[:query_id]
            # Note: blackbird uses 0-indexed page numbers, but the frontend uses 1-indexed.
            current_page = response[:page] + 1
            page_count = response[:page_count]
            result_count = response[:result_count]
            facets = response[:facets]
            metadata = response[:metadata]
            blackbird_protected_org_ids = response[:protected_organization_ids]
            if blackbird_protected_org_ids.any?
              protected_orgs = Organization.where(id: blackbird_protected_org_ids)
            end
          end
        else
          results = []
        end

      else
        # legacy_query should be implemented by descendant class
        legacy_response, result_query = legacy_query
        if GitHub.blackbird_use_fake_legacy_data
          legacy_response = JSON.parse(File.read("#{__dir__}/../../lib/search/legacy_response.json"))
          render_react_app(
            payload: legacy_response[type],
            page_data: { footer: false },
            disable_ssr: true, # disabled until this app is ready for SSR
          )
          return
        else
          results = populate_results_data(legacy_response, result_query)

          warn_limited_results = result_query.warn_limited_results? if result_query&.respond_to?(:warn_limited_results?)
          GitHub.dogstats.increment("repos.search.warn_limited_results") if warn_limited_results
          warn_limited_results = FeatureFlag.vexi.enabled?(:repos_search_warn_limited_results, current_user, default: false)
        end
        page_count = legacy_response.total_pages
        result_count  = legacy_response.total

        #if ff enabled for search_action_packages, then we need to pass true as param to package_types
        legacy_response.search_action_packages_enabled! if FeatureFlag.vexi.enabled?(:search_action_packages, current_user, default: false)
        facets = transform_package_states(legacy_response.package_types)

        # It doesn't make sense to report language facets for issues
        if client_type != Search::ClientTypes::ISSUE && !params[:l]
          facets += transform_languages(legacy_response.languages)
        end

        current_page = current_page(:p)
        protected_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)
        if protected_org_ids.any?
          protected_orgs = Organization.where(id: protected_org_ids)
        end
      end
      if protected_orgs.any?
        protected_org_logins = protected_orgs.pluck(:display_login)
      end

      elapsed_millis = ((Time.now - start_time).to_f * 1000).to_i

      if GitHub.signup_enabled?
        sign_up_path = nux_signup_index_path(source: "code_search_results")
      end

      render_react_app(
        payload: {
          header_redesign_enabled: header_redesign_enabled?,
          results: results.as_json(dangerously_allow_all_keys: true),
          type: client_type.downcase,
          page: current_page,
          page_count: page_count,
          elapsed_millis: elapsed_millis,
          errors: errors,
          result_count: result_count,
          facets: facets,
          protected_org_logins: protected_org_logins,
          topics: topic_callout_topics_for_frontend_rendering,
          query_id: query_id,
          logged_in: logged_in?,
          sign_up_path: sign_up_path,
          sign_in_path: site_nav_login_path,
          metadata: metadata,
          warn_limited_results:,
        },
        title: page_title(client_type, query),
        page_data: { footer: false },
      )

    rescue *EXCEPTIONS => e
      GitHub.logger.error("Failed", {
        :exception => e,
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        })

      render_react_app(
        payload: {
          results: [],
          type: client_type.downcase,
          page: 1,
          page_count: 1,
          elapsed_millis: elapsed_millis,
          errors: [{ message: error_message(e) }],
          result_count: 0,
          logged_in: logged_in?,
          sign_up_path: sign_up_path,
          sign_in_path: site_nav_login_path,
        },
        title: "Search error",
        page_data: { footer: false },
      )
    end
  end

  sig { params(client_type: String, query: String).returns(String) }
  def page_title(client_type, query)
    type = Search::ClientTypes.search_type_as_singular(client_type).capitalize
    "#{type} search results"
  end

  def suggestions
    query = params[:query]

    begin
      scopes = JSON.parse(params[:saved_searches] || "[]")
    rescue JSON::ParserError
      scopes = []
    end

    proto_scopes = scopes.map { |s| ::Blackbird::Query::V1::CustomScope.new(s) }
    actor = ::BlackbirdSearch::Client.actor(T.must(current_user), user_session, request.remote_ip)
    resp = ::BlackbirdSearch::Client.suggest(
      current_user,
      query: query,
      cursor_position: 0,
      actor: actor,
      tenant: current_tenant,
      custom_scopes: proto_scopes,
      experiments: experiments,
      request_timeout: Google::Protobuf::Duration.new(seconds: 2),
    )
    render layout: false, json: resp
  end

  def query_blackbird(query, custom_scopes, experiments)
    if query
      # Note: Blackbird uses 0-indexed page numbers
      page = current_page(:p)
      if page > 0
        page -= 1
      end

      request_timeout = GitHub.request_timeout(T.must(request).env) - 1
      actor = ::BlackbirdSearch::Client.actor(T.must(current_user), user_session, request.remote_ip)
      proto_scopes = custom_scopes.map { |s| ::Blackbird::Query::V1::CustomScope.new(s) }
      ::BlackbirdSearch::Client.query(T.must(current_user), cap_filter,
        actor: actor,
        tenant: current_tenant,
        query: query,
        results_per_page: 20,
        page_number: page,
        custom_scopes: proto_scopes,
        document_location_limit: 5,
        experiments: experiments,
        request_timeout: Google::Protobuf::Duration.new(seconds: request_timeout),
        snippet_options: {
          desired_width: 120,
          high_density_snippet_max_lines: 20,
        },
        context: "web",
      )
    else
      {
        failed: true,
        error_message: {
          message: "No query provided"
        }
      }
    end
  end

  # Copied from RepositorySearchController, mostly the same in CodeSearchController
  def language
    return @language if defined? @language
    name = params[:l] if params[:l].present?
    @language = name.kind_of?(String) ? Linguist::Language[name] : nil
  end

  def transform_languages(languages)
    # If only one language exists, then there's no need for facets
    if languages.length <= 1
      return []
    end

    [{
      kind: "FACET_KIND_LANGUAGE",
      entries: languages.select { |l| !l.language.nil? }.map { |l| { name: l.language.name, language_color: l.language.color, query: "language:#{l.language.name}" } }
    }]
  end

  def transform_package_states(states)
    # If only one facet exists, then there's no need for facets
    valid_states = states.select { |s| !s.nil? && s.any? }
    if states.length <= 1
      return []
    end

    [{
      kind: "FACET_KIND_PACKAGE_TYPE",
      entries: valid_states.map { |s| { name: s.term, query: "package_type:#{s.term}" } }
    }]
  end

  def get_languages(facets)
    return [] if facets.nil?
    languages = facets.find { |f| f[:kind] == :FACET_KIND_LANGUAGE }
    return [] if languages.nil?
    languages[:entries].map { |l| { name: l[:name], color: l[:language_color], query: l[:query] } }
  end

  def current_tenant
    ::BlackbirdSearch::Client.tenant(GitHub::CurrentTenant.get)
  end

  def require_feature_flags
    render_404 unless blackbird_enabled?
  end

  def error_message(e)
    case e
    when ::Twirp::Error, ::Faraday::ConnectionFailed, ::Faraday::TimeoutError
      "Search failed. Please try again later."
    else
      e.is_a?(Hash) ? e[:message] : e.message
    end
  end

  def normalize_qualifiers(query)
    restrict_type_qualifier_based_on_client_type(query)
    normalize_org_and_repo_qualifiers(query)
  end

  def restrict_type_qualifier_based_on_client_type(query)
    # Always override the query type to pull-requests when querying pull requests
    query.qualifiers[:type].clear.must("pull-request") if client_type == Search::ClientTypes::PULL_REQUEST

    # Only override the query type to issues when the type is not specified
    # i.e. allow the user to use the legacy behavior of searching issues, which allows finding PRs
    query.qualifiers[:type].clear.must("issue") if client_type == Search::ClientTypes::ISSUE && !query.qualifiers.key?(:type)
  end

  # If exactly one org is specified and exactly one repo is specified without the owner,
  # then search for that repo under the specified org
  def normalize_org_and_repo_qualifiers(query)
    # If more than one org or repo is specified as required, bail.
    # We don't know what to do with this, and we should expect 0 results anyway.
    return if query.qualifiers[:repo].must&.length != 1
    return if query.qualifiers[:org].must&.length != 1

    org = query.qualifiers[:org].must.first
    repo = query.qualifiers[:repo].must.first

    # If the org is already specified as part of the repo, bail.
    return if repo.include?("/")

    # Specify the repo and org together in the repo qualifier
    query.qualifiers[:org].clear
    query.qualifiers[:repo].clear.must(org + "/" + repo)
  end

  def client_type_to_type(ct)
    return Search::Types::ISSUE if ct == Search::ClientTypes::PULL_REQUEST

    # Other than these two additions, the client_type is the same as the type.
    ct
  end

  def is_legacy_code_search?
    params[:type].to_s.downcase == "code-legacy"
  end

  def populate_results_data(results, query)
    case type
    when Search::Types::COMMIT
      populate_commits_results_data(results)
    when Search::Types::DISCUSSION
      populate_discussion_results_data(results)
    when Search::Types::ISSUE
      populate_issues_results_data(results)
    when Search::Types::REPOSITORY
      populate_repository_results_data(results, query)
    when Search::Types::TOPIC
      populate_topics_results_data(results)
    when Search::Types::USER
      populate_user_results_data(results)
    when Search::Types::REGISTRY_PACKAGE
      populate_registry_package_results_data(results)
    when Search::Types::MARKETPLACE, Search::Types::WIKI, Search::Types::CODE
      results.results.each do |result|
        result.populate_results_data if result.respond_to?(:populate_results_data)
      end
    end

    results.results.map do |result|
      result.for_frontend_rendering
    end
  end

  def populate_commits_results_data(results)
    results = results.results.map! { |commit_data| Search::CommitResultView.new(commit_data) }
    commit_collections = []
    results.each do |result|
      commit_collections << Repositories.domain.commits.by_oid(repository: result.repository, commit_oid: result.sha) # NOT a db call
    end
    preload_commit_data(commit_collections)
    results.map.with_index do |result, index|
      # Checks Status
      # We only care about the first status since we're only sending 1 commit at a time
      result.status_check_rollup = commit_collections[index].status_check_rollup
      combined_status = Commit.prefill_combined_statuses([commit_collections[index]], result.repository)[0].combined_status
      view = create_view_model(Statuses::CombinedStatusView, {
        combined_status: combined_status,
        simple_view: true,
      })
      result.initialize_checks_status(view)

      result.initialize_commit_authors(commit_collections[index], current_user)

      result.has_signature = commit_collections[index].has_signature?
      result.verification_status = commit_collections[index].verification_status
      signed_commit_badge = Commits::SignedCommitBadge.for(commit_collections[index], current_user: current_user)
      result.initialize_signature(commit_collections[index], signed_commit_badge)

      result.hl_message(commit_collections[index], current_user)
      result.hl_subject = commit_short_message_link(commit_collections[index], "/#{result.repository.owner_display_login}/#{result.repository["name"]}/commit/#{result.sha}", result.hl_subject)
    end
  end

  def populate_discussion_results_data(results)
    user_ids = results.results.map { |result| result.user_id.to_i }
    users = make_hash(User.where(id: user_ids))
    results.results.each do |result|
      user = users[result.user_id.to_i]
      result.populate_results_data(user)
    end
  end

  def populate_issues_results_data(results)
    issues_ids = []
    pr_ids = []
    author_ids = []
    results.results.each do |result|
      if result.issue.pull_request_id.present?
        pr_ids << result.issue.pull_request_id
      end
      issues_ids << result.issue.id
      author_ids << result.author_id
    end
    authors = User.where(id: author_ids)
    issues = Issue.includes(:labels).find(issues_ids) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    prs = PullRequest.find(pr_ids)
    author_hash = make_hash(authors)
    issue_hash = make_hash(issues)
    pr_hash = make_hash(prs)
    results.results.each do |result|
      author = author_hash[result.author_id] || User.ghost
      result.labels = issue_hash[result.issue.id].sorted_labels&.map { |label| label.name_html }
      if result.issue.pull_request_id.present?
        result.reviewable_state = pr_hash[result.issue.pull_request_id].reviewable_state
        result.merged = pr_hash[result.issue.pull_request_id].merged_at.present?
      end
      result.author_name = author.display_login
      result.author_avatar_url = author.primary_avatar_url(48)
      result.hl_title
      result.hl_text
    end
  end

  def populate_registry_package_results_data(results)
    # filter where package is nil
    results.results = results.results.select { |result| result.package.present? }

    results.results.each do |result|
      result.populate_results_data
      v2_package = result.package.instance_of?(PackageRegistry::PackageMetadata)
      url_prefix = result.package.owner.is_a?(Organization) ? "orgs" : "users"
      if v2_package
        result.package_url = packages_two_view_path(url_prefix, result.package.owner.display_login, result.package.package_type, result.package.name)
      else
        result.package_url = package_path(result.package.owner, result.package.repository, result.package)
      end
    end
  end

  def populate_repository_results_data(results, query)
    starred_repository_names = is_anonymous_access? ? [] : T.must(current_user).starred_repositories
    results.results.each do |result|
      starred_result = starred_repository_names.detect do |el|
        el.name == result.repo.repository.name && el.owner_id == result.repo.repository.owner_id
      end
      result.populate_results_data(!!starred_result)
      add_csrf_token("/#{result.repo.repository.owner_display_login}/#{result.repo.repository.name}/star", :post)
      add_csrf_token("/#{result.repo.repository.owner_display_login}/#{result.repo.repository.name}/unstar", :post)
    end
    add_csrf_token("/sponsors/batch_deferred_sponsor_buttons", :post)
    if show_topic_callout?(query)
      topic_callout_topics(query)
    end
  end

  ## Following methods are copied from `app/view_models/search/results_view.rb`
  def query_has_topic_qualifier?(query)
    query.qualifiers.key?(:topic) && query.qualifiers[:topic].must
  end

  def topic_callout_topics(query)
    return @topic_callout_topics if @topic_callout_topics

    linked_topic = Topic.find_by(name: topic_name_from_query(query))

    unless linked_topic
      @topic_callout_topics = []
      return @topic_callout_topics
    end

    curated_topic = if linked_topic.featured? && linked_topic.curated?
      linked_topic
    elsif (source_topic = linked_topic.alias_source_topic)
      source_topic if source_topic.featured? && source_topic.curated?
    end

    @topic_callout_topics = {
      linked_topic_name: linked_topic.name,
      curated_topic: curated_topic
    }
  end

  # TODO: can we get more specific with the second parameter here?
  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def topic_callout_topics_for_frontend_rendering
    if @topic_callout_topics.nil?
      return nil
    end

    {
      linked_topic_name: @topic_callout_topics[:linked_topic_name],
      curated_topic: Search::TopicResultView::from_model(@topic_callout_topics[:curated_topic]).for_frontend_rendering
    }
  end

  def topic_qualifier(query)
    query.qualifiers[:topic].must.first
  end

  # Private: Returns a topic pulled from the search query.
  #
  sig { params(query: Search::Queries::RepoQuery).returns(T.nilable(String)) }
  def topic_name_from_query(query)
    return @topic_name_from_query if defined? @topic_name_from_query
    topic_name = nil
    if query_has_topic_qualifier?(query)
      topic_name = Topic.extract_featured_topic_name(topic_qualifier(query))
    end
    topic_name ||= Topic.extract_featured_topic_name(query.query)
    @topic_name_from_query = topic_name
  end

  # Private: Should a callout to visit a topic page be shown in the search results page?
  #
  # Only shows a callout for topics for which we have curated content that we want to feature.
  sig { params(query: Search::Queries::RepoQuery).returns(T.nilable(T::Boolean)) }
  def show_topic_callout?(query)
    # Topic pages are not enabled on Enterprise.
    return false if GitHub.enterprise?

    # Didn't find a topic in the query for which we had curated content:
    return false unless topic_name_from_query(query).present?

    # Ensure we found a topic to link to and a curated topic:
    linked_topic, curated_topic = topic_callout_topics(query)
    linked_topic && curated_topic
  end
  ## end copied methods

  # TODO: what on earth is the parameter type here?
  sig { params(results: T.untyped).void }
  def populate_topics_results_data(results)
    starred_topic_names = is_anonymous_access? ? [] : T.must(current_user).starred_topics.pluck(:name)
    results.results.each do |result|
      result.populate_results_data(starred_topic_names.include?(result.name))
      add_csrf_token("/topics/#{result.name}/star", :post)
      add_csrf_token("/topics/#{result.name}/unstar", :delete)
    end
  end

  # TODO: as above, what is the parameter type?
  sig { params(results: T.untyped).void }
  def populate_user_results_data(results)
    user_ids = results.results.map { |result| result.id.to_i }
    followed_users = logged_in? ? User.bulk_following_check(T.must(current_user).id, user_ids) : []
    results.results.each do |result|
      user = followed_users[result.id.to_i]
      result.populate_results_data(current_user, user)
      add_csrf_token("/sponsors/batch_deferred_sponsor_buttons", :post)
      if logged_in?
        add_csrf_token("/users/follow?target=#{result.display_login}", :post)
        add_csrf_token("/users/unfollow?target=#{result.display_login}", :post)
      end
    end
  end

  sig { returns(T::Boolean) }
  def is_anonymous_access?
    !current_user
  end

  # TODO: add parameterized type here
  sig { params(items: Enumerable).returns(T::Hash[Integer, T.untyped]) }
  def make_hash(items)
    hash = {}
    items.each do |item|
      hash[item.id] = item
    end
    hash
  end

  def preload_commit_data(commits)
    return [] if commits.empty?

    # prevents calling into verify_signature more than once when we hit verification_status on each commit
    Promise.all(commits.map(&:async_signature)).sync

    Promise.all(commits.map { |commit| [commit.verification_status, commit.status_check_rollup] }.flatten).sync

    # batch retrieve commit signatures
    Commit.prefill_verified_signature(commits, nil)
  end

  def feedback
    if feedback = params[:feedback]
      if logged_in? && params[:include_email].present?
        email = T.must(current_user).email
      end

      GlobalInstrumenter.instrument "blackbird.feedback", {
        feedback: feedback.truncate(@@max_feedback_length),
        email: email,
      }
    end

    head :ok
  end

  def add_react_search_feature_flags
    add_client_feature_flag([:code_nav_ui_events])
  end

  private

  sig { returns(T::Hash[String, String]) }
  def experiments
    if current_user&.employee?
      begin
        experiments = params[:experiments] || ""
        Hash[experiments.split(",").map { |x| x.split("=") }]
      rescue ArgumentError
        {}
      end
    else
      {}
    end
  end
end
