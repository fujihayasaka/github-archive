# typed: true
# frozen_string_literal: true

class Issue
  # Handles the various control flows through Issues. Specifically, it manages
  # things like query parameters and redirection logic.
  class ControlFlow
    # Routes
    include UrlHelpers

    include GitHub::RouteHelpers

    # The controller's `params` variable.
    attr_accessor :params

    # The search query, extracted from `params`.
    attr_writer :query

    # Are we looking at a page that should list pull requests only?
    attr_accessor :pulls_only

    # Did we rewrite the URL?
    attr_accessor :rewrote_url

    # Does this repository have Issues enabled?
    attr_accessor :has_issues

    # The repository
    attr_accessor :repo

    # The results from Search::Queries::IssueQuery.parse(@query).
    attr_accessor :components

    # The path that we're currently trying to access.
    attr_accessor :current_path

    # The current user.
    attr_accessor :current_user

    # Whether issues/PRs from archived repos are excluded.
    attr_accessor :exclude_archived

    def initialize(params:, repo: nil, components: nil, current_path: "", current_user: nil, exclude_archived: false)
      @params      = params

      @query       = params[:q].kind_of?(String) ? params[:q] : "is:issue is:open ".dup
      @pulls_only  = params[:pulls_only] || false
      @repo        = repo

      if components
        @components = components
      else
        @components = Search::Queries::IssueQuery.parse(@query)
      end

      @pulls_only  = true if params[:q] && [:type, :is].include?(@components.rassoc("pr").try(:first))

      params[:page] = [params[:page].to_s.to_i, 1].max if params[:page]

      # If we're on the dashboard, it always has issues.
      @has_issues  = @repo ? @repo.has_issues : true

      @current_path = current_path
      @current_user = current_user
      @exclude_archived = exclude_archived

      if components = query_components_from_params(@components, @params)
        @components  = components
        @query       = Search::Queries::IssueQuery.stringify(components)
        @rewrote_url = true
      else
        @rewrote_url = false
      end

      # The dashboard needs us to populate certain things.
      load_current_user_into_dashboard_params if !repo

      @query.rstrip!
    end

    # The search query. Sometimes we'll rewrite it. Don't worry about it.
    #
    # Returns a String.
    def query
      if params[:milestone] && milestone = repo.milestones.find_by_number(params[:milestone].to_i)
        @query << " milestone:#{Search::ParsedQuery.encode_value(milestone.title)}"
      end

      if exclude_archived && params[:q].blank?
        @query << " archived:false"
      end

      if pulls_only || !has_issues
        @query.gsub("is:issue", "is:pr")
      else
        @query
      end
    end

    # Does the page need to be redirected? This could be because of either clean
    # URL concerns, or Issues have been disabled.
    #
    # Returns a Boolean.
    def needs_redirection?
      needs_disabled_redirect? ||
        has_query_state_params? ||
        needs_clean_url_redirect?
    end

    # What's the actual path we should redirect users towards?
    #
    # Returns a String.
    def redirect_path
      if repo && needs_disabled_redirect?
        rewritten_path_for_disabled_issues
      elsif repo && has_query_state_params?
        rewritten_path_for_query_state_params
      else
        rewritten_path_for_clean_url
      end
    end

    def has_query_state_params?
      # If we're paginating at *all*, bail and force a straight query.
      return false if params[:page].to_i > 1

      params.key?(:state) ||
        params.key?(:sort) ||
        params.key?(:direction) ||
        params.key?(:labels) ||
        (params[:q] && params.key?(:author)) ||  # for author and assignee, don't consider it clean
        (params[:q] && params.key?(:assignee))   # unless there is an actual query associated with it
    end

    def load_current_user_into_dashboard_params
      components = Search::Queries::IssueQuery.parse(params[:q] || "is:open is:#{pulls_only ? "pr" : "issue"}")

      if params[:created_by] && !params[:q] && !params[:user] && current_user
        components += [[:author, current_user.display_login]]
      end

      components += [[:assignee, current_user.display_login]] if params[:assigned]
      components += [[:mentions, current_user.display_login]] if params[:mentioned]
      components += [[:"review-requested", current_user.display_login]] if params[:review_requested]

      # It's possible to have a url like /issues?user=github&q=is%3Aopen+is%3Aissue,
      # where the user param is valid, but not explictly a part of the search string.
      # We want to avoid inserting the user component when we're paginating, otherwise
      # we'll end up with a bunch of user:github instances in the search string.
      unless components.detect { |param, _value| param == :user } || !params[:user]
        components += [[:user, params[:user]]]
      end

      @query = Search::Queries::IssueQuery.stringify(components)
    end

    def rewritten_path_for_query_state_params
      params = self.params

      components = Search::Queries::IssueQuery.parse(params[:q] || "")

      if state = params.delete(:state)
        components += [[:is, state]]
      end

      sort = params.delete(:sort)
      direction = params.delete(:direction)

      if sort || direction
        components += [[:sort, "#{sort || 'created'}-#{direction || 'desc'}"]]
      end

      if author = params.delete(:author)
        components += [[:author, author]]
      end

      if assignee = params.delete(:assignee)
        components += [[:assignee, assignee]]
      end

      if labels = params.delete(:labels)
        if labels.is_a?(String)
          labels.split(",").each do |label|
            components += [[:label, label]]
          end
        end
      end

      query = Search::Queries::IssueQuery.stringify(components)

      if params.delete(:pulls_only)
        pull_requests_path(repo.owner, repo, q: query, milestone: params[:milestone])
      else
        issues_path(repo.owner, repo, q: query, milestone: params[:milestone])
      end
    end

    # Do the parameters call for a clean URL?
    #
    # Returns a Boolean.
    def needs_clean_url_redirect?
      !!rewritten_path_for_clean_url
    end

    # Certain URLs we want to promote the usage of as clean URLs. They are:
    #
    #   /user/repo/(issues|pulls)/assigned/:login
    #   /user/repo/(issues|pulls)/created_by/:login
    #   /user/repo/(issues|pulls)/mentioned/:login
    #   /user/repo/pulls/review-requested/:login
    #   /user/repo/labels/:label_name
    #   /user/repo/milestones/:milestone_name
    #   /user/repo/pulls/:login
    #
    # This returns the String path that the redirect should be. It returns nil
    # if no redirect should happen.
    def rewritten_path_for_clean_url
      return @clean_url_path if @clean_url_path

      # Did the user request only pulls? type:pr, is:pr, etc.
      is_pr = components.assoc(:type).try(:second) == "pr" ||
              components.any? { |c| c.is_a?(Array) && c[0] == :is && c[1] == "pr" }

      # TODO: Compare router parsed params instead of path substrings
      if repo && current_path.downcase.start_with?("/#{repo.nwo.downcase}/issues") && is_pr
        url_parts = "?#{query.to_query(:q)}" if query
        return "/#{repo.nwo}/pulls#{url_parts}"
      end

      return if !clean_url?

      # Check if there's any sort of type information in the filters (type:pr, is:issue, etc)
      has_type = components.assoc(:type) ||
                 components.any? { |c| c.is_a?(Array) && c[0] == :is && %w(issue pr).include?(c[1]) }

      @clean_url_path = if (q = components.assoc(:assignee).try(:second)) && has_type
        username = sanitize_user(q)
        if has_issues && !pulls_only && !is_pr
          gh_issues_assigned_path(repo, assignee: username)
        else
          gh_pulls_assigned_path(repo, assignee: username)
        end
      elsif (q = components.assoc(:author).try(:second)) && has_type && q&.length > 0
        username = sanitize_user(q)
        if has_issues && !is_pr
          gh_issues_created_by_path(repo, creator: username)
        else
          gh_user_pull_requests_path(repo, login: username)
        end
      elsif (q = components.assoc(:mentions).try(:second)) && has_type
        username = sanitize_user(q)
        if has_issues && !is_pr
          gh_issues_mentioned_path(repo, mentioned: username)
        else
          gh_pulls_mentioned_path(repo, mentioned: username)
        end
      elsif (q = components.assoc(:"review-requested").try(:second)) && is_pr
        gh_pulls_review_requested_path(repo, review_requested: q)
      elsif (q = components.assoc(:label).try(:second)) && !has_type && repo
        gh_label_path(Label.new(name: q, repository: repo), repo)
      elsif (q = components.assoc(:milestone).try(:second)) && !has_type && repo
        milestone_query_path(repo.owner, repo, q)
      end
    end

    # Does the URL qualify as being a clean URL? There's a bunch of checks we
    # can do to verify.
    #
    # Returns a Boolean.
    def clean_url?
      # A query must be present.
      return false if params[:q].blank?

      # Clean URLs only happen on the first page of results.
      return false if params[:page].to_i > 1

      # Clean URLs don't have any fulltext search in them.
      return false if components.any? { |c| !c.is_a?(Array) }

      # Clean URLs only happen for open issues.
      return false unless components.any? { |c| c.is_a?(Array) && c[0] == :is && c[1] == "open" }

      return false if components.any? { |c| c.is_a?(Array) && c[0] == :is && c[1] == "queued" }

      clean_filters = [:is, :type, :state]
      if exclude_archived
        # Clean URLs only happen for non-archived issues.
        return false unless components.any? { |c| c.is_a?(Array) && c[0] == :archived && c[1] == "false" }
        clean_filters << :archived
      end

      # Clean URLs only happen for simplistic, non-default queries, as denoted
      # by number of filters used.
      unclean_filters = components.select { |c| c.is_a?(Array) }.map(&:first) - clean_filters
      return false if unclean_filters.length > 1

      # Clean URLs shouldn't happen on queries that use filter negation.
      any_negated = components.any? do |c|
        c.is_a?(Array) && c[2]
      end
      return false if any_negated

      # Clean URLs shouldn't happen for groups of labels, like `label:one,two,three`
      # in terms of components that'd look like [:label, ["one", "two", "three"]]
      any_enumerated = components.any? do |c|
        c.is_a?(Array) && c[1].is_a?(Array)
      end
      return false if any_enumerated

      # If it's a really small query it's bound to be too simplistic for a clean URL.
      return false if components.size < 2

      # We have no clean URLs for is:public is:private filters.
      return false if components.any? { |c| c.is_a?(Array) && c[0] == :is && %w(public private).include?(c[1]) }

      # Allow the dashboard to filter non-current or macro'd user authors.
      return false if !repo && components.any? do |c|
        c.is_a?(Array) &&
          %i[author assignee mentions review-requested].include?(c[0]) &&
          c[1] != current_user.try(:display_login)
      end

      # Looks like it's a clean URL after all.
      true
    end

    # Is this request in need of disabled issue redirection? In other words, are
    # we hitting an /issues URL when we should be on /pulls or
    # /labels/:label_name, etc?
    #
    # Returns a Boolean.
    def needs_disabled_redirect?
      !has_issues && !pulls_only && !rewrote_url
    end

    # The actual path we should redirect people to from /issues.
    #
    # Returns a String path.
    def rewritten_path_for_disabled_issues
      self.pulls_only = true

      if params[:q].blank? && !rewrote_url
        pull_requests_path(repo.owner, repo)
      else
        pull_requests_path(repo.owner, repo) + "?#{query.to_query(:q)}"
      end
    end

    # Internal: If we're using a clean URL, populate the query with the
    # reconstructed strings pulled from routes.
    #
    # Returns Array of components or nil if its not a clean url.
    def query_components_from_params(components, params)
      if params[:assignee].present?
        components + [[:assignee, params[:assignee]]]
      elsif params[:creator].present?
        components + [[:author, params[:creator]]]
      elsif params[:mentioned].present?
        components + [[:mentions, params[:mentioned]]]
      elsif params[:review_requested].present?
        components + [[:"review-requested", params[:review_requested]]]
      elsif params[:login].present?
        components + [[:author, params[:login]]]
      elsif params[:label_name].present?
        [[:is, "open"], [:label, params[:label_name]]]
      elsif params[:milestone_name].present?
        [[:is, "open"], [:milestone, params[:milestone_name]]]
      end
    end

    # Should the current state of the system force a `is:pr` filter on the query?
    #
    # Returns a Boolean.
    def force_pulls?
      pulls_only || (!repo.has_issues? && rewrote_url)
    end

    def sanitize_user(username)
      username.delete_prefix("/").delete_suffix("/") if username
    end

    def applied_dashboard_tab_filter_name
      if params[:created_by]
        "Created"
      elsif params[:assigned]
        "Assigned"
      elsif params[:mentioned]
        "Mentioned"
      elsif params[:review_requested]
        "Review requests"
      end
    end
  end
end
