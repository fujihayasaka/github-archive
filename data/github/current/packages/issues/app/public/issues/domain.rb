# typed: strict
# frozen_string_literal: true

module Issues
  class Domain < GH::Domain::Base
    include GitHub::ResilienceMixin

    class CalledInsideTransaction < StandardError ; end

    accessor Issues::Domain::IssueTypes
    accessor Issues::Domain::IssueFields
    accessor Issues::Domain::Labels
    accessor Issues::Domain::Copilot
    accessor Issues::Domain::Triage
    accessor Issues::Domain::PlanningTemplates
    accessor Issues::Domain::Transfer
    accessor Issues::Domain::Comments
    accessor Issues::Domain::Suggestions
    accessor Issues::Domain::Reactions
    accessor Issues::Domain::SemanticSearch

    # Find an issue by its number for a given repository. Returns nil no issue is found.
    sig { params(number: Integer, repo_id: Integer).returns(GH::Result[IIssue]) }
    def by_number(number, repo_id:)
      # Use this method to avoid an N+1 query when fetching issue events across multiple
      # issues; it can be used to retrieve all the issues associated with a list of
      # events (or any other object that has an issue reference).
      if issue = ::Issue.find_by(repository_id: repo_id, number: number)
        GH::Result::Ok.new(issue)
      else
        GH::Result::Error::NotFound.new("Issue with number #{number} not found in repository with id #{repo_id}.")
      end
    end

    # Find an issue by any args. Returns nil if no issue is found.
    # If you find yoursself needing to add more arguments, feel free to do so as long
    # as the argument is non-nullable in the databse
    # otherwise see the comment below 👇🏻
    sig { params(repo_id: T.nilable(Integer), title: T.nilable(String), number: T.nilable(Integer), state: T.nilable(Symbol), id: T.nilable(Integer)).returns(T.nilable(IIssue)) }
    def by_any(repo_id: nil, title: nil, number: nil, state: nil, id: nil)
      # Using nillable arguments is not optimal because we cannot distinguish between
      # an explicitly nil value and an omitted argument, but because so far we only have non-nullable
      # columns and this way provides the best devx, we will use it for now.
      # If we need to support nullable columns in the future, we'll have to introduce a typed struct
      # I didn't use shapes (https://sorbet.org/docs/shapes) because they are still WIP and they don't work
      # with splatted hashes

      # If id is provided, look up by ID directly (MySQL primary key)
      return ::Issue.find_by(id: id) if id

      # Otherwise, require repo_id and use other filters
      return nil unless repo_id

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
      if FeatureFlag.vexi.enabled?(:open_issue_and_pr_count_caching, default: false)
        begin
          full_result = Issues::Cache::OpenIssueAndPullRequestCountClient.new(repository_ids).fetch_multi(graceful_degradation: false) do |missing_repository_ids|
            missing_result = ::Issue.where(state: :open, repository_id: missing_repository_ids, user_hidden: false)
              .group(:repository_id, :has_pull_request)
              .count

            missing_repository_ids.each_with_object({}) do |repo_id, hash|
              issue_count = missing_result[[repo_id, false]] || 0
              pr_count = missing_result[[repo_id, true]] || 0
              hash[repo_id] = [issue_count, pr_count]
            end
          end

          full_result.each_with_object({}) do |(repo_id, (issue_count, pr_count)), hash|
            hash[[repo_id, false]] = issue_count
            hash[[repo_id, true]] = pr_count
          end
        rescue ActiveRecord::ActiveRecordError => error
          return nil if return_nil_on_failure
          raise error
        end
      else
        begin
          ::Issue.where(state: :open, repository_id: repository_ids, user_hidden: false)
            .group(:repository_id, :has_pull_request)
            .count
        rescue ActiveRecord::ActiveRecordError => error
          return nil if return_nil_on_failure
          raise error
        end
      end
    end

    # This is a temporary method until we consolidate data access patterns for open issue and PR counts.
    # This method returns the same data as open_issue_and_pr_counts, but:
    #   - returns a hash keyed by repository id, with the value being the sum of open issues and PRs
    #     vs a hash keyed by [repository id, is_pull_request] tuples with integer values for counts
    sig { params(repository_ids: T::Array[Integer]).returns(T::Hash[Integer, Integer]) }
    def open_issues_and_prs_combined_counts_for_repos(repository_ids)
      if FeatureFlag.vexi.enabled?(:open_issues_count_batch_caching, default: false)
        counts = Issues::Cache::OpenIssueAndPullRequestCountClient.new(repository_ids).fetch_multi do |missing_repository_ids|
          missing_result = Issue.where(state: :open, repository_id: missing_repository_ids, user_hidden: false)
            .group(:repository_id, :has_pull_request)
            .count

          missing_repository_ids.each_with_object({}) do |repo_id, hash|
            issue_count = missing_result[[repo_id, false]] || 0
            pr_count = missing_result[[repo_id, true]] || 0
            hash[repo_id] = [issue_count, pr_count]
          end
        end

        repository_ids.index_with do |repo_id|
          counts[repo_id]&.sum.to_i
        end
      else
        Issue.open_issues.not_spammy.where(repository_id: repository_ids).group(:repository_id).except(:order).count
      end
    end

    # Returns a boolean indicating if the issue is assignable by the actor and (optionally) the viewer.
    sig do
      params(
        issue: Issue,
        actor: User,
        viewer: T.nilable(User)
      ).returns(T::Boolean)
    end
    def set_assignees?(issue, actor, viewer: nil)
      promises = T.let([], T::Array[Promise[T::Boolean]])
      promises << issue.async_assignable_by?(actor: actor)
      promises << issue.async_assignable_by?(actor: viewer) unless viewer.nil? || actor == viewer
      Promise.all(promises).sync.all?
    end

    # Returns a boolean indicating if the issue is labelable by the actor and (optionally) the viewer.
    sig do
      params(
        issue: Issue,
        actor: User,
        viewer: T.nilable(User)
      ).returns(T::Boolean)
    end
    def set_labels?(issue, actor, viewer: nil)
      promises = T.let([], T::Array[Promise[T::Boolean]])

      promises << issue.async_labelable_by?(actor: actor)
      promises << issue.async_labelable_by?(actor: viewer) unless viewer.nil? || actor == viewer

      Promise.all(promises).sync.all?
    end

    # Returns a boolean indicating if the issue is milestonable by the actor and (optionally) the viewer.
    sig do
      params(
        issue: Issue,
        actor: User,
        viewer: T.nilable(User)
      ).returns(T::Boolean)
    end
    def set_milestone?(issue, actor, viewer: nil)
      promises = T.let([], T::Array[Promise[T::Boolean]])

      promises << issue.async_can_set_milestone?(actor)
      promises << issue.async_can_set_milestone?(viewer) unless viewer.nil? || actor == viewer

      Promise.all(promises).sync.all?
    end

    # Find a transferred issue by its original MySQL ID.
    # Returns the new issue if the issue was transferred, nil otherwise.
    # This method handles transfer chains (issue transferred multiple times).
    sig { params(original_id: Integer).returns(T.nilable(IIssue)) }
    def transferred_by_id(original_id)
      # Use IssueTransfer to find the new issue ID
      new_issue_id = ::IssueTransfer.find_new_id_by_original_id(original_id: original_id)
      return nil unless new_issue_id

      # Return the new issue
      ::Issue.find_by(id: new_issue_id)
    end

    # Find a deleted issue by its original MySQL ID.
    # Returns a hash with deleted issue metadata if found, nil otherwise.
    # The hash contains: { repository:, number:, old_issue_id:, deleted_by: }
    sig { params(original_id: Integer).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def deleted_by_id(original_id)
      deleted_issue = ::DeletedIssue.find_by(old_issue_id: original_id)
      return nil unless deleted_issue

      {
        repository: deleted_issue.repository,
        number: deleted_issue.number,
        old_issue_id: deleted_issue.old_issue_id,
        deleted_by: deleted_issue.deleted_by
      }
    end

    # Find a transferred issue by repository and issue number.
    # Returns the new issue if the issue was transferred, nil otherwise.
    # This method handles transfer chains (issue transferred multiple times).
    sig { params(repository: Repository, number: Integer).returns(T.nilable(IIssue)) }
    def transferred_by_number(repository, number)
      # Use IssueTransfer to find the transfer
      transfer = ::IssueTransfer.find_from(repository: repository, number: number)
      return nil unless transfer

      # Return the new issue
      transfer.new_issue
    end

    # Find a deleted issue by repository and issue number.
    # Returns a hash with deleted issue metadata if found, nil otherwise.
    # The hash contains: { repository:, number:, old_issue_id:, deleted_by: }
    sig { params(repository: Repository, number: Integer).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def deleted_by_number(repository, number)
      deleted_issue = ::DeletedIssue.find_by(repository: repository, number: number)
      return nil unless deleted_issue

      {
        repository: deleted_issue.repository,
        number: deleted_issue.number,
        old_issue_id: deleted_issue.old_issue_id,
        deleted_by: deleted_issue.deleted_by
      }
    end

    # Returns a boolean indicating if the issue is typeable by the actor and (optionally) the viewer.
    sig do
      params(
        issue: Issue,
        actor: User,
        viewer: T.nilable(User)
      ).returns(T::Boolean)
    end
    def set_type?(issue, actor, viewer: nil)
      promises = T.let([], T::Array[Promise[T::Boolean]])

      promises << issue.async_can_set_type?(actor: actor)
      promises << issue.async_can_set_type?(actor: viewer) unless viewer.nil? || actor == viewer

      Promise.all(promises).sync.all?
    end

    # Creates an issue with the given attributes. Returns a result object with the created issue if successful.
    # If parent_issue is provided, the issue will be created as a sub-issue of that parent.
    sig do
      params(
        issue_attributes: CreateIssueAttributes,
        actor: User,
        viewer: T.nilable(User),
        integration: T.untyped,
        skip_permission_checks: T::Boolean,
        fail_on_invalid_assignees: T::Boolean,
        copilot_context: IssueOrchestration::CopilotContext
      ).returns(GH::Result[IIssue]).checked(:always).on_failure(:raise)
    end
    def create(issue_attributes, actor, viewer: nil, integration: nil, skip_permission_checks: false, fail_on_invalid_assignees: false, copilot_context: nil)
      validate_transaction_count

      issue = Issue.new(
        repository: issue_attributes.repository,
        title: issue_attributes.title,
        body: issue_attributes.body,
        user: viewer || actor,
        performed_via_integration: integration,
        modifying_integration: integration,
        body_template_name: issue_attributes.body_template_name,
        skip_create_issue_orchestration: true
      )

      issue.created_at = issue_attributes.created_at if issue_attributes.created_at

      repository = T.cast(issue_attributes.repository, Repository) # rubocop:todo GitHub/AvoidCast

      if !repository.has_issues?
        return GH::Result::Error::Gone.new("Issues has been disabled in this repository.")
      end

      if actor.blocked_by?(repository.owner_id) || (viewer.present? && viewer.blocked_by?(repository.owner_id))
        return GH::Result::Error::AccessDenied.new("Blocked")
      end

      authorization = Issues::ContentAuthorizer.new(actor, :create, repo: repository)
      if authorization.failed?
        return GH::Result::Error::ContentAuthorizationError.new(authorization)
      end

      if issue_attributes.parent_issue && parent_issue = T.cast(issue_attributes.parent_issue, Issue)
        unless parent_issue.viewer_can_create_sub_issues?(actor)
          return GH::Result::Error::Forbidden.new("You may not create a sub-issue for a parent issue with id '#{parent_issue.global_relay_id}'.")
        end
      end

      # use a temporary variable to avoid calling the `#assignees=` overridden assigner more than once
      assignees = []

      if issue_attributes.template_name
        if issue_template = repository.preferred_issue_templates(viewer).find_by_name(issue_attributes.template_name)
          assignees = issue_template.assignees
          issue.labels = only_labels_on_repository(repository, issue_template.labels)
          issue.issue_type_id = issue_types.by_organization_and_name(repository.owner&.id, issue_template.type)&.id if issue_template.type # TODO check if org?
          issue.body_template_name = issue_template.filename
        else
          return GH::Result::Error::NotFound.new("Could not find an issue template with name #{issue_attributes.template_name}")
        end
      end

      assignee_attribute = issue_attributes.assignee || issue_attributes.assignees

      if assignee_attribute && (skip_permission_checks || set_assignees?(issue, actor, viewer: viewer))
        assignees_to_set = Array.wrap(assignee_attribute)

        user = viewer || actor
        assignees = auto_assign_actor_with_agent(assignees: assignees_to_set, actor: user)
      end

      issue.assignees = assignees

      # If copilot_context was provided but no bot ended up assigned (e.g. because
      # set_assignees? returned false for an unprivileged viewer), discard it so the
      # agent pipeline is never triggered without a corresponding assignment.
      # This mirrors how the domain silently drops other metadata (labels, milestones)
      # when the viewer lacks permission, but ensures there are no side-effects from
      # the decoupled copilot_context parameter.
      if copilot_context.present? && issue.assignees.none? { |a| a.is_a?(Bot) }
        copilot_context = nil
      end

      if issue_attributes.labels && (skip_permission_checks || set_labels?(issue, actor, viewer: viewer))
        issue.labels = only_labels_on_repository(repository, T.cast(issue_attributes.labels, T::Array[Label]))
      end

      if issue_attributes.milestone && (skip_permission_checks || set_milestone?(issue, actor, viewer: viewer))
        issue.milestone = T.cast(issue_attributes.milestone, Milestone)
      end

      owner = T.cast(issue_attributes.repository.owner, User)
      if issue_attributes.issue_type && (skip_permission_checks || (set_type?(issue, actor, viewer: viewer) && owner.issue_types_enabled?))
        issue.issue_type = T.cast(issue_attributes.issue_type, IssueType)
      end

      if issue_attributes.issue_fields && org = T.cast(repository.owner, Organization)
        unless IssueFieldsFeature.enabled?(org, actor: actor)
          return GH::Result::Error::Forbidden.new("Issue fields are not enabled for you in this organization.")
        end

        fields_res = ::IssueFields::Builder.build_issue_field_values(issue: issue, actor: actor, attributes: T.must(issue_attributes.issue_fields))
        case fields_res
        when GH::Result::Ok
          issue.issue_field_values = fields_res.value
        when GH::Result::Error
          return GH::Result::Error::Validation.new(issue, message: fields_res.message)
        end
      end

      create_issue_orchestration = T.let(nil, T.nilable(CreateIssueOrchestration))
      parent_issue_relationship = T.let(nil, T.nilable(SubIssue))

      # The overridden `#assignees=` method on Issue (via AssignmentDependency) adds errors to the issue even before `#save` or `#valid?` are called.
      # Checking for errors at this points means just checking for assignee-related errors.
      # Before returning the error though, we need to refine the errors to make sure they associated with the correct attribute (`assignee` vs `assignees`).
      if fail_on_invalid_assignees
        refine_assignee_errors(issue, issue_attributes)
        if issue.errors.any?
          return GH::Result::Error::Validation.new(issue, message: issue.errors.full_messages.to_sentence)
        end
      end

      saved = ActiveRecord::Base.connected_to(role: :writing) do
        IssueOrchestration.transaction do
          next false unless issue.save

          # If there's a parent issue, create the parent-child relationship in the same transaction
          if parent_issue = T.cast(issue_attributes.parent_issue, T.nilable(Issue))
            parent_issue_relationship = parent_issue.add_sub_issue!(issue, (viewer || actor).id)
            # If the relationship isn't persisted or has errors, roll back the transaction
            raise ActiveRecord::Rollback unless parent_issue_relationship.persisted?
          end

          # Create orchestration within the same transaction for consistency (outbox pattern)
          create_issue_orchestration = IssueOrchestration.create_issue!(actor: actor, issue: issue, uses_domain: true, is_duplicated: !!issue_attributes.is_duplicated, copilot_context: copilot_context)
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
        if (rate_limit_error = issue.errors.where(:base, :rate_limited).first).present?
          return GH::Result::Error::ServiceRateLimited.new(rate_limit_error.message)
        else
          return GH::Result::Error::Validation.new(issue, message: issue.errors.full_messages.to_sentence)
        end
      end

      unless saved
        return GH::Result::Error::NotSaved.new
      end

      # Execute orchestration outside of the transaction to avoid long-running transactions and lock contention
      create_issue_orchestration.execute! if create_issue_orchestration

      GH::Result::Ok.new(issue)
    end

    sig do
      params(repository: Repository, labels: T::Array[Label])
        .returns(T::Array[Label]).checked(:always).on_failure(:raise)
    end
    private def only_labels_on_repository(repository, labels)
      Label.where(lowercase_name: labels.map { |l| l.name.downcase }, repository_id: repository.id).to_a
    end

    # Updates an issue with the given attributes. Returns a result object with the updated issue if successful.
    sig do
      params(issue: Issue, issue_attributes: UpdateIssueAttributes, actor: User, copilot_context: T.nilable(IssueOrchestration::CopilotContext))
        .returns(GH::Result[IIssue]).checked(:always).on_failure(:raise)
    end
    def update(issue, issue_attributes, actor, copilot_context: nil)
      validate_transaction_count

      # Skip automatic orchestration runs and hydro instrumentation for individual changes
      # since we want to batch them for all updates done in this method.
      issue.skip_update_issue_orchestration = true
      issue.skip_hydro_update_event_instrumentation = true

      previous_title = issue.title
      previous_body = issue.body
      previous_assignee_ids = issue.assignees.map(&:id)

      ar_attributes = {}
      issue_attributes.title.then { |v| ar_attributes[:title] = v }
      issue_attributes.milestone.then { |v| ar_attributes[:milestone] = v }
      issue_attributes.issue_type.then { |v| ar_attributes[:issue_type] = v }
      if set_assignees?(issue, actor)
        issue_attributes.assignees.then do |assignees|
          ar_attributes[:assignees] = auto_assign_actor_with_agent(assignees: assignees, actor: actor, current_assignees: issue.assignees.to_a)
        end
      end

      update_issue_orchestration = T.let(nil, T.nilable(UpdateIssueOrchestration))
      retries = 2
      valid = begin
        IssueOrchestration.transaction do
          if issue_attributes.issue_fields.any?
            raise ActiveRecord::Rollback unless update_issue_field_values(issue, issue_attributes.issue_fields, actor)
          end

          issue_attributes.state.then { |v| raise ActiveRecord::Rollback unless update_state(issue, v, actor) }

          # Set modifying_user so assignee blocking validation works correctly
          issue.modifying_user = actor
          raise ActiveRecord::Rollback unless issue.update(ar_attributes)
          issue_attributes.body.then { |v| raise ActiveRecord::Rollback unless issue.update_body(v, actor) }
          issue_attributes.labels.then { |v| raise ActiveRecord::Rollback unless issue.replace_labels(v) }

          update_issue_orchestration = IssueOrchestration.update_issue!(actor: actor, issue: issue, uses_domain: true, copilot_context: copilot_context)
          update_issue_orchestration.data[:previous_assignee_ids] = previous_assignee_ids
          true
        end
      rescue ActiveRecord::RecordNotUnique
        (retries -= 1) && retry if retries > 0

        # we can't handle this - fail
        return GH::Result::Error::ServiceUnreachable.new
      end

      if !valid
        return GH::Result::Error::Validation.new(issue, message: issue.errors.full_messages.join(", "))
      end

      # These updates are performed in background jobs so they need to be enqueued after the main transaction finishes
      issue_attributes.projects.then { |v| issue.replace_memex_projects(T.cast(v, T::Array[MemexProject]), issue, actor) }

      update_issue_orchestration.execute! if update_issue_orchestration

      issue.instrument_hydro_update_event(
        previous_title: previous_title,
        previous_body: previous_body,
        actor: actor
      )

      GH::Result::Ok.new(issue)
    end

    # Calls Issue#open, Issue#close, Issue#lock, or Issue#unlock when needed.
    # Returns true when no transition is needed or the transition succeeds.
    sig { params(issue: Issue, new_state: T.nilable(Issues::State), actor: User).returns(T::Boolean) }
    def update_state(issue, new_state, actor)
      return true if new_state.nil?
      return !!issue.close(actor) if new_state == Issues::State::Closed && issue.open?
      return !!issue.open(actor) if new_state == Issues::State::Open && issue.closed?
      return !!issue.lock(actor) if new_state == Issues::State::Locked && !issue.locked?
      return !!issue.unlock(actor) if new_state == Issues::State::Unlocked && issue.locked?

      true
    end

    # Cached version of repository#open_issue_count_for
    # TODO: remove #open_issue_count_for from Repository and implement the method here instead,
    # downgrading to non-AR arguments
    sig { params(repository: ::Repository, viewer: T.nilable(::User), cached: T::Boolean).returns(Integer) }
    def open_issue_count_for_repo(repository, viewer, cached: false)
      count = Issues::Cache::OpenIssueCountClient.new(repository, viewer).fetch(force_refresh: !cached) do
        repository.open_issue_count_for(viewer)
      end

      # if the count was fetched from cache, we need to set it on the repository
      repository.set_open_issue_count_for(viewer, count)
      count
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

    sig { params(issue: Issue, issue_fields: T::Array[T.any(IssueField::IssueFieldAttributesType, Issues::IssueFieldDeleteAttributes)], actor: User).returns(T::Boolean) }
    def update_issue_field_values(issue, issue_fields, actor)
      delete_attrs, update_attrs = issue_fields.partition { |f| f.is_a?(Issues::IssueFieldDeleteAttributes) }
      delete_attrs.each do |attr|
        issue_field = IssueField.where(id: attr.field_id, owner: T.must(issue.repository).owner).index_by(&:id)

        unless issue_field[attr.field_id]
          issue.errors.add(:issue_fields, "Issue field with id #{attr.field_id} not found.")
          return false
        end

        # Remove and destroy the matching field value
        issue.issue_field_values.each do |v|
          if v.issue_field_id == attr.field_id
            v.destroy! if v.persisted?
            break
          end
        end
        issue.issue_field_values.reload
      end

      return true if update_attrs.empty?

      attributes = update_attrs.map do |field|
        if field.is_a?(Issues::IssueFieldTextValueAttributes) || field.is_a?(Issues::IssueFieldSingleSelectValueAttributes) || field.is_a?(Issues::IssueFieldDateValueAttributes) || field.is_a?(Issues::IssueFieldNumberValueAttributes)
          field
        else
          nil
        end
      end.compact

      result = ::IssueFields::Builder.build_issue_field_values(
        issue: issue,
        actor: actor,
        attributes: attributes
      )
      case result
      when GH::Result::Ok
        result.value.each do |updated_value|
          new_values = issue.issue_field_values.to_a.reject { |v| v.issue_field_id.to_i == updated_value.issue_field_id.to_i }
          new_values << updated_value
          issue.issue_field_values = new_values
          updated_value.save! if updated_value.persisted? && updated_value.changed?
        end
        return true
      when GH::Result::Error
        issue.errors.add(:base, result.message)
        return false
      end
      false # should not reach here
    end

    sig { params(issue: Issue, attributes: CreateIssueAttributes).void }
    def refine_assignee_errors(issue, attributes)
      return unless issue.errors.any?

      assignees_error = issue.errors.where(:assignees).first
      if assignees_error.present?
        issue.errors.delete(:assignees)
        if attributes.assignee
          issue.errors.add(:assignee, assignees_error.message, value: assignees_error.options[:value].first)
        else
          issue.errors.add(:assignees, assignees_error.message, value: assignees_error.options[:value])
        end
      end
    end

    sig { params(assignees: T.nilable(T::Array[Users::IUser]), actor: User, current_assignees: T.nilable(T::Array[User])).returns(T::Array[Users::IUser]) }
    def auto_assign_actor_with_agent(assignees:, actor:, current_assignees: nil)
      return [] if assignees.nil?

      actor_id = actor.id
      assignee_ids = assignees.map(&:id)

      current_assignee_ids = current_assignees&.map(&:id) || []

      # Check if an agentic bot is being NEWLY assigned
      is_newly_assigning_agentic_bot = assignee_ids.any? do |id|
        AgenticApp.agent_for_bot_id(id) && !current_assignee_ids.include?(id)
      end

      # If actor was explicitly removed from the assignees list, don't add them back
      if current_assignees
        actor_was_removed = current_assignee_ids.include?(actor_id) && !assignee_ids.include?(actor_id)
        return assignees if actor_was_removed
      end

      if is_newly_assigning_agentic_bot && !assignee_ids.include?(actor_id)
        assignees + [actor]
      else
        assignees
      end
    end
  end
end
