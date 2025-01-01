# typed: true
# frozen_string_literal: true

class Issue
  module State
    extend T::Helpers
    include Scientist

    requires_ancestor { Issue }

    States = %w(open closed)

    def open?
      state == "open"
    end

    def closed?
      state == "closed"
    end

    def unplanned?
      state_reason_not_planned? || state_reason_duplicate?
    end

    def toggle(toggler = nil)
      open? ? close(toggler) : open(toggler)
    end

    def reopen!(opener = user, attributes = {})
      open(opener, attributes.merge(state_reason: :reopened))
    end

    # Reopen the issue.
    #
    #   opener     - The User who opened the issue. May be nil to disable
    #                creation of an open event
    #   attributes - Hash of optional attributes to update with `state`.
    #
    # Returns true when the issue is successfully opened
    # Returns false-y if the issue cannot be opened
    # Returns false-y if the issue is already open
    def open(opener = user, attributes = {})
      opener = opener.try(:bot) || opener

      return if open? unless attributes[:state_reason] != state_reason

      if pull_request? && !pull_request&.reopenable?
        pull_request&.set_not_reopenable_error
        return false
      end

      return if !reopenable_by?(opener)

      attributes[:state] = States[0]
      attributes[:state_reason] = pull_request? ? nil : attributes[:state_reason]
      undo_closed_as_duplicate(opener)

      return if !update(attributes)

      events.create(
          event: "reopened",
          actor: opener,
          state_reason: attributes[:state_reason]
      ) if opener
      pull_request&.reopened opener if pull_request?

      if milestone && milestone&.prioritizable?
        milestone&.prioritize_issue!(self)
      end

      # Update the checkbox status of issue in the parent issues' comment body
      if tracked_in_issues
        update_parent_issue_checklist
      end

      after_open(opener, attributes)
    end

    # Mark the issue as closed, possibly by a given user and commit.
    #
    #   closer       - The User who closed the issue.
    #   attributes   - Hash of optional attributes to update with `state`.
    #                  May contain a :commit hash containing :id and :repository
    #                  keys
    #                  May contain a :pr key
    #   create_event - A Boolean indicating if we should create an associated
    #                  closed issue event.
    #
    # Returns true when the issue is successfully closed
    # Returns false-y if the issue cannot be closed
    # Returns false-y if the issue is already closed unless state_reason is changing
    def close(closer = user, attributes: {}, create_event: true)
      attributes[:state_reason] = if pull_request?
        nil
      else
        # We store the `completed` state as `nil` in the database
        attributes[:state_reason] == "completed" ? nil : attributes[:state_reason]
      end

      if closed?
        if pull_request? && pull_request&.merged?
          report_to_failbot("already closed")
        end
        return unless attributes[:state_reason] != state_reason
      end

      attributes[:state] = States[1]

      # If this is a pull request and it is already merged then we should
      # close regardless of the result of closable_by? to avoid leaving
      # the pull request in a broken state
      return if !closable_by?(closer) && !pull_request&.merged?
      undo_closed_as_duplicate(closer)

      commit  = attributes.delete(:commit) || {}
      pr_id   = attributes.delete(:pr)
      duplicate_issue_id = attributes.delete(:duplicate_issue_id)

      # when triggered by an auto-close memex workflow, we use this to find the project
      performed_by_project_workflow_action_id = attributes.delete(:performed_by_project_workflow_action_id)
      closing_status_in_project = attributes.delete(:closing_status_in_project)

      return if commit[:id] && already_closed_by_commit?(commit[:id])

      updated = update(attributes)
      if !updated
        if pull_request? && pull_request&.merged?
          report_to_failbot("failed to update state", errors: errors.full_messages.join(", "))
        end
        return
      end

      closing_data = { state_reason: attributes[:state_reason] }

      if commit[:id]
        closing_data[:commit_id]         = commit[:id]
        closing_data[:commit_repository] = commit[:repository]
      elsif pr_id
        closing_data[:referencing_issue_id] = pr_id
      elsif performed_by_project_workflow_action_id
        closing_data[:performed_by_project_workflow_action_id] = performed_by_project_workflow_action_id
        closing_data[:column_name] = closing_status_in_project if closing_status_in_project # Project status that triggered the auto-close workflow
      end

      if duplicate_issue_id
        closing_data[:subject_id] = duplicate_issue_id
        closing_data[:subject_type] = "Issue"
        duplicate_issue = Issue.find_by(id: duplicate_issue_id)
        DuplicateIssue.find_or_build_for(issue: self, canonical_issue: duplicate_issue, is_duplicate: true, user: closer, touch: true).save! if duplicate_issue
        create_xref_duplicate_issue_event!(duplicate_issue_id, closer, true)
      end

      after_close(closer, closing_data, create_event: create_event)
      pull_request&.after_close(closer) if pull_request?

      # Update the checkbox status of issue in the parent issues' comment body
      if tracked_in_issues
        update_parent_issue_checklist
      end

      true
    end

    alias :close! :close

    # Internal: Handle any processing for after an Issue closes
    #
    #   closer - User who closed the issue, or nil to
    #            not create a closed event
    #   attributes - Extra data used to trace the closing to a source
    #                (either commit or PR)
    #   create_event - A Boolean indicating if we should create an associated
    #                  closed issue event.
    #
    # Returns true
    #  (none of these 'after close' events are really considered a failure)
    def after_close(closer, attributes, create_event: true)
      if closer && create_event
        ignore_duplicate_records do
          events.create!(
            attributes.merge(
              event: "closed",
              actor: closer,
            ),
          )
        end

        remove_instance_variable(:@closed_by) if instance_variable_defined?(:@closed_by)
      end
      if milestone
        milestone&.deprioritize_dependent(T.unsafe(self))
      end
      update_repo_community_profile(changed_labels: labels)

      true
    end

    def create_xref_duplicate_issue_event!(duplicate_issue_id, actor, is_duplicate)
      dupe_issue_repo_id = Issue.where(id: duplicate_issue_id).select(:repository_id).first&.repository_id
      return unless dupe_issue_repo_id
      ignore_duplicate_records do
        IssueEvent.create!(
          actor: actor,
          event: is_duplicate ? "marked_as_duplicate" : "unmarked_as_duplicate",
          issue_id: duplicate_issue_id,
          repository_id: dupe_issue_repo_id,
          subject_id: self.id,
          subject_type: Issue,
          state_reason: "duplicate"
        )
      end
    end

    def undo_closed_as_duplicate(closer)
      # if it was previously closed as duplicate, and now it is being closed again as completed or not planned,
      # we need to remove the duplicate issue
      if state_reason_was == "duplicate"
        closed_dupe_event = self.events.closes.order(created_at: :desc).where(issue_event_detail: { state_reason: "duplicate" }, repository_id: self.repository&.id).first
        return unless closed_dupe_event
        ref_issue = closed_dupe_event.issue_event_detail.subject_id
        return unless ref_issue
        DuplicateIssue.find_or_build_for(issue: self, canonical_issue: ref_issue, is_duplicate: false, user: closer).save!
        create_xref_duplicate_issue_event!(ref_issue, closer, false)
      end
    end

    def after_open(opener, attributes)
      update_repo_community_profile(changed_labels: labels)

      true
    end

    # Add a new comment to this issue and create issue events if the comment
    # marks the issue as a duplicate and tracking "marked_as_duplicate" events is
    # enabled. Create records within a transaction so that if one part fails we
    # roll back to the original issue state.
    #
    # commenter    - The User who is commenting
    # comment_body - A String of text
    # performed_via_integration - The Integration that created this comment, if any
    #
    # Returns the IssueComment object.
    def create_comment(commenter, comment_body, performed_via_integration: nil)
      comment = comments.build(body: comment_body)
      comment.user = commenter
      comment.repository = repository

      if performed_via_integration.present?
        comment.performed_via_integration = performed_via_integration
        duplicate_issue_events = []
      else
        duplicate_issue_events = build_duplicate_issue_events(commenter, comment.duplicate_issues)
      end

      transaction do
        comment.save!
        duplicate_issue_events.each(&:save!)
      end

      comment

    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => exception
      comment
    end

    # Add a new comment to this issue, create issue events if the comment marks
    # the issue as a duplicate and tracking "marked_as_duplicate" events is
    # enabled, and change the state to closed. Create records within a
    # transaction so that if one part fails we roll back to the original issue state.
    #
    # closer       - The User who is closing this issue
    # comment_body - A String of text
    #
    # Returns the newly created IssueComment object or nil.
    def comment_and_close(closer, comment_body, state_reason = nil)
      valid = T.let(true, T::Boolean)
      duplicate_issue_events = []

      unless comment_body.blank?
        comment = comments.build(body: comment_body)
        comment.user       = closer
        comment.repository = repository
        duplicate_issue_events = build_duplicate_issue_events(closer, comment.duplicate_issues)
      end

      transaction do
        close(closer, attributes: { state_reason: state_reason })
        valid = !!(comment && comment.save)
        duplicate_issue_events.each(&:save)
      end

      comment
    end

    # Add a new comment to this issue, create issue events if the comment marks
    # the issue as a duplicate if tracking "marked_as_duplicate" events is enabled,
    # and change the state to open. Create records within a transaction so that
    # if one part fails we roll back to the original issue state.
    #
    # opener       - The User who is opening this issue
    # comment_body - Comment body as a String
    #
    # Returns the newly created IssueComment object or nil.
    def comment_and_open(opener, comment_body)
      valid = T.let(true, T::Boolean)
      duplicate_issue_events = []

      unless comment_body.blank?
        comment = comments.build(body: comment_body)
        comment.user       = opener
        comment.repository = repository
        duplicate_issue_events = build_duplicate_issue_events(opener, comment.duplicate_issues)
      end

      transaction do
        open(opener, { state_reason: :reopened })
        valid &&= !!(comment && comment.save!)
        duplicate_issue_events.each(&:save)
      end

      comment
    end

    def async_closable_by?(other_user)
      return Promise.resolve(false) unless other_user
      async_repository.then do |repo|
        T.must(repo).async_owner.then do |_owner|
          async_user.then do |_user|
            Promise.all([async_pull_request, async_repository]).then do |pull, _repo|
              Platform::Loaders::Permissions::BatchAuthorize.load(
                action: pull ? :close_pull_request : :close_issue,
                actor: other_user,
                subject: pull ? pull : self,
              ).then do |decision|
                decision.allow?
              end
            end
          end

        end
      end
    end

    # Does user have permission to close this issue?
    #
    # Returns true when user opened the issue or has write access
    # to the repository
    def closable_by?(other_user)
      async_closable_by?(other_user).sync
    end

    def async_closed_by
      Platform::Loaders::ClosedIssueEvents.load(
        self.id,
        omit_event_detail: true,
        fields: [:actor_id, :issue_id],
        order: "DESC",
        limit: 1
      ).then do |issue_events|
        issue_events&.first&.async_actor
      end
    end

    # The user that closed the issue, or nil when that information is not
    # available.
    def closed_by
      return @closed_by if defined?(@closed_by)

      @closed_by = async_closed_by.sync
    end
    attr_writer :closed_by

    # Fallback on the ghost user when the closer has been deleted or the closing
    # event doesn't exist.
    # See User.ghost for more.
    #
    # Returns a User, or nil if the Issue is open.
    def safe_closed_by
      return nil if open?

      closed_event = events.reverse.find { |e| e.event == "closed" }

      closed_event.present? ? closed_event.safe_actor : User.ghost
    end

    # Did the given commit close this issue by way of a reference?
    #
    # commit - Commit
    #
    # Returns Boolean.
    def closed_by_commit?(commit)
      if commit && closing_event = events.closes.last
        closing_event.commit && closing_event.commit.oid == commit.oid
      end
    end

    # Does user have permissions to reopen this issue?
    #
    # Returns false if this issue is actually a PR and the PR isn't reopenable
    # (unless you pass a true issue_only value)
    #
    # Returns true when user last closed the issue or has write access
    # to the repository
    def reopenable_by?(actor, issue_only: false)
      async_reopenable_by?(actor, issue_only: issue_only).sync
    end

    def async_reopenable_by?(actor, issue_only: false)
      return Promise.resolve(false) unless actor.present?

      async_checkable_pull = issue_only ? Promise.resolve(nil) : async_pull_request
      async_checkable_pull.then do |pull|
        GitHub.dogstats.time("reopenable_by", tags: ["subject:#{pull.present? ? 'pull_request' : 'issue'}"]) do
          async_reopenable?(issue_only: issue_only).then do |is_reopenable|
            next false unless is_reopenable
            action  = pull.present? ? :reopen_pull_request : :reopen_issue
            subject = pull.present? ? pull : self

            Platform::Loaders::Permissions::BatchAuthorize.load(
              action: action,
              actor: actor,
              subject: subject,
            ).then(&:allow?)
          end
        end
      end
    end

    # Public: Indicates if this issue is able to be reopened. This will return false if this issue
    #         is actually a PR and the PR isn't reopenable (unless you pass a true issue_only value).
    #
    # issue_only - A Boolean indicating if we should only check if the issue is reopenable,
    #              or if we should also check if the pull request associated with it can
    #              be reopened.
    #
    # Returns a Promise<Boolean>
    def async_reopenable?(issue_only: false)
      return Promise.resolve(true) if issue_only
      async_pull_request.then do |pull|
        next true unless pull.present?
        pull.async_reopenable?
      end
    end

    # Storing times in PDT is _not_ ideal, but we need to keep things consistent.
    def set_state
      if self.state.to_s =~ /close/
        self.closed_at ||= Time.current
        self.state       = States[1]
      else
        self.closed_at = nil
        self.state     = States[0]
      end

      if repository&.feature_enabled?(:sync_issue_state_to_pull_request)
        if pull = pull_request
          if pull.new_record?
            pull.status = self.state
          elsif pull.status != self.state
            pull.update_column(:status, self.state)
          end
        end
      end
    end

    # Public: Returns a list including IssueEvent and DuplicateIssue records that are potentially
    # not persisted.
    #
    # user - the current user, a User instance
    # referenced_issues - a list of Issue instances; the user should have indicated this issue was a
    #                     duplicate of these issues
    #
    # Returns an array.
    def build_duplicate_issue_events(user, referenced_issues)
      return [] unless self.can_mark_as_duplicate?(user)

      related_dupes = DuplicateIssue.marked_as_duplicate.with_duplicate_issue(id).
        with_canonical_issue(referenced_issues).to_a
      eligible_issues = referenced_issues.reject do |canonical_issue|
        marked_as_duplicate_of?(canonical_issue, duplicate_issues: related_dupes)
      end

      eligible_issues.flat_map do |canonical_issue|
        event = events.marked_as_duplicates.
          build(actor_id: user.id, repository_id: repository_id, subject_type: self.class.name,
                subject_id: canonical_issue.id)

        dupe_issue = DuplicateIssue.find_or_build_for(issue: self, canonical_issue: canonical_issue,
                                         user: user)

        [event, dupe_issue]
      end
    end

    # Public: Returns true if this Issue is marked as a duplicate of the given Issue.
    #
    # other_issue - an Issue instance
    # duplicate_issues - an optional list of DuplicateIssue records that can be passed for
    #                    performance reasons, to be checked instead of querying the database
    #
    # Returns a Boolean.
    def marked_as_duplicate_of?(other_issue, duplicate_issues: nil)
      if duplicate_issues
        dupe_issue = duplicate_issues.
          detect { |dupe| dupe.issue_id == id && dupe.canonical_issue == other_issue }
        dupe_issue.present?
      else
        DuplicateIssue.marked_as_duplicate.exists?(issue_id: id, canonical_issue_id: other_issue)
      end
    end

    private


    # Private: Report to Failbot when the #close method is called on a merged
    # pull request and returns without closing the issue.
    #
    # This was added to investigate cases in which a pull request is merged and
    # not subsequently closed.
    #
    # TODO: remove once we've determined the cause of the bug.
    #
    def report_to_failbot(message, errors: nil)
      boom = PullRequest::PRMergedAndNotClosed.new(message)
      boom.set_backtrace(caller)
      Failbot.push_sensitive("gh.pull_request.errors": errors) if errors
      Failbot.report(boom, "gh.pull_request.id": pull_request&.id, app: "github-pull-requests")
    end

    def update_parent_issue_checklist
      SyncIssueParentChecklistJob.perform_later(self)
    end
  end
end
