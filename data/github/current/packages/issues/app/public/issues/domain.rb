# typed: strict
# frozen_string_literal: true

module Issues
  class Domain < GH::Domain::Base
    class CalledInsideTransaction < StandardError ; end

    accessor Issues::Domain::IssueTypes
    accessor Issues::Domain::IssueFields
    accessor Issues::Domain::Labels

    # Find an issue by its number for a given repository. Returns nil no issue is found.
    sig { params(number: Integer, repo_id: Integer).returns(T.nilable(IIssue)) }
    def by_number(number, repo_id:)
      # Use this method to avoid an N+1 query when fetching issue events across multiple
      # issues; it can be used to retrieve all the issues associated with a list of
      # events (or any other object that has an issue reference).
      ::Issue.find_by(repository_id: repo_id, number: number)
    end

    # Find an issue by any args. Returns nil if no issue is found.
    # If you find yoursself needing to add more arguments, feel free to do so as long
    # as the argument is non-nullable in the databse
    # otherwise see the comment below 👇🏻
    sig { params(repo_id: Integer, title: T.nilable(String), number: T.nilable(Integer), state: T.nilable(Symbol)).returns(T.nilable(IIssue)) }
    def by_any(repo_id:, title: nil, number: nil, state: nil)
      # Using nillable arguments is not optimal because we cannot distinguish between
      # an explicitly nil value and an omitted argument, but because so far we only have non-nullable
      # columns and this way provides the best devx, we will use it for now.
      # If we need to support nullable columns in the future, we'll have to introduce a typed struct
      # I didn't use shapes (https://sorbet.org/docs/shapes) because they are still WIP and they don't work
      # with splatted hashes

      ::Issue.find_by(
        repository_id: repo_id,
        ** {
          title: title,
          number: number,
          state: state
        }.compact
      )
    end

    # Bulk retrieve issues by ID. Returns a hash of issue IDs to issue numbers within the repository.
    sig { params(repo_id: Integer, issue_ids: T::Array[Integer]).returns(T::Hash[Integer, Integer]) }
    def numbers_by_ids(repo_id, issue_ids)
      # This method exists to provide a way to retrieve multiple issues in a single query.
      # Use this to avoid an N+1 query pattern when fetching objects across issue boundaries
      # during bulk operations. An example is in exporting issue events.
      ::Issue.where(repository_id: repo_id, id: issue_ids)
        .pluck(:id, :number)
        .to_h
    end

    # Bulk retrieve whether issues are pull requests by ID.
    sig { params(issue_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Boolean]) }
    def is_pull_request_by_ids(issue_ids)
      # This method exists to provide a way to retrieve multiple issues in a single query.
      # Use this to avoid an N+1 query pattern when fetching objects across issue boundaries
      # during bulk operations. An example is in exporting issue events.
      #
      # If the ID is not in the output hash, it is not a pull request.
      ::Issue.where(id: issue_ids)
        .pluck(:id, :pull_request_id)
        .each_with_object({}) do |(id, pr_id), hash|
          hash[id] = pr_id.present?
        end
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
    # If parent_issue is provided, the issue will be created as a sub-issue of that parent.
    sig do
      params(
        issue_attributes: CreateIssueAttributes,
        actor: User,
        integration: T.untyped,
        skip_permission_checks: T::Boolean,
        raise_on_failed_permission: T::Boolean,
      ).returns(GH::Result[IIssue]).checked(:always).on_failure(:raise)
    end
    def create(issue_attributes, actor, integration: nil, skip_permission_checks: false, raise_on_failed_permission: true)
      validate_transaction_count

      issue = Issue.new(
        repository: issue_attributes.repository,
        title: issue_attributes.title,
        body: issue_attributes.body,
        user: actor,
        performed_via_integration: integration,
        modifying_integration: integration,
        body_template_name: issue_attributes.body_template_name,
        skip_create_issue_orchestration: true
      )

      # Check if we should raise errors on permission failures
      raise_on_permission_failure = FeatureFlag.vexi.enabled?(:issues_domain_create_raise_access_denied, issue_attributes.repository, default: false) && raise_on_failed_permission

      if issue_attributes.assignees.present?
        if skip_permission_checks || issue.assignable_by?(actor: actor)
          issue.assignees = T.cast(issue_attributes.assignees, T::Array[User])
        elsif raise_on_permission_failure
          return GH::Result::Error::AccessDenied.new("Access denied: insufficient permissions to assign users to issue")
        end
      end

      if issue_attributes.labels.present?
        if skip_permission_checks || issue.labelable_by?(actor: actor)
          issue.labels = T.cast(issue_attributes.labels, T::Array[Label])
        elsif raise_on_permission_failure
          return GH::Result::Error::AccessDenied.new("Access denied: insufficient permissions to add labels to issue")
        end
      end

      if issue_attributes.milestone != nil
        if skip_permission_checks || issue.can_set_milestone?(actor)
          issue.milestone = T.cast(issue_attributes.milestone, Milestone)
        elsif raise_on_permission_failure
          return GH::Result::Error::AccessDenied.new("Access denied: insufficient permissions to set milestone on issue")
        end
      end

      owner = T.cast(issue_attributes.repository.owner, User)
      if issue_attributes.issue_type != nil
        if skip_permission_checks || (issue.can_set_type?(actor: actor) && owner.issue_types_enabled?)
          issue.issue_type = T.cast(issue_attributes.issue_type, IssueType)
        elsif raise_on_permission_failure
          return GH::Result::Error::AccessDenied.new("Access denied: insufficient permissions to set issue type")
        end
      end

      create_issue_orchestration = T.let(nil, T.nilable(CreateIssueOrchestration))
      parent_issue_relationship = T.let(nil, T.nilable(SubIssue))

      saved = ActiveRecord::Base.connected_to(role: :writing) do
        IssueOrchestration.transaction do
          next false unless issue.save

          # If there's a parent issue, create the parent-child relationship in the same transaction
          if issue_attributes.parent_issue && parent_issue = T.cast(issue_attributes.parent_issue, Issue)
            parent_issue_relationship = parent_issue.add_sub_issue!(issue, actor.id)
            # If the relationship isn't persisted or has errors, roll back the transaction
            raise ActiveRecord::Rollback unless parent_issue_relationship.persisted?
          end

          if issue_attributes.issue_fields
            Issues.domain.issue_fields.create_issue_field_values(issue: issue, actor: actor, attributes: T.must(issue_attributes.issue_fields))
          end

          # Create orchestration within the same transaction for consistency (outbox pattern)
          create_issue_orchestration = IssueOrchestration.create_issue!(actor: actor, issue: issue, uses_domain: true)
          true
        end
      rescue GitHub::Prioritizable::Context::LockedForRebalance
        return GH::Result::Error::LockedForRebalance.new("Milestone or parent sub-issue list is temporarily locked for maintenance. Please try again.")
      rescue SubIssue::MaximumHeightError => e
        issue.errors.add(:base, e.message)
        return GH::Result::Error::Validation.new(issue, message: e.message)
      end

      # if the parent issue relationship creation fails, add the errors to the issue (which should have none, as its creation succeeded)
      if parent_issue_relationship && parent_issue_relationship.errors.any?
        parent_issue_relationship.errors.each do |error|
          issue.errors.add(:parent, error.type, **error.options)
        end
      end

      if issue.errors.any?
        return GH::Result::Error::Validation.new(issue, message: issue.errors.full_messages.to_sentence)
      end

      unless saved
        return GH::Result::Error::NotSaved.new
      end

      # Execute orchestration outside of the transaction to avoid long-running transactions and lock contention
      create_issue_orchestration.execute! if create_issue_orchestration

      GH::Result::Ok.new(issue)
    end

    # Updates an issue with the given attributes. Returns a result object with the updated issue if successful.
    sig do
      params(issue: Issue, issue_attributes: UpdateIssueAttributes, actor: User)
        .returns(GH::Result[IIssue]).checked(:always).on_failure(:raise)
    end
    def update(issue, issue_attributes, actor)
      validate_transaction_count

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

    private

    sig { void }
    def validate_transaction_count
      return unless ::Issue.current_transaction.open?

      if Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        Rails.logger.error("Issues.domain called inside an open transaction.")
      else
        raise CalledInsideTransaction.new("Issues.domain.create and Issues.domain.update cannot be called inside an open transaction.")
      end
    end
  end
end
