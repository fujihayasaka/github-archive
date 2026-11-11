# typed: true
# frozen_string_literal: true

module RepositoryAdvisories
  class PullRequestView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :pull_request

    delegate :issue,
             :title,
             :number,
             :author,
             :created_at,
             :merged_at,
             :open?,
             :merged?,
             :draft?,
             :total_comments,
             to: :pull_request

    delegate :safe_user, :assignees, to: :issue

    def status_icon_classes
      %W(d-inline-block float-left ml-n4 tooltipped tooltipped-e color-fg-#{pull_request_icon.primer_color})
    end

    def status_icon
      pull_request_icon.octicon_name
    end

    def status_tooltip
      pull_request_icon.label
    end

    def no_comments?
      total_comments.zero?
    end

    private

    def pull_request_icon
      @pull_request_icon ||= PullRequest::Icon.new(
        pull_request,
        permit_queued_icon: false, # TODO: Remove this after resolving N+1 issues
      )
    end
  end
end
