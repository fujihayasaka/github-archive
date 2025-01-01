# typed: true
# frozen_string_literal: true

class Api::Labels < Api::App
  include ReceiveSchemaWithOpenApi
  include Issues::Domain::Provider

  module Helpers
    extend T::Helpers
    include Issues::Domain::Provider

    requires_ancestor { Api::App::ErrorDependency }

    # Fetch all Labels from the given data. Labels that do not exist will be created
    # on-the-fly. Returns early with a 400 if input is not a String or Hash with a
    # value for 'name'.
    #
    # issue - The Issue that is being updated.
    # data  - An Array of Hashes or String names, usually pulled from the body
    #         of the API request.
    #
    # Returns an Array of Labels.
    def labels_for(repo, data)
      return [] if Array(data).compact.blank?

      begin
        label_names = label_names_from_input(data)
      rescue # rubocop:todo Lint/GenericRescue
        deliver_error! 400,
          message: "Invalid Labels: #{data.inspect}.  Must be an Array of strings: ['bug', 'ui']",
          documentation_url: "/v3/issues/labels/"
      end

      if label_names.blank? || label_names.any?(&:blank?)
        deliver_error! 422,
          errors: [api_error(:Label, :name, :missing_field)]
      end

      # Note: if two requests come in at the same time targeting the same repository, we
      # could end up with a race condition where both requests try to create the
      # same label. Adding retries.
      retries_left = 2

      begin
        labels = if GitHub.flipper[:issue_dependency_removal].enabled?
          issues_domain.labels.by_repository_and_names(repository_id: repo.id, names: label_names)
        else
          repo.find_labels_by_name(label_names).to_a
        end
        existing_label_names = labels.map { |l| l.name.downcase }

        Label.transaction do
          label_names.each do |name|
            unless existing_label_names.include?(name.downcase)
              new_label = Label.create!(repository: repo, name: name)
              labels << new_label
            end
          end
        end

        if retries_left < 2
          # track that retries are helping.
          GitHub.dogstats.increment("labels_for.pass_with_retry", tags: ["object_class:#{self.class.name}"])
        end

        labels
      rescue ActiveRecord::RecordInvalid => e
        deliver_error! 422,
          errors: [api_error(:Label, :name, :invalid, value: e.record.name)]
      rescue ActiveRecord::RecordNotUnique
        if retries_left > 0
          retries_left -= 1

          retry
        end

        deliver_error! 422,
          errors: [api_error(:Label, :name, :already_exists)]
      end
    end

    # Internal: Parse label names from API input
    #
    # data - Array where each element is a label name
    #        String or a label Hash.
    #
    # Returns an Array of label name Strings.
    def label_names_from_input(data)
      return nil unless data.respond_to?(:map)

      data.map do |input|
        case input
        when Hash   then input["name"]
        when String then input
        end
      end
    end

    def label_attributes_from_input(data)
      if data.is_a?(Hash)
        return data["labels"].map { |label| { "name" => label } }
      end

      data.map do |input|
        case input
        when Hash   then input
        when String then { "name" => input }
        end
      end
    end
  end

  include Helpers, Api::Issues::EnsureIssuesEnabled
  include Api::Issues::HandleIssueNotFound
  include Scientist

  # List all Labels for this Repository
  get "/repositories/:repository_id/labels", operation_id: "issues/list-labels-for-repo", resolve_tenant_context: :resolve_tenant_from_repo do
    repo = current_repo
    control_access :list_repo_labels,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    labels = repo.labels
    labels = paginate_rel(labels)
    deliver :label_hash, labels, repo: repo
  end

  # Create a Label
  post "/repositories/:repository_id/labels", operation_id: "issues/create-label", resolve_tenant_context: :resolve_tenant_from_repo do
    control_access :create_repo_label, repo: repo = current_repo, allow_integrations: true, allow_user_via_granular_actor: true
    ensure_repo_writable!(repo)

    data = receive_with_schema("label", "create-legacy")
    allowed_attributes = [:name, :color, :description]
    label = repo.labels.build attr(data, *allowed_attributes)

    begin
      label.save
    rescue ActiveRecord::RecordNotUnique => e
      # database errors will not be handled gracefully by .save, instead catch this exception here and retry one more time.
      if e.message.include? "index_labels_on_repository_id_and_label_name"
        label.errors.add(:name, "has already been taken")
      else
        # re-raise if we don't know which index that triggered the exception.
        raise
      end
    end

    if label.errors.empty?
      deliver :label_hash, label, status: 201, repo: repo
    else
      deliver_error 422, errors: label.errors
    end
  end

  # Get a single Label
  # use :splat so sinatra can parse weird tags with periods in them.
  get "/repositories/:repository_id/labels/*", operation_id: "issues/get-label", resolve_tenant_context: :resolve_tenant_from_repo do
    control_access :get_repo_label,
      repo: repo = current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    label_name = label_id
    label = repo.labels.find_by_name(label_name)

    deliver :label_hash, label,
      repo: repo,
      last_modified: calc_last_modified_for_object(label)
  end

  # Update a Label
  # use :splat so sinatra can parse weird tags with periods in them.
  verbs :patch, :post, "/repositories/:repository_id/labels/*", operation_id: "issues/update-label", resolve_tenant_context: :resolve_tenant_from_repo do
    control_access :update_repo_label, repo: repo = current_repo, allow_integrations: true, allow_user_via_granular_actor: true
    ensure_repo_writable!(repo)

    id    = label_id
    data  = receive_with_schema("label", "update-legacy")

    if label = repo.labels.find_by_name(id)
      allowed_attributes = [:name, :color, :description]
      attributes = attr(data, *allowed_attributes)
      attributes[:name] ||= attr(data, :new_name)[:new_name] if data["new_name"]

      if label.update(attributes)
        deliver :label_hash, label, repo: repo
      else
        deliver_error 422, errors: label.errors
      end
    else
      deliver_error 404
    end
  end

  # Delete a label
  delete "/repositories/:repository_id/labels/*", operation_id: "issues/delete-label", resolve_tenant_context: :resolve_tenant_from_repo do
    # Introducing strict validation of the label.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("label", "delete", skip_validation: true)

    control_access :delete_repo_label, repo: repo = current_repo, allow_integrations: true, allow_user_via_granular_actor: true
    ensure_repo_writable!(repo)

    id = label_id
    if label = repo.labels.find_by_name(id)
      label.destroy
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  IssueLabelsQuery = PlatformClient.parse <<-'GRAPHQL'
    query($issueId: ID!, $limit: Int!, $numericPage: Int) {
      node(id: $issueId) {
        ... on Issue {
          lastModifiedAt: updatedAt
          labels(first: $limit, numericPage: $numericPage) {
            totalCount
            nodes {
              lastModifiedAt: updatedAt
              ...Api::Serializer::IssuesDependency::LabelFragment
            }
          }
        }
        ... on PullRequest {
          labels(first: $limit, numericPage: $numericPage) {
            totalCount
            nodes {
              lastModifiedAt: updatedAt
              ...Api::Serializer::IssuesDependency::LabelFragment
            }
          }
        }
      }
    }
  GRAPHQL

  # List labels on the Issue
  get "/repositories/:repository_id/issues/:issue_number/labels", operation_id: "issues/list-labels-on-issue" do
    repo = current_repo
    issue = issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)

    handle_issue_not_found("/labels") unless issue
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "list-labels-on-issue")


    control_access :list_issue_labels,
      repo: repo,
      resource: issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_issues_enabled_or_pr! repo, issue

    variables = {
      issueId: issue.global_relay_id,
      limit: pagination[:per_page] || DEFAULT_PER_PAGE,
      numericPage: pagination[:page],
    }
    results = platform_execute(IssueLabelsQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error({
        errors: results.errors.all,
        resource: "Issue",
        documentation_url: @documentation_url,
      })
    else
      labels  = results.data.node.labels
      nodes   = labels.nodes.map { |n| Api::Serializer::IssuesDependency::LabelFragment.new(n) }

      last_modified = calc_last_modified([issue, *nodes])

      paginator.collection_size = labels.total_count
      deliver :graphql_label_hash, labels.nodes, last_modified: last_modified
    end
  end

  AddIssueLabelsQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: AddOrCreateLabelsToLabelableInput!) {
      addOrCreateLabelsToLabelable(input: $input) {
        errors {
          ...Api::Serializer::ValidationErrorFragment
        }
        labelableRecord {
          labels(first: 100) {
            nodes {
              ...Api::Serializer::IssuesDependency::LabelFragment
            }
          }
        }
      }
    }
  GRAPHQL

  # Add Labels to an Issue
  post "/repositories/:repository_id/issues/:issue_number/labels", operation_id: "issues/add-labels" do
    repo = current_repo
    issue  = issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)

    handle_issue_not_found("/labels") unless issue
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "add-labels")

    control_access :add_label,
      repo: repo,
      resource: issue,
      challenge: repo.public?,
      # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
      # Therefore, we could leave off the integration-related key/value pairs in this call.
      # However, that would count against our linter, so for completeness, we are adding them.
      forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)
    ensure_issues_enabled_or_pr! repo, issue

    label_attributes = label_attributes_from_input(receive_with_schema("label", "add-legacy"))

    if issue.labels.length + label_attributes.length > 100
      deliver_error! 422,
        message: "Validation Failed. Issues cannot have more than 100 labels",
        errors: [api_error(:Label, :labels, :invalid, value: label_attributes)]
    end

    input_variables = {
      "input" => {
        "labelableId"      => issue.global_relay_id,
        "labels"           => label_attributes,
        "clientMutationId" => request_id,
      },
    }

    results = platform_execute(AddIssueLabelsQuery, variables: input_variables)

    if has_graphql_system_errors?(results)
      deprecated_deliver_graphql_error! errors: results.errors, resource: "Label"
    elsif has_graphql_mutation_errors?(results)
      deliver_graphql_mutation_errors! results, input_variables: input_variables, resource: "Label"
    end

    deliver :graphql_label_hash, results.data.add_or_create_labels_to_labelable.labelable_record.labels.nodes
  end

  RemoveIssueLabelsMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: RemoveLabelsFromLabelableInput!) {
      removeLabelsFromLabelable(input: $input)
      {
        errors {
          ...Api::Serializer::ValidationErrorFragment
        }
        labelable {
          labels(first: 100) {
            nodes {
              ...Api::Serializer::IssuesDependency::LabelFragment
            }
          }
        }
      }
    }
  GRAPHQL

  # Remove a Label from an Issue
  delete "/repositories/:repository_id/issues/:issue_number/labels/*", operation_id: "issues/remove-label" do
    # Introducing strict validation of the label.remove-one
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("label", "remove-one", skip_validation: true)

    repo = current_repo
    issue = issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)
    label_name = params[:splat].shift

    handle_issue_not_found("/labels/#{label_name}") unless issue
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "remove-label")


    control_access :remove_label,
      repo: repo,
      resource: issue,
      challenge: repo.public?,
      # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
      # Therefore, we could leave off the integration-related key/value pairs in this call.
      # However, that would count against our linter, so for completeness, we are adding them.
      forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)
    ensure_issues_enabled_or_pr! repo, issue

    label = issue.labels.find_by(lowercase_name: label_name.downcase)

    deliver_error!(404, message: "Label does not exist") if label.nil?

    input_variables = {
      input: {
        labelableId: issue.global_relay_id,
        labelIds: [label.global_relay_id],
        clientMutationId: request_id,
      },
    }

    results = platform_execute(RemoveIssueLabelsMutation, variables: input_variables)

    if has_graphql_system_errors?(results)
      deprecated_deliver_graphql_error! errors: results.errors, resource: "Label"
    elsif has_graphql_mutation_errors?(results)
      deliver_graphql_mutation_errors! results, input_variables: input_variables, resource: "Label"
    end

    deliver :graphql_label_hash, results.data.remove_labels_from_labelable.labelable.labels.nodes
  end

  ReplaceIssueLabelsQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: ReplaceLabelsForLabelableInput!) {
      replaceLabelsForLabelable(input: $input) {
        errors {
          ...Api::Serializer::ValidationErrorFragment
        }
        labelableRecord {
          labels(first: 100) {
            nodes {
              ...Api::Serializer::IssuesDependency::LabelFragment
            }
          }
        }
      }
    }
  GRAPHQL

  # Replace all Labels for an Issue
  put "/repositories/:repository_id/issues/:issue_number/labels", operation_id: "issues/set-labels" do
    repo  = current_repo
    issue = issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)

    handle_issue_not_found("/labels") unless issue
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "set-labels")

    control_access :replace_all_labels,
      repo: repo,
      resource: issue,
      challenge: repo.public?,
      # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
      # Therefore, we could leave off the integration-related key/value pairs in this call.
      # However, that would count against our linter, so for completeness, we are adding them.
      forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)
    ensure_issues_enabled_or_pr! repo, issue

    label_attributes = label_attributes_from_input(receive_with_schema("label", "replace-legacy"))

    input_variables = {
      "input" => {
        "labelableId"      => issue.global_relay_id,
        "labels"           => label_attributes,
        "clientMutationId" => request_id,
      },
    }

    results = platform_execute(ReplaceIssueLabelsQuery, variables: input_variables)

    if has_graphql_system_errors?(results)
      deprecated_deliver_graphql_error! errors: results.errors, resource: "Label"
    elsif has_graphql_mutation_errors?(results)
      deliver_graphql_mutation_errors! results, input_variables: input_variables, resource: "Label"
    end

    deliver :graphql_label_hash, results.data.replace_labels_for_labelable.labelable_record.labels.nodes
  end

  ClearIssueLabelsQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($issueId: ID!, $clientMutationId: String!) {
      clearLabelsFromLabelable(input: {
        labelableId: $issueId
        clientMutationId: $clientMutationId
      })
      {
        errors {
          ...Api::Serializer::ValidationErrorFragment
        }
      }
    }
  GRAPHQL

  # Remove all Labels from an Issue
  delete "/repositories/:repository_id/issues/:issue_number/labels", operation_id: "issues/remove-all-labels" do
    # Introducing strict validation of the label.delete-all-from-issue
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("label", "delete-all-from-issue", skip_validation: true)

    repo  = current_repo
    issue = issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)

    handle_issue_not_found("/labels") unless issue
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "remove-all-labels")


    control_access :remove_all_labels,
      repo: repo,
      resource: issue,
      challenge: repo.public?,
      # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
      # Therefore, we could leave off the integration-related key/value pairs in this call.
      # However, that would count against our linter, so for completeness, we are adding them.
      forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)
    ensure_issues_enabled_or_pr! repo, issue

    input_variables = {
      "issueId"          => issue.global_relay_id,
      "clientMutationId" => request_id,
    }

    results = platform_execute(ClearIssueLabelsQuery, variables: input_variables)

    if has_graphql_system_errors?(results)
      deprecated_deliver_graphql_error! errors: results.errors, resource: "Label"
    elsif has_graphql_mutation_errors?(results)
      deliver_graphql_mutation_errors! results, input_variables: input_variables, resource: "Label"
    end

    deliver_empty(status: 204)
  end

  # Get Labels for every Issue in a Milestone
  get "/repositories/:repository_id/milestones/:milestone_number/labels", operation_id: "issues/list-labels-for-milestone" do
    repo = current_repo
    milestone = repo.milestones.find_by_number(int_id_param!(key: :milestone_number))
    control_access :list_milestone_issue_labels, repo: repo, resource: milestone, allow_integrations: true, allow_user_via_granular_actor: true

    deliver :label_hash, paginate_rel(milestone.labels), repo: repo
  end

  def resolve_tenant_from_repo
    return unless current_repo.present?
    Business.find_by(id: current_repo.tenant_id)
  end

  private

  def label_id
    params[:splat].shift
  end
end
