# typed: true
# frozen_string_literal: true

class Discussion
  class SearchResult
    extend T::Sig

    # Public: Load discussions using MySQL or ElasticSearch (and MySQL)
    #
    # query - parsed search query, e.g. ["foo", [:author, "iancanderson"]]
    # page - page to load as a string or integer, e.g. "2"
    # per_page - discussions per page, e.g. "20"
    # repo - Repository to search within, if any
    # category_ids - Discussion categories to search
    # ngram_title - Whether the search should include partial matches to the title
    #
    # Returns a paginated list of Discussions.
    sig do
      params(
        query: T.untyped,
        page: T.nilable(T.any(String, Integer)),
        per_page: T.nilable(T.any(String, Integer)),
        current_user: T.nilable(User),
        repo: T.nilable(Repository),
        category_ids: T.nilable(T::Array[T.any(Integer, String)]),
        remote_ip: T.nilable(String),
        user_session: T.nilable(UserSession),
        ngram_title: T::Boolean
      ).returns(WillPaginate::Collection)
    end
    def self.search(query:, page:, per_page:, current_user:, repo: nil, category_ids: nil, remote_ip: nil, user_session: nil, ngram_title: false)
      new(query: query, page: page, per_page: per_page, current_user: current_user, repo: repo,
        category_ids: category_ids, remote_ip: remote_ip, user_session: user_session, ngram_title: ngram_title).search
    end

    sig do
      params(
        query: T.untyped,
        page: T.nilable(T.any(String, Integer)),
        per_page: T.nilable(T.any(String, Integer)),
        current_user: T.nilable(User),
        repo: T.nilable(Repository),
        category_ids: T.nilable(T::Array[T.any(Integer, String)]),
        remote_ip: T.nilable(String),
        user_session: T.nilable(UserSession),
        ngram_title: T::Boolean
      ).void
    end
    def initialize(query:, page:, per_page:, current_user:, repo: nil, category_ids: nil, remote_ip: nil, user_session: nil, ngram_title: false)
      @query = query
      @page = (page || 1).to_i
      @per_page = (per_page || 25).to_i
      @repo = repo
      @category_ids = category_ids
      @current_user = current_user
      @remote_ip = remote_ip
      @user_session = user_session
      @ngram_title = ngram_title
    end

    sig { returns WillPaginate::Collection }
    def search
      discussion_query = ::Search::Queries::DiscussionQuery.new(
        phrase: sanitized_query_string,
        repo_id: repo&.id,
        category_ids: category_ids,
        page: page,
        per_page: per_page,
        current_user: current_user,
        remote_ip: remote_ip,
        user_session: user_session,
        ngram_title: ngram_title,
        top_filter_only_unlocked: repo&.feature_enabled?(:discussions_top_filter_only_unlocked),
      )
      es = begin
        discussion_query.execute
      rescue ElastomerClient::Client::Error => boom
        Failbot.report(boom.with_redacting!)
        Search::Results.empty
      end

      es = Search::Results.empty if es.error?

      WillPaginate::Collection.create(page, per_page, es.total) do |pager|
        pager.replace(es.models)

        pager.total_entries = if es.total > ::Search::Query::max_offset_default
          ::Search::Query::max_offset_default
        else
          es.total
        end
      end
    end

    private

    attr_reader :current_user, :query, :repo, :category_ids,
      :remote_ip, :user_session, :ngram_title

    sig { returns Integer }
    attr_reader :page, :per_page

    sig { returns String }
    def sanitized_query_string
      @sanitized_query_string ||= Search::Queries::DiscussionQuery.stringify(query)
    end
  end
end
