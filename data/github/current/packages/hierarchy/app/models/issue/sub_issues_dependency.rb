# typed: strict
# frozen_string_literal: true

module Issue::SubIssuesDependency
  extend T::Helpers

  requires_ancestor { Issue }

  # Ensures that a user can create a sub-issue for the current issue
  #
  # (abstracted to it's own issue for the time being, as we may evolve past simply checking if a user can update to
  # more granular permissions in the future)
  sig { params(actor: User).returns(T::Boolean) }
  def viewer_can_create_sub_issues?(actor)
    T.bind(self, Issue)
    self.triageable_by?(actor)
  end

  # Adds a sub issue to the current issue, prioritizing it at the given position.
  sig { params(sub_issue: Issue, actor_id: Integer, position: T.nilable(Symbol)).returns(SubIssue) }
  def add_sub_issue!(sub_issue, actor_id, position: :bottom)
    relationship = SubIssue.build(
       source_issue_id: self.id,
       source_repository_id: self.repository_id,
       target: sub_issue,
       actor_id:
    )

    self.prioritize_dependent!(relationship, position:)
    # priortize_dependent swallows any validation errors, so if the priority wasn't set, we know there are validation
    # errors in the mix which we can raise without attempting to save and re-validating
    if relationship.priority.present?
      relationship.save
    else
      relationship.errors.delete(:priority)
    end

    relationship
  end

  sig { params(sub_issue: Issue).void }
  def remove_sub_issue!(sub_issue)
    SubIssue.find_by(
       source_issue_id: self.id,
       source_repository_id: self.repository_id,
       target_issue_id: sub_issue.id,
    )&.destroy!
  end

  # Adds or replaces a sub issue's parent with the provided issue.
  sig { params(new_parent_issue: Issue, actor: User).returns(SubIssue) }
  def add_or_replace_parent!(new_parent_issue, actor)
    T.bind(self, Issue)

    original_parent = self.parent # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    self.class.transaction do
      # To avoid scenarios where we are updating SubIssue's priority within a transaction,
      # we manually set the priority. This is done to stay compliant with the guidance in GitHub::Prioritizable.
      # Because, GitHub::Prioritizable defaults to sorting in `desc` order,
      # we substract the gap size from the current minimum to force to bottom.
      priority = if new_parent_issue.sub_issue_relations.present?
        new_parent_issue.sub_issue_relations.minimum(:priority) - GitHub::Prioritizable::GAP_SIZE
      else
        GitHub::Prioritizable::START_VALUE
      end

      relationship = SubIssue.build(
        source_issue_id: new_parent_issue.id,
        source_repository_id: new_parent_issue.repository_id,
        target: self,
        actor_id: actor.id,
        priority: priority,
        skip_only_one_parent_validation: true
      )

      # Run validations before the original parent is removed so that we can detect duplicate sub-issues
      unless relationship.valid?
        next relationship
      end

      if original_parent.present?
        original_parent.remove_sub_issue!(self)

        maybe_log_sub_issue_removal(original_parent, actor)
      end

      relationship.save
      relationship
    end
  end

  # Loads the parent issue (if it exists) asynchronously, taking into account whether the issue can be
  # accessed or not, based on the conditional access filter passed in.
  sig { params(viewer: T.nilable(User), cap_filter: T.any(ConditionalAccess::Web::Filter, ConditionalAccess::Api::Public::Filter)).returns(T.nilable(Promise[T.nilable(Issue)])) }
  def async_filtered_parent(viewer:, cap_filter:)
    self.async_parent.then do |parent|
      next unless (authorized_parent = cap_filter.authorized_resources(parent).first)
      Promise.all([authorized_parent.async_hide_from_user?(viewer), authorized_parent.async_readable_by?(viewer)]).then do |hidden, readable|
        authorized_parent if !hidden && readable
      end
    end
  end

  # Loads all sub issue relations for the current issue which a user has access to and shouldn't be hidden.
  sig { params(viewer: T.nilable(User), cap_filter: T.any(ConditionalAccess::Web::Filter, ConditionalAccess::Api::Public::Filter)).returns(Promise[T::Array[Issue]]) }
  def async_filtered_prioritized_sub_issues(viewer:, cap_filter:)
    # Loading repository and owner async so that we can check feature-flag enablement
    self.async_repository.then do |repository|
      T.must(repository).async_owner.then do |_owner|
        return Promise.resolve(T.let([], T::Array[Issue])) unless SubIssuesFeature.enabled?(repository)

        self.async_sub_issue_relations.then do |sub_issue_relations|
          Promise.all(sub_issue_relations.map(&:async_target)).then(&:compact)
        end.then do |sub_issues|
          authorized_sub_issues = cap_filter.authorized_resources(sub_issues)
          Promise.all(
            authorized_sub_issues.map do |issue|
              Promise.all([issue.async_hide_from_user?(viewer), issue.async_readable_by?(viewer)]).then do |hidden, readable|
                issue if !hidden && readable
              end
            end
          ).then(&:compact)
        end
      end
    end
  end

  sig { returns(T.nilable(SubIssueList)) }
  def recalculate_sub_issue_list!
    return sub_issue_list&.recalculate! if sub_issue_list

    SubIssueList.find_or_initialize_by(issue: self).recalculate!
  end

  # Loads the completion rate from the denormalized sub_issue_list if available, and calculate otherwise.
  #
  # If calculate is true, then we calculate the sub-issue summary based on the current sub-issue state as opposed to
  # relying on the denormalized sub-issue-list
  sig { params(calculate: T::Boolean).returns(Promise[{ total: Integer, completed: Integer, percent_completed: Integer }]) }
  def async_sub_issues_summary(calculate: false)
    return async_calculated_sub_issues_summary if calculate
    T.let(self.async_sub_issue_list, Promise[T.nilable(SubIssueList)]).then do |sub_issue_list|
      # return an empty summary unless there is a list to calculate from
      if sub_issue_list
        sub_issue_list.to_h
      else
        { total: 0, completed: 0, percent_completed: 0 }
      end
    end
  end

  sig { returns(Promise[{ total: Integer, completed: Integer, percent_completed: Integer }]) }
  private def async_calculated_sub_issues_summary
    T.let(self.async_sub_issues, Promise[T::Array[Issue]]).then do |sub_issues|
      total = sub_issues.count
      completed = sub_issues.count { |sub_issue| sub_issue.closed? }
      {
        total: total,
        completed: completed,
        percent_completed: total.nonzero? ? (completed.to_f / total.to_f * 100).to_i : 0
      }
    end
  end

  # To add a sub-issue, we ensure that the user has write access to both the child issue and the parent issue. When
  # replacing the parent, we ignore read/write permissions to the parent being replaced. This can end up with
  # users unwittingly taking a "destroy" action on the SubIssue entity that they did not know existed. To determine
  # the impact of that action through the API, we keep metrics on the occurance of this situation.
  sig { params(replaced_parent: Issue, user: User).void }
  private def maybe_log_sub_issue_removal(replaced_parent, user)
    cannot_update_reasons = replaced_parent.async_viewer_cannot_update_reasons(user).sync
    return if cannot_update_reasons.empty?

    repo = replaced_parent.repository
    return unless repo

    viewer_can_read = repo.visible_and_readable_by?(user)
    GitHub.logger.info("User replaced sub-issue parent without some permissions to replaced parent",
      "code.function" => "maybe_log_sub_issue_removal",
      "graphql.operation" => "AddSubIssue",
      "gh.org.id" => repo.organization&.id,
      "gh.repo.id" => repo.id,
      "gh.user.id" => user.id,
      "gh.issue.authorization.cannot_update_reasons" => cannot_update_reasons,
      "gh.issue.authorization.viewer_can_read" => viewer_can_read,
    )
  end
end
