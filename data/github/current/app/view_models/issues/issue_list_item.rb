# typed: true
# frozen_string_literal: true

module Issues
  class IssueListItem < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :issue,
      :repo,
      :draggable,
      :global,
      :hide_milestone,
      :drag_disabled_message,
      :show_drag_controls,
      :hide_checkbox,
      :hide_unread,
      :reference_location,
      :reaction_sort,
      :pulls_only

    def initialize(attributes)
      super
      prefill_pull_request
    end

    # The PR or the issue object for this item.
    def subject
      issue.pull_request? ? issue.pull_request : issue
    end

    def id
      parts = []
      parts << "issue_#{issue.number}"
      parts << issue.repository.name_with_display_owner.gsub("/", "_") if global
      parts.join("_")
    end

    def classes
      # FIXME: mt-0 is a hack for broken Box-row styles
      classes = ["Box-row Box-row--focus-gray p-0 mt-0 js-navigation-item js-issue-row"]

      if logged_in?
        classes << (issue.read_by_current_user || hide_unread? ? "" : "Box-row--unread")
      end

      classes << "js-draggable-issue sortable-button-item" if draggable?
      classes.join(" ")
    end

    # Set all the targets for this pull.
    #
    # Returns nothing.
    def prefill_pull_request
      if pull_request = issue.pull_request
        GitHub::PrefillAssociations.prefill_associations(pull_request, [:issue, :repository], available_records: [issue, issue.repository])
      end
    end

    # Public: Is the issue representing a pull request that's a draft?
    def draft?
      issue.pull_request? && issue.pull_request&.draft?
    end

    # Which type of icon should we display for this particular issue?
    #
    # Returns a String.
    def icon
      if issue.state == "locked"
        "lock"
      elsif issue.pull_request?
        pr_icon.octicon_name
      elsif issue.open?
        "issue-opened"
      elsif issue.state_reason_not_planned?
        Issue::StateReasonDependency::OCTICONS[:not_planned][:icon]
      else
        "issue-closed"
      end
    end

    def icon_class
      if issue.pull_request?
        "color-fg-#{pr_icon.primer_color}"
      elsif issue.closed? && issue.state_reason_not_planned?
        Issue::StateReasonDependency::OCTICONS[:not_planned][:class]
      else
        status
      end
    end

    def icon_tooltip
      if issue.pull_request?
        return pr_icon.label
      end

      parts = []
      parts << status.capitalize

      if issue.closed? && issue.state_reason_not_planned?
        parts << "as not planned"
      end

      parts << type_name
      parts.join(" ")
    end

    # The path to submit data to for an issues search. This exists to support
    # both of our use cases: from a repo page, or from the global issues search
    # page.
    #
    # Returns a String.
    def target_path(options = {})
      pulls_only = options.delete(:pulls_only)
      if repo
        if pulls_only
          urls.pull_requests_path(repo.owner, repo, options)
        else
          urls.issues_path(repo.owner, repo, options)
        end
      else
        if pulls_only
          urls.all_pulls_path(options)
        else
          urls.all_issues_path(options)
        end
      end
    end

    def type_filter
      if issue.pull_request?
        "pr"
      else
        "issue"
      end
    end

    def query_filter
      author = issue.safe_user
      display_login = author.is_a?(Bot) ? author.to_query_filter : author.display_login

      if issue.open?
        "is:#{type_filter} is:open author:#{display_login}"
      else
        "is:#{type_filter} author:#{display_login}"
      end
    end

    def type_name
      if issue.pull_request?
        "pull request"
      else
        "issue"
      end
    end

    def status
      if issue.pull_request? && issue.pull_request.merged?
        "merged"
      else
        issue.open? ? "open" : "closed"
      end
    end

    # Does this item have a task list associated with it?
    #
    # Returns a Boolean.
    def task_list?
      subject.has_task_list?
    end

    def comment_count
      @comment_count ||= if issue.pull_request?
        issue.pull_request.total_comments
      else
        issue.issue_comments_count
      end
    end

    def any_comments?
      !comment_count.zero?
    end

    def reaction_count
      return 0 unless reaction_sort
      issue.prelude_reaction_count_for_reaction(reaction_sort)
    end

    def any_reactions?
      !reaction_count.zero?
    end

    def emotion
      return unless reaction_sort
      Emotion.find(reaction_sort)
    end

    def linked_xrefs_count
      issue.close_issue_references_count
    end

    def any_linked_xrefs?
      !linked_xrefs_count.zero?
    end

    def xref_octicon
      @xref_octicon ||= issue.pull_request? ? "issue-opened" : "git-pull-request"
    end

    def xref_subject
      @xref_subject ||= issue.pull_request? ? "issue" : "pull request"
    end

    def draggable?
      draggable
    end

    # We might show the controls but still not allow dragging
    def show_drag_controls?
      show_drag_controls
    end

    def hide_milestone?
      hide_milestone
    end

    def hide_checkbox?
      hide_checkbox
    end

    def hide_unread?
      hide_unread
    end

    def assignees_tooltip
      issue.assignees.reverse.map { |assignee| assignee.try(:source_login) || assignee.display_login }.to_sentence
    end

    private

    def pr_icon
      return @pull_request_icon if defined?(@pull_request_icon)
      @pull_request_icon = PullRequest::Icon.new(
        issue.pull_request,
        permit_queued_icon: true,
      )
    end
  end
end
