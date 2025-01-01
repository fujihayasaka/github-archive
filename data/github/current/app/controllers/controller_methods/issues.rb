# typed: true
# frozen_string_literal: true

module ControllerMethods
  module Issues
    extend T::Helpers
    extend ActiveSupport::Concern
    include ResilienceHelper

    requires_ancestor { AbstractRepositoryController }

    SHOW_ACTION_NAMES = [:show, :issue_layout, :issue_conversation_content, :issue_conversation_sidebar].freeze

    included do
      T.bind(self, T.class_of(AbstractRepositoryController))
      helper_method :current_issue
      helper_method :discussion_from_issue_transfer
      helper_method :handle_issue_transfer_deletion_or_conversion
      helper_method :issue_transfer_from_current_repository
      helper_method :track_execution_time
      helper_method :use_strict_loading
      helper_method :render_not_found?
      helper_method :set_headers_and_hovercard_subject
    end

    def render_not_found?(issue)
      if !issue || issue.hide_from_user?(current_user) || !issue.readable_by?(current_user)
        return true
      end

      if issue.pull_request_id && !issue.pull_request
        return true
      end

      false
    end

    def issue_required
      if current_issue.nil?
        render_404
      end
    end

    def set_headers_and_hovercard_subject(issue)
      track_execution_time("set_hovercard_subject") do
        set_hovercard_subject(issue)
      end

      request.format = :html if request.format.blank? || request.format.nil?

      add_headers_to_vary(["Accept"])

      request.env["issue.record_id"] = issue.id
    end

    def set_rails_tag
      # we need to track requests to this controller that don't use react to compare to requests that do
      T.must(request).env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "rails"
    end

    def set_react_tag
      T.must(request).env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "html"
    end

    def current_issue
      return @current_issue if defined?(@current_issue)

      # if there is no `id` set from the route, then we can't load the issue.
      issue_number = params[:id].to_i
      return @current_issue = nil if issue_number.zero?

      load_participants = should_load_participants?

      track_execution_time("current_issue") do
        issues = use_strict_loading ? current_repository.issues.strict_loading : current_repository.issues
        includes = if use_strict_loading
          [
            :labels,
            :milestone,
            :pinned_issue,
            pull_request: [:user],
          ]
        else
          [:labels]
        end
        ActiveRecord::Base.connected_to(role: :reading) do
          @current_issue = issues.includes(*includes).find_by_number(issue_number).tap do |issue|
            # Loads the participant data if it hasn't been loaded already. We load max of {Issue::VIEW_PARTICIPANT_LOAD_LIMIT},
            # since we limit the number of user profiles that are displayed on the show page and don't need to load them all into memory.
            # reverting the issue: https://github.com/github/github/pull/158345
            if load_participants
              with_database_error_fallback do
                GitHub.dogstats.time("issue.participants", tags: %W[logged_in:#{logged_in?}]) do
                  issue&.participants(user_limit: Issue::VIEW_PARTICIPANT_LOAD_LIMIT)
                end
              end
            end
          end
        end
      end
    end
    alias :timeline_owner :current_issue

    def track_execution_time(method)
      is_empty_issue = !!@current_issue && !@current_issue.has_timeline_items?
      tags = ["#{GitHub::TaggingHelper::EMPTY_ISSUE_TAG}:#{is_empty_issue}", "method:#{method}"]

      track_time(tags: tags) do
        yield
      end
    end

    def use_strict_loading
      !action_name.nil? && SHOW_ACTION_NAMES.include?(action_name.to_sym)
    end

    def handle_issue_transfer_deletion_or_conversion
      return if current_issue

      if current_repository&.discussions_active? &&
        (discussion = Discussion.for_repository(current_repository).with_number(params[:id]).first)

        if discussion.converted_from_issue?
          flash[:notice] = "That issue was converted to a discussion."
        end
        redirect_to discussion_path(discussion)
      elsif deleted_issue = DeletedIssue.find_by(repository_id: current_repository.id, number: params[:id])
        render "issues/deleted", locals: {
          deleted_issue: deleted_issue,
          kql_query: "webevents | where repo_id == #{current_repository.id} | where action == \"issue.destroy\" | where data.number == #{deleted_issue.number}",
        }
      elsif issue_transfer = IssueTransfer.find_from(repository: current_repository, number: params[:id])
        transferred_issue = issue_transfer.new_issue
        new_repository = transferred_issue.repository
        if new_repository&.readable_by?(current_user) && !new_repository.hide_from_user?(current_user)
          flash[:notice] = "This issue was transferred here."
          redirect_to issue_path(transferred_issue)
        else
          render "issues/transfer_no_access"
        end
      elsif issue_transfer_from_current_repository.present?
        if discussion = discussion_from_issue_transfer(issue_transfer_from_current_repository)
          flash[:notice] =
            "Issue ##{params[:id]} from #{current_repository.name_with_display_owner} was converted to a discussion."
          redirect_to discussion_path(discussion)
        else
          render "issues/transfer_no_access", locals: { issue_deleted: true }
        end
      else
        render_404 and return
      end
    end

    def issue_transfer_from_current_repository
      if defined?(@_issue_transfer_from_current_repository)
        @_issue_transfer_from_current_repository
      else
        @_issue_transfer_from_current_repository = IssueTransfer
                                                     .find_by(old_repository_id: current_repository.id, old_issue_number: params[:id])
      end
    end

    def discussion_from_issue_transfer(issue_transfer)
      Discussion
        .for_repository(issue_transfer.new_repository)
        .find_by(issue_id: issue_transfer.new_issue_id)
    end

    def should_load_participants?
      # Loads participants only in the cases really needed.
      partial ||= params[:partial]
      (action_name.present? && SHOW_ACTION_NAMES.include?(action_name.to_sym)) ||
        (action_name == "show_partial" && partial == "issues/sidebar/assignees_menu_content")
    end

    def pulls_only? # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      return @_pulls_only if defined?(@_pulls_only)
      @_pulls_only = ActiveRecord::Type::Boolean.new.deserialize(params[:pulls_only])
    end

    def pulls_only=(value)
      @_pulls_only = value
    end

    def parsed_issues_query=(value)
      @parsed_issues_query = value
    end

    def parsed_issues_query # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      @parsed_issues_query ||= Search::Queries::IssueQuery.normalize(
        Search::Queries::IssueQuery.parse(params_or_default_query_string, current_user)
      )
    end

    def params_or_default_query_string
      params[:q] || "is:#{pulls_only? ? :pr : :issue} is:open "
    end

    def query_string_includes_pr?
      params[:q] && [:type, :is].include?(parsed_issues_query.rassoc("pr").try(:first))
    end

    def query_parsed_search_tags
      search_tags = default_search_tags

      # is default query: query run on the /pulls or /issues page without any additional interaction
      is_default_query = false

      # when includes :assignee for the current user of @me
      is_self_assigned = false

      # when includes :author for the current user of @me
      is_self_authored = false

      # when is a exclusive issue search
      issues_only = false

      unless parsed_issues_query.nil?
        is_issue_search = parsed_issues_query.include?([:is, "issue"])
        is_pr_search = parsed_issues_query.include?([:is, "pr"])
        is_default_query = ::Search::Queries::IssueQuery.is_default_issues_index_query?(parsed_issues_query)

        issues_only = is_issue_search && !is_pr_search

        if logged_in?
          is_self_assigned = parsed_issues_query.include?([:assignee, T.must(current_user).display_login]) || parsed_issues_query.include?([:assignee, "@me"])
          is_self_authored = parsed_issues_query.include?([:author, T.must(current_user).display_login]) || parsed_issues_query.include?([:author, "@me"])
        end
      end

      # parsed_issues_query is currently an array of pairs, or a flat search query text.
      # We want to extract the filter symbols used.
      parsed_query_keys = []
      parsed_issues_query.each do |item|
        if item.is_a?(Array) && item.length == 2
          parsed_query_keys.append(item.first)
        end
      end

      IssuesController::ISSUES_INDEX_TAG_FILTER_SYMBOLS.each do |filter|
        filter_s = filter.to_s

        has_filter = parsed_issues_query.include?([:no, filter_s]) ||
          parsed_query_keys.include?(filter) ||
          parsed_issues_query.include?([:is, filter_s])

        search_tags.append("has_#{filter_s}_filter:#{has_filter}")
      end

      tags = %W[force_pulls:#{pulls_only?} force_issues:#{issues_only} is_default_query:#{is_default_query} is_self_assigned:#{is_self_assigned} is_self_authored:#{is_self_authored}]
      search_tags.concat(tags)
      search_tags
    end

    def default_search_tags
      %W[controller:#{controller_name} action:#{action_name} spammy:#{current_user&.spammy?} has_issues:#{current_repository&.has_issues?} logged_in:#{logged_in?}]
    end
  end
end
