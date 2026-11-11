# typed: true
# frozen_string_literal: true

class Discussion
  # Handles the various control flows through Discussions. Specifically, it manages
  # things like query parameters and redirection logic.
  class ListControlFlow
    include GitHub::Memoizer
    include UrlHelpers

    DEFAULT_SEARCH_QUERY = [[:is, "open"]]

    sig { params(params: T.untyped, repo: Repository, parsed_discussions_query: T.untyped).void }
    def initialize(params:, repo:, parsed_discussions_query:)
      @params = params
      @repo = repo
      @parsed_discussions_query = parsed_discussions_query
    end

    # Public: Does the page need to be redirected?
    #
    # This could be due to query state params that need to be merged into the search string query param, or because
    # this request is meant to have a vanity URL for a single-category-term search.
    #
    # Returns a Boolean.
    sig { returns(T.untyped) }
    def needs_redirection?
      redirect_path.present?
    end

    # Public: Generate the target URL that the current request should be redirect to, or nil if no redirection is
    # necessary.
    #
    # Examines the all `category:"Name"` terms from the `:discussions_q` URL parameter. If the query contains exactly
    # one `category:` term, redirect to that category's vanity URL (if you aren't already on it). The `:discussions_q`
    # parameter is *omitted* if the `category:` term is the *only* term in the query, and included if there are any
    # other terms. Similarly, if the current request is a category vanity URL, redirect if the query is for a different
    # category, or to the plain `/discussions` index URL if it contains zero or many `category:` terms.
    #
    # Returns a String containing the URL of the redirect target, or nil if no redirection is necessary.
    sig { returns(T.untyped) }
    def redirect_path
      return @redirect_path if defined?(@redirect_path)

      @redirect_path = nil
      redirect_params = { user_id: repo.owner_display_login, repository: repo.name }

      url_category_slug = params[:category_slug]
      query_is_empty = parsed_discussions_query.empty?
      query_has_non_category_terms = query_category_slugs.size != parsed_discussions_query.size
      query_needs_redirect = false

      if author = params.delete(:author)
        parsed_discussions_query.reject! { |term| term.try(:first) == :author }
        parsed_discussions_query << [:author, author]
        query_needs_redirect = true
      end

      if url_category_slug
        # These cases handle what happens when the current request is a category vanity URL.
        # /:owner/:repo/discussions/categories/:category_slug

        if query_category_slugs.none?
          # Category term is present in the URL, but not in the query.
          #
          # If the query is completely empty, artificially add a `category:"Name"` term to the query and render the page
          # directly. If the query contains any other terms, perform a redirect with the appended query.

          url_category = repo.available_discussion_categories.find_by(slug: url_category_slug)
          parsed_discussions_query << [:category, url_category&.name || url_category_slug]

          unless query_is_empty
            @redirect_path = agnostic_discussion_category_path(**redirect_params.merge(
              category_slug: url_category_slug,
              discussions_q: stringified_discussions_query,
            ))
          end
        elsif query_category_slugs.one?
          # Category term is present in the URL and in the query.
          #
          # If the category from the URL slug matches the category from the query render the page directly.
          # If the categories do *not* match, redirect to the categories path with the category from the query
          # as its URL slug.

          if url_category_slug != query_category_slugs.first
            if query_has_non_category_terms
              redirect_params[:discussions_q] = stringified_discussions_query
            end

            @redirect_path = agnostic_discussion_category_path(**redirect_params.merge(
              category_slug: query_category_slugs.first
            ))
          end
        else
          # There's a category in the URL, but the query has multiple category terms.
          #
          # Redirect to the non-category-slug index path, preserving the query unaltered.
          @redirect_path = agnostic_discussion_index_path(**redirect_params.merge(
            discussions_q: stringified_discussions_query,
          ))
        end
      else
        # These cases handle what happens when the current request is a plain index request.
        # /:owner/:repo/discussions

        if query_category_slugs.one?
          # No category in the URL, but one category term in the query. Redirect to the category_slug URL. If the
          # query includes any non-category terms as well, include the query in the URL, otherwise leave it off.

          if query_has_non_category_terms
            redirect_params[:discussions_q] = stringified_discussions_query
          end

          @redirect_path = agnostic_discussion_category_path(**redirect_params.merge(
            category_slug: query_category_slugs.first,
          ))
        end

        # query_categories.empty?: No category in the URL or in the query = render results directly.
        # query_categories.many?: No category in the URL, but many category terms in the query = render results directly.
      end

      # If the URL slug and query terms are in sync, but the query needs to be rewritten to follow an ?author= parameter,
      # perform the redirect here.
      if @redirect_path.nil? && query_needs_redirect
        if url_category_slug
          redirect_params[:discussions_q] = stringified_discussions_query if query_has_non_category_terms
          @redirect_path = agnostic_discussion_category_path(**redirect_params.merge(
            category_slug: url_category_slug,
          ))
        else
          @redirect_path = agnostic_discussion_index_path(**redirect_params.merge(
            discussions_q: stringified_discussions_query,
          ))
        end
      end

      @redirect_path
    end

    sig { returns(T.untyped) }
    def query
      if params[:discussions_q].nil?
        DEFAULT_SEARCH_QUERY + parsed_discussions_query
      else
        parsed_discussions_query
      end
    end

    private

    attr_reader :params, :parsed_discussions_query, :repo

    def agnostic_discussion_category_path(args = {})
      if params.has_key?(:org)
        args.delete(:user_id)
        args.delete(:repository)
        org_discussions_category_path(org: params[:org], **args)
      else
        category_discussions_path(**args)
      end
    end

    def agnostic_discussion_index_path(args = {})
      if params.has_key?(:org)
        args.delete(:user_id)
        args.delete(:repository)
        org_discussions_path(org: params[:org], **args)
      else
        discussions_path(**args)
      end
    end

    def stringified_discussions_query
      Search::Queries::DiscussionQuery.stringify(parsed_discussions_query)
    end

    memoize def query_category_slugs
      Discussion::SearchTerm.values(:category, parsed_discussions_query: parsed_discussions_query)
        .map { |value| DiscussionCategory.slug_for_name(value) }
    end
  end
end
