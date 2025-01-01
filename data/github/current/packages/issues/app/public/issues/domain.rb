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
    accessor Issues::Domain::PlanningTemplates
    accessor Issues::Domain::Transfer

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
        fail_on_invalid_assignees: T::Boolean
      ).returns(GH::Result[IIssue]).checked(:always).on_failure(:raise)
    end
    def create(issue_attributes, actor, viewer: nil, integration: nil, skip_permission_checks: false, fail_on_invalid_assignees: false)
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
        assignees = Array.wrap(assignee_attribute)
      end

      issue.assignees = assignees

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
          create_issue_orchestration = IssueOrchestration.create_issue!(actor: actor, issue: issue, uses_domain: true, is_duplicated: !!issue_attributes.is_duplicated)
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

        if issue_attributes.issue_fields.any?
          # handle deleting first
          issue_attributes.issue_fields.each do |field|
            if field.is_a?(Issues::IssueFieldDeleteAttributes)
              delete_result = delete_issue_field_value(issue, field)
              return delete_result if delete_result.is_a?(GH::Result::Error)
            end
          end

          # handle updating
          update_result = update_issue_field_values(issue, issue_attributes.issue_fields, actor)
          next false if update_result.is_a?(GH::Result::Error)
        end

        case issue_attributes.assignees
        when Issues::UpdateOptions::Keep
          # Do nothing
        else
          if set_assignees?(issue, actor)
            issue.assignees = Array.wrap(issue_attributes.assignees)
          end
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

    # The "open_issue_count_caching" feature flag controlls for which repositories should use the
    # cache. This flag will not initially be rolled out using %, but rather by enabling the flag
    # for a small set of repositories so that we can monitor the metrics for those specific
    # repositories.
    sig { params(repository: ::Repository).returns(T::Boolean) }
    def open_issue_count_caching_enabled?(repository)
      FeatureFlag.vexi.enabled?(:open_issue_count_caching, repository, default: false)
    end

    # Cached version of repository#open_issue_count_for
    # TODO: remove #open_issue_count_for from Repository and implement the method here instead,
    # downgrading to non-AR arguments
    sig { params(repository: ::Repository, viewer: T.nilable(::User), cached: T::Boolean).returns(Integer) }
    def open_issue_count_for_repo(repository, viewer, cached: false)
      if !open_issue_count_caching_enabled?(repository)
        with_database_error_fallback(fallback: 0) do
          repository.open_issue_count_for(viewer)
        end
      else
        count = Issues::Cache::OpenIssueCountClient.new(repository, viewer).fetch(force_refresh: !cached) do
          repository.open_issue_count_for(viewer)
        end

        # if the count was fetched from cache, we need to set it on the repository
        repository.set_open_issue_count_for(viewer, count)
        count
      end
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

    sig { params(issue: Issue, field_id: Issues::IssueFieldDeleteAttributes).returns(T.nilable(GH::Result::Error[T.untyped])) }
    def delete_issue_field_value(issue, field_id)
      issue_field = IssueField.where(id: field_id.field_id, owner: T.must(issue.repository).owner).index_by(&:id)

      unless issue_field[field_id.field_id]
        issue.errors.add(:issue_fields, "Issue field with id #{field_id.field_id} not found.")
        return GH::Result::Error::NotFound.new("Issue field with id #{field_id.field_id} not found.")
      end

      # Remove and destroy the matching field value
      issue.issue_field_values.each do |v|
        if v.issue_field_id == field_id.field_id
          v.destroy! if v.persisted?
          break
        end
      end
      issue.issue_field_values.reload
      nil
    end

    sig { params(issue: Issue, issue_fields: T::Array[T.any(IssueField::IssueFieldAttributesType, Issues::IssueFieldDeleteAttributes)], actor: User).returns(T.nilable(GH::Result::Error[T.untyped])) }
    def update_issue_field_values(issue, issue_fields, actor)
      update_attrs = issue_fields.reject { |f| f.is_a?(Issues::IssueFieldDeleteAttributes) }
      return if update_attrs.empty?

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
        nil
      when GH::Result::Error
        issue.errors.add(:base, result.message)
        GH::Result::Error::Validation.new(issue, message: result.message)
      end
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
  end
end
