# typed: true
# frozen_string_literal: true

module Issues
  class FormButtonsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include PlatformHelper

    attr_reader :issue, :current_user, :issue_node, :addl_btn_classes

    def initialize(**args)
      super(args)
      @issue = args[:issue]
      @current_user = args[:current_user]
      @addl_btn_classes = args[:addl_btn_classes] || []
      @closable = args[:closable]
    end

    def pull_request?
      return @is_pull_request if defined?(@is_pull_request)
      @is_pull_request = issue.pull_request?
    end

    def pull_request
      return @pull_request if defined?(@pull_request)
      @pull_request = if pull_request?
        issue.pull_request
      end
    end

    def show_close_button?
      !issue.closed? && @closable
    end

    def show_reopen_button?
      issue.closed?
    end

    def can_reopen?
      issue.reopenable_by?(current_user)
    end

    def cannot_reopen_with_reason?
      pull_request? &&
        issue.reopenable_by?(current_user, issue_only: true) &&
        not_reopenable_reason
    end

    def not_reopenable_reason
      return unless pull_request?
      return @reason if defined?(@reason)
      @reason = pull_request.not_reopenable_reason
    end

    def in_merge_queue?
      return @in_merge_queue if defined?(@in_merge_queue)

      @in_merge_queue = pull_request&.in_merge_queue?
    end

    def noun
      if pull_request?
        "pull request"
      else
        "issue"
      end
    end

    def btn_classes(custom_classes: [])
      classes = base_btn_classes + addl_btn_classes
      classes += custom_classes
      classes.join(" ")
    end

    def base_btn_classes
      classes = %w[btn js-quick-submit-alternative]
      classes.push("js-comment-and-button") if pull_request?
      classes
    end
  end
end
