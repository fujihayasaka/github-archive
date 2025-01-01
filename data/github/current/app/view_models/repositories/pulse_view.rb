# typed: false
# frozen_string_literal: true

module Repositories
  class PulseView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include UrlHelpers
    include UrlHelper
    include ActionView::Helpers::TagHelper
    include EscapeHelper

    attr_reader :period, :summary, :repository, :viewer

    def initialize(repository, period = nil, viewer = nil)
      @repository = repository
      @viewer     = viewer
      @period     = period_for(period)
      @summary    = repository.activity_summary(viewer: viewer, period: period)
    end

    def pulse_periods
      {
        daily: "24 hours",
        halfweekly: "3 days",
        weekly: "1 week",
        monthly: "1 month",
      }
    end

    def human_period
      pulse_periods[period]
    end

    def default_period
      :weekly
    end

    def show_diffstat_summary?
      summary.has_default_branch_commits?
    end

    def total_pull_requests
      summary.merged_pulls.size + summary.new_pulls.size
    end

    def total_issues
      summary.new_issues.count + summary.closed_issues.count
    end

    def total_merged_pull_requests
      summary.merged_pulls.size
    end

    def total_new_pull_requests
      summary.new_pulls.size
    end

    def total_files_changed
      summary.diffstat[:files]
    end

    def total_additions
      summary.diffstat[:insertions]
    end

    def total_deletions
      summary.diffstat[:deletions]
    end

    def total_default_branch_commits
      summary.default_branch_commit_count
    end

    def formatted_pluralize(count, word)
      if count != 1
        word = word.pluralize
      end
      content_tag(:span, helpers.number_with_delimiter(count), class: "text-emphasized") + " " + word # rubocop:disable Rails/ViewModelHTML
    end

    def range_label
      safe_join([
        summary.since.strftime("%B %-d, %Y"),
        content_tag(:span, "–", class: "dash"), # rubocop:disable Rails/ViewModelHTML
        Date.today.strftime("%B %-d, %Y"),
      ], " ")
    end

    def has_have?(count)
      count == 1 ? "has" : "have"
    end

    def pull_requests_summary
      merged, open = summary.merged_pulls.size, summary.new_pulls.size
      link_to("#{merged} merged", merged_pull_requests_path) + " and " + link_to("#{open} new", new_pull_requests_path)
    end

    def issues_summary
      closed, open = summary.closed_issues.size, summary.new_issues.size
      link_to("#{closed} closed", repository_issues_path({ state: "closed" }, repository)) + " and " + link_to("#{open} new", repository_issues_path({ state: "open" }, repository))
    end

    def repository_commits_url
      commits_url("", "", repository)
    end

    def new_pull_requests_path
      repository_pull_requests_path({ state: "open", sort: "created", direction: "desc" }, repository)
    end

    def merged_pull_requests_path
      repository_pull_requests_path({ state: "closed", sort: "created", direction: "desc" }, repository)
    end

    def release_title(release)
      return unless release.name?
      release.name unless release.name == release.tag_name
    end

    private

    def period_for(period)
      return default_period if period.nil?
      period  = period.to_sym
      pulse_periods.has_key?(period) ? period : default_period
    end
  end
end
