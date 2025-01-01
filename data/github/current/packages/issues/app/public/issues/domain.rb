# typed: strict
# frozen_string_literal: true

module Issues
  class Domain < GH::Domain::Base
    accessor Issues::Domain::IssueTypes
    accessor Issues::Domain::Labels

    # Find an issue by its number for a given repository. Returns nil no issue is found.
    sig { params(number: Integer, repo_id: Integer).returns(T.nilable(IIssue)) }
    def by_number(number, repo_id:)
      ::Issue.find_by(repository_id: repo_id, number: number)
    end

    # Returns a hash of open issue and pull request counts for a list of repository ids.
    sig { params(repository_ids: T::Array[Integer], return_nil_on_failure: T::Boolean).returns(T.nilable(T::Hash[[Integer, T::Boolean], Integer])) }
    def open_issue_and_pr_counts(repository_ids:, return_nil_on_failure: false)
      begin
        ::Issue.where(state: :open, repository_id: repository_ids, user_hidden: false)
          .group(:repository_id, :has_pull_request)
          .count
      rescue ActiveRecord::ActiveRecordError => error
        return nil if return_nil_on_failure
        raise error
      end
    end

    # Creates an issue with the given attributes. Returns a result object with the created issue if successful.
    sig do
      params(issue_attributes: CreateIssueAttributes, actor: User, integration: T.untyped)
        .returns(GH::Result[IIssue]).checked(:always).on_failure(:raise)
    end
    def create(issue_attributes, actor, integration: nil)
      issue = Issue.new(
        repository: issue_attributes.repository,
        title: issue_attributes.title,
        body: issue_attributes.body,
        user: actor,
        issue_type: issue_attributes.issue_type,
        labels: issue_attributes.labels,
        milestone: issue_attributes.milestone,
        assignees: issue_attributes.assignees,
        performed_via_integration: integration,
        modifying_integration: integration,
        skip_create_issue_orchestration: true
      )

      create_issue_orchestration = T.let(nil, T.nilable(CreateIssueOrchestration))

      valid = begin
        IssueOrchestration.transaction do
          next false unless issue.save

          # Create orchestration within the same transaction for consistency (outbox pattern)
          create_issue_orchestration = IssueOrchestration.create_issue!(actor: actor, issue: issue, uses_domain: true)
          true
        end
      rescue GitHub::Prioritizable::Context::LockedForRebalance
        return GH::Result::Error::LockedForRebalance.new("Milestone is temporarily locked for maintenance.")
      end

      if !valid
        return GH::Result::Error::Validation.new(issue, message: issue.errors.full_messages.join(", "))
      end

      # Execute orchestration outside of the transation to avoid long-running transactions and lock contention
      create_issue_orchestration.execute! if create_issue_orchestration

      GH::Result::Ok.new(issue)
    end

    # Updates an issue with the given attributes. Returns a result object with the updated issue if successful.
    sig do
      params(issue: Issue, issue_attributes: UpdateIssueAttributes, actor: User)
        .returns(GH::Result[IIssue]).checked(:always).on_failure(:raise)
    end
    def update(issue, issue_attributes, actor)
      # Skip automatic orchestration runs and hydro instrumentation for individual changes
      # since we want to batch them for all updates done in this method.
      issue.skip_update_issue_orchestration = true
      issue.skip_hydro_update_event_instrumentation = true
      previous_title = issue.title
      previous_body = issue.body

      update_issue_orchestration = T.let(nil, T.nilable(UpdateIssueOrchestration))

      valid = IssueOrchestration.transaction do
        case title = issue_attributes.title
        when Issues::UpdateOptions::Keep
          # Do nothing
        else
          next false unless issue.update(title: title)
        end

        case body = issue_attributes.body
        when Issues::UpdateOptions::Keep
          # Do nothing
        when Issues::UpdateOptions::Delete
          next false unless issue.update_body(nil, actor)
        else
          next false unless issue.update_body(body, actor)
        end

        update_issue_orchestration = IssueOrchestration.update_issue!(actor: actor, issue: issue, uses_domain: true)
        true
      end

      if !valid
        return GH::Result::Error::Validation.new(issue, message: issue.errors.full_messages.join(", "))
      end

      update_issue_orchestration.execute! if update_issue_orchestration

      issue.instrument_hydro_update_event(
        previous_title: previous_title,
        previous_body: previous_body,
      )

      GH::Result::Ok.new(issue)
    end
  end
end
