# typed: true
# frozen_string_literal: true

class Api::ProjectsV2 < Api::App
  include MemexesHelper
  include ReceiveSchemaWithOpenApi
  include MemexProject::SharedMemexProjectsDependency

  CONTENT_ALREADY_EXISTS = "Content already exists in this project"
  FIELD_VALIDATION_ERROR_MESSAGE = "Field validation errors"

  before do
    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:memex_projects_v2_rest_api, current_user, default: false)
  end

  get "/user/:user_id/projectsV2", operation_id: "projects/list-for-user" do
    receive_with_openapi

    parse_params! => { query:, cursor_opts:, per_page: }
    owner = T.cast(find_user!, User)

    control_access :project_v2_list,
      resource: owner,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    results = owner.projects_by_query(
      query: Search::Queries::MemexProjectQuery.new(query),
      viewer: current_user,
      pagination: GH::Pagination::Cursor.new(**cursor_opts.merge(disable_auth: true)),
      base_scope: projects_base_scope(owner),
      min_permission_level: "read",
      available_records: [current_user]
    )

    projects = results.to_a

    return deliver :projects_hash, [] if projects.empty?

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_for_user_project_prefill"]) do
      prefill_project_associations(projects)
    end

    @links.add_current({ before: results.start_cursor, per_page:, after: nil }, rel: "prev") if results.has_previous_page?
    @links.add_current({ after: results.end_cursor, per_page:, before: nil }, rel: "next") if results.has_next_page?

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_list_for_user"]) do
      deliver :projects_hash, projects
    end
  end

  get "/organizations/:organization_id/projectsV2/:project_number/items/:item_id", operation_id: "projects/get-org-item" do
    receive_with_openapi

    parse_params! => { query:, cursor_opts:, per_page:, field_ids: }

    owner = find_org!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      current_org: owner,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    item = find_item!(project)
    fields = find_fields!(project, field_ids:)

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_get_org_item_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(
        item,
        current_user:,
        available_records: [owner, current_user, project]
      )
    end

    redactor = MemexProjectItemRedactor.new(
      viewer: current_user,
      items: [item],
      columns: fields,
      cap_filter:,
    )

    ensure_non_redacted_item!(redactor)

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_get_org_item_field_value_prefill"]) do
      project.preload_rest_api_response_data(
        items: [item],
        fields:,
      )
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_get_org_item"]) do
      deliver :projects_item_hash, item, {
        fields:,
        redacted_issue_ids: redactor.redacted_issue_ids,
      }
    end
  end

  get "/user/:user_id/projectsV2/:project_number/items/:item_id", operation_id: "projects/get-user-item" do
    receive_with_openapi

    parse_params! => { query:, cursor_opts:, per_page:, field_ids: }

    owner = find_user!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    item = find_item!(project)
    fields = find_fields!(project, field_ids:)

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_get_user_item_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(
        item,
        current_user:,
        available_records: [owner, current_user, project]
      )
    end

    redactor = MemexProjectItemRedactor.new(
      viewer: current_user,
      items: [item],
      columns: fields,
      cap_filter:,
    )

    ensure_non_redacted_item!(redactor)

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_get_user_item_field_value_prefill"]) do
      project.preload_rest_api_response_data(
        items: [item],
        fields:,
      )
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_get_user_item"]) do
      deliver :projects_item_hash, item, {
        fields:,
        redacted_issue_ids: redactor.redacted_issue_ids,
      }
    end
  end

  get "/organizations/:organization_id/projectsV2", operation_id: "projects/list-for-org" do
    receive_with_openapi

    parse_params! => { query:, cursor_opts:, per_page: }
    owner = T.cast(find_org!, Organization)

    control_access :project_v2_list,
      resource: owner,
      current_org: owner,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # For projects, cap filters are validated against the project's owner.
    # In this scenario, there is no need to run cap against _all_ projects owned by
    # the same organization, instead we can frontload this and exit early if necessary.
    ensure_cap!(owner)

    results = owner.projects_by_query(
      query: Search::Queries::MemexProjectQuery.new(query),
      viewer: current_user,
      pagination: GH::Pagination::Cursor.new(**cursor_opts.merge(disable_auth: true)),
      base_scope: projects_base_scope(owner),
      min_permission_level: "read",
      available_records: [current_user, owner],
    )

    projects = results.to_a

    return deliver :projects_hash, [] if projects.empty?

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_for_org_project_prefill"]) do
      prefill_project_associations(projects, available_records: [current_user, owner])
    end

    @links.add_current({ before: results.start_cursor, per_page:, after: nil }, rel: "prev") if results.has_previous_page?
    @links.add_current({ after: results.end_cursor, per_page:, before: nil }, rel: "next") if results.has_next_page?

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_list_for_org"]) do
      deliver :projects_hash, projects
    end
  end

  get "/user/:user_id/projectsV2/:project_number", operation_id: "projects/get-for-user" do
    receive_with_openapi

    owner = find_user!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_get_for_user_project_prefill"]) do
      prefill_project_associations(project, available_records: [current_user, owner])
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_get_for_user"]) do
      deliver :projects_hash, project
    end
  end

  get "/organizations/:organization_id/projectsV2/:project_number", operation_id: "projects/get-for-org" do
    receive_with_openapi

    owner = find_org!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      current_org: owner,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_get_for_org_project_prefill"]) do
      prefill_project_associations(project)
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_get_for_org"]) do
      deliver :projects_hash, project
    end
  end

  get "/user/:user_id/projectsV2/:project_number/fields/:field_id", operation_id: "projects/get-field-for-user" do
    receive_with_openapi

    owner = find_user!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    field = find_field!(project)

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_get_field_for_user"]) do
      deliver :projects_v2_fields_hash, field
    end
  end

  get "/organizations/:organization_id/projectsV2/:project_number/fields/:field_id", operation_id: "projects/get-field-for-org" do
    receive_with_openapi

    owner = find_org!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      current_org: owner,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    field = find_field!(project)

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_get_field_for_org"]) do
      deliver :projects_v2_fields_hash, field
    end
  end

  get "/user/:user_id/projectsV2/:project_number/fields", operation_id: "projects/list-fields-for-user" do
    receive_with_openapi

    parse_params! => { cursor_opts:, per_page: }
    owner = find_user!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    fields = paginated_fields(project, cursor_opts)

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_list_fields_for_user"]) do
      deliver :projects_v2_fields_hash, fields
    end
  end

  get "/organizations/:organization_id/projectsV2/:project_number/fields", operation_id: "projects/list-fields-for-org" do
    receive_with_openapi

    parse_params! => { cursor_opts:, per_page: }
    owner = find_org!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      current_org: owner,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    fields = paginated_fields(project, cursor_opts)

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_list_fields_for_org"]) do
      deliver :projects_v2_fields_hash, fields
    end
  end

  delete "/user/:user_id/projectsV2/:project_number/items/:item_id", operation_id: "projects/delete-item-for-user", read_from_replicas: true do
    receive_with_openapi

    owner = find_user!
    project = find_project!(owner)

    control_access :project_v2_write,
      resource: project,
      forbid: access_allowed?(:project_v2_read,
        resource: project,
        allow_integrations: false,
        allow_user_via_granular_actor: false
      ),
      allow_integrations: false,
      allow_user_via_granular_actor: false

    item = find_item!(project)

    with_write(clusters: [ApplicationRecord::Memex]) do
      item.destroy!
    end
    deliver_empty status: 204
  end

  delete "/organizations/:organization_id/projectsV2/:project_number/items/:item_id", operation_id: "projects/delete-item-for-org", read_from_replicas: true do
    receive_with_openapi

    owner = find_org!
    project = find_project!(owner)

    control_access :project_v2_write,
      resource: project,
      forbid: access_allowed?(:project_v2_read,
        resource: project,
        current_org: owner,
        allow_integrations: true,
        allow_user_via_granular_actor: true
      ),
      current_org: owner,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    item = find_item!(project)

    with_write(clusters: [ApplicationRecord::Memex]) do
      item.destroy!
    end
    deliver_empty status: 204
  end

  get "/user/:user_id/projectsV2/:project_number/items", operation_id: "projects/list-items-for-user" do
    receive_with_openapi

    parse_params! => { query:, cursor_opts:, per_page:, field_ids: }

    owner = find_user!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    fields = find_fields!(project, field_ids:)

    query = Search::Queries::MemexProjectItemQuery.new(
      project: project,
      viewer: current_user,
      cap_filter:,
      query:,
      before: cursor_opts[:before],
      after: cursor_opts[:after],
      first: cursor_opts[:first],
      last: cursor_opts[:last],
    )

    query_results = query.execute
    items = query_results.models

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_items_for_user_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(
        items,
        current_user:,
        available_records: [owner, current_user, project]
      )
    end

    redactor = MemexProjectItemRedactor.new(
      viewer: current_user,
      items: query_results.models,
      columns: fields,
      query_redactor_results: query_results.redactor_results,
      cap_filter:,
    )

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_items_for_user_field_value_prefill"]) do
      project.preload_rest_api_response_data(
        items: redactor.items,
        fields:,
      )
    end

    @links.add_current({ after: nil, before: query_results.start_cursor, per_page: }, rel: "prev") if query_results.has_previous_page
    @links.add_current({ after: query_results.end_cursor, before: nil, per_page: }, rel: "next") if query_results.has_next_page

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_list_items_for_user"]) do
      deliver :projects_item_hash, redactor.items, {
        fields:,
        redacted_issue_ids: redactor.redacted_issue_ids,
      }
    end
  end

  get "/organizations/:organization_id/projectsV2/:project_number/items", operation_id: "projects/list-items-for-org" do
    receive_with_openapi

    parse_params! => { query:, cursor_opts:, per_page:, field_ids: }

    owner = find_org!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      current_org: owner,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    fields = find_fields!(project, field_ids:)

    query = Search::Queries::MemexProjectItemQuery.new(
      project: project,
      viewer: current_user,
      cap_filter:,
      query:,
      before: cursor_opts[:before],
      after: cursor_opts[:after],
      first: cursor_opts[:first],
      last: cursor_opts[:last],
    )

    query_results = query.execute
    items = query_results.models

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_items_for_org_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(
        items,
        current_user:,
        available_records: [owner, current_user, project]
      )
    end

    redactor = MemexProjectItemRedactor.new(
      viewer: current_user,
      items:,
      columns: fields,
      query_redactor_results: query_results.redactor_results,
      cap_filter:,
    )

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_items_for_org_field_value_prefill"]) do
      project.preload_rest_api_response_data(
        items: redactor.items,
        fields:
      )
    end

    @links.add_current({ after: nil, before: query_results.start_cursor, per_page: }, rel: "prev") if query_results.has_previous_page
    @links.add_current({ after: query_results.end_cursor, before: nil, per_page: }, rel: "next") if query_results.has_next_page

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_list_items_for_org"]) do
      deliver :projects_item_hash, redactor.items, {
        fields:,
        redacted_issue_ids: redactor.redacted_issue_ids,
      }
    end
  end

  post "/user/:user_id/projectsV2/:project_number/items", read_from_replicas: true, operation_id: "projects/add-item-for-user" do
    owner = find_user!
    project = find_project!(owner)

    control_access :project_v2_write,
      resource: project,
      forbid: access_allowed?(:project_v2_read,
        resource: project,
        allow_integrations: false,
        allow_user_via_granular_actor: false
      ),
      allow_integrations: false,
      allow_user_via_granular_actor: false

    receive_with_openapi.symbolize_keys => { type:, id: }

    issue_or_pr = ensure_valid_content_for_project_item!(project, type, id)

    ensure_cap!([owner, issue_or_pr.repository])

    item = build_project_item(project, issue_or_pr)

    begin
      with_write(clusters: [ApplicationRecord::Memex]) do
        project.save_with_priority!(item, **{ position: :bottom })
      end
    rescue GitHub::Prioritizable::Context::LockedForRebalance
      deliver_error! 503, message: "This project is temporarily unavailable. Please try again.", documentation_url: @documentation_url
    rescue ActiveRecord::RecordInvalid => invalid
      deliver_error! 422, message: invalid.record.errors.full_messages.to_sentence, documentation_url: @documentation_url
    rescue ActiveRecord::RecordNotUnique
      deliver_error! 422, message: CONTENT_ALREADY_EXISTS, documentation_url: @documentation_url
    end

    unless item.persisted?
      deliver_error! 422, message: item.errors.full_messages.to_sentence, documentation_url: @documentation_url
    end

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_add_item_for_user_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(item, current_user: current_user, available_records: [issue_or_pr, owner, current_user, project])
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_add_item_for_user"]) do
      deliver :simple_projects_item_hash, item, status: 201
    end
  end

  post "/organizations/:organization_id/projectsV2/:project_number/items", read_from_replicas: true, operation_id: "projects/add-item-for-org" do
    owner = find_org!
    project = find_project!(owner)

    control_access :project_v2_write,
      resource: project,
      forbid: access_allowed?(:project_v2_read,
        resource: project,
        current_org: owner,
        allow_integrations: true,
        allow_user_via_granular_actor: true
      ),
      current_org: owner,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    receive_with_openapi.symbolize_keys => { type:, id: }

    issue_or_pr = ensure_valid_content_for_project_item!(project, type, id)

    ensure_cap!([owner, issue_or_pr.repository])

    item = build_project_item(project, issue_or_pr)

    begin
      with_write(clusters: [ApplicationRecord::Memex]) do
        project.save_with_priority!(item, **{ position: :bottom })
      end
    rescue GitHub::Prioritizable::Context::LockedForRebalance
      deliver_error! 503, message: "This project is temporarily unavailable. Please try again.", documentation_url: @documentation_url
    rescue ActiveRecord::RecordInvalid => invalid
      deliver_error! 422, message: invalid.record.errors.full_messages.to_sentence, documentation_url: @documentation_url
    rescue ActiveRecord::RecordNotUnique
      deliver_error! 422, message: CONTENT_ALREADY_EXISTS, documentation_url: @documentation_url
    end

    unless item.persisted?
      deliver_error! 422, message: item.errors.full_messages.to_sentence, documentation_url: @documentation_url
    end

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_add_item_for_org_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(item, current_user: current_user, available_records: [issue_or_pr, owner, current_user, project])
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_add_item_for_org"]) do
      deliver :simple_projects_item_hash, item, status: 201
    end
  end

  patch "/user/:user_id/projectsV2/:project_number/items/:item_id", operation_id: "projects/update-item-for-user", read_from_replicas: true do
    owner = find_user!
    project = find_project!(owner)

    control_access :project_v2_write,
      resource: project,
      forbid: access_allowed?(:project_v2_read,
        resource: project,
        allow_integrations: false,
        allow_user_via_granular_actor: false
      ),
      allow_integrations: false,
      allow_user_via_granular_actor: false

    body = receive_with_openapi.symbolize_keys

    item = find_item!(project)
    deliver_error! 422, message: "This item is archived and cannot be updated" unless item.archived_at.nil?

    values_by_field_id = body[:fields].index_by { |field| field["id"] }
    fields = find_updateable_fields!(project, field_ids: values_by_field_id.keys)

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_update_item_for_user_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(
        item,
        current_user:,
        available_records: [owner, current_user, project]
      )
    end

    redactor = MemexProjectItemRedactor.new(
      viewer: current_user,
      items: [item],
      columns: fields,
      cap_filter:,
    )

    ensure_non_redacted_item!(redactor)

    updates = build_updates!(project, fields, values_by_field_id)

    begin
      with_write(clusters: [ApplicationRecord::Memex]) do
        result = item.update_column_values(updates, current_user)

        unless result.presence
          GitHub.logger.info(
            "Error persisting project item",
            :error => item.errors.full_messages,
            "code.namespace" => self.class.name,
            "code.function" => __method__,
            "gh.user.id" => current_user.id,
            "project_id" => project.id,
            "project_owner_id" => project.owner_id,
            "project_item_id" => item.id,
          )

          deliver_error! 500, message: "Error updating column values"
        end

        GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_update_item_for_user_field_value_prefill"]) do
          project.preload_rest_api_response_data(
            items: [item],
            fields: fields,
          )
        end

        GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_update_item_for_user"]) do
          deliver :projects_item_hash, item, {
            fields: fields,
            redacted_issue_ids: redactor.redacted_issue_ids,
          }
        end
      end
    rescue GitHub::Prioritizable::Context::LockedForRebalance
      deliver_error! 503, message: "This project must be rebalanced."
    rescue ActiveRecord::RecordInvalid => e
      deliver_error! 422, message: "Validation failed", errors: e.record.errors.full_messages, documentation_url: @documentation_url
    end
  end

  patch "/organizations/:organization_id/projectsV2/:project_number/items/:item_id", operation_id: "projects/update-item-for-org", read_from_replicas: true do
    owner = find_org!
    project = find_project!(owner)

    control_access :project_v2_write,
      resource: project,
      forbid: access_allowed?(:project_v2_read,
        resource: project,
        current_org: owner,
        allow_integrations: true,
        allow_user_via_granular_actor: true
      ),
      current_org: owner,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    body = receive_with_openapi.symbolize_keys

    item = find_item!(project)
    deliver_error! 422, message: "This item is archived and cannot be updated" unless item.archived_at.nil?

    values_by_field_id = body[:fields].index_by { |field| field["id"] }
    fields = find_updateable_fields!(project, field_ids: values_by_field_id.keys)

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_update_item_for_org_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(
        item,
        current_user:,
        available_records: [owner, current_user, project]
      )
    end

    redactor = MemexProjectItemRedactor.new(
      viewer: current_user,
      items: [item],
      columns: fields,
      cap_filter:,
    )

    ensure_non_redacted_item!(redactor)

    updates = build_updates!(project, fields, values_by_field_id)

    begin
      with_write(clusters: [ApplicationRecord::Memex]) do
        result = item.update_column_values(updates, current_user)

        unless result.presence
          GitHub.logger.info(
            "Error persisting project item",
            :error => item.errors.full_messages,
            "code.namespace" => self.class.name,
            "code.function" => __method__,
            "gh.user.id" => current_user.id,
            "project_id" => project.id,
            "project_owner_id" => project.owner_id,
            "project_item_id" => item.id,
          )

          deliver_error! 500, message: "Error updating column values"
        end

        GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_update_item_for_org_field_value_prefill"]) do
          project.preload_rest_api_response_data(
            items: [item],
            fields: fields,
          )
        end

        GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_update_item_for_org"]) do
          deliver :projects_item_hash, item, {
            fields: fields,
            redacted_issue_ids: redactor.redacted_issue_ids,
          }
        end
      end
    rescue GitHub::Prioritizable::Context::LockedForRebalance
      deliver_error! 503, message: "This project must be rebalanced."
    rescue ActiveRecord::RecordInvalid => e
      deliver_error! 422, message: "Validation failed", errors: e.record.errors.full_messages, documentation_url: @documentation_url
    end
  end

  private

  sig { params(owner: T.any(Organization, User)).returns(MemexProject) }
  def find_project!(owner)
    project = projects_base_scope(owner).find_by(number: params[:project_number])

    record_or_404(project)
  end

  sig { params(project: MemexProject).returns(MemexProjectColumn::Field::Base) }
  def find_field!(project)
    column = project.memex_project_columns.find_by(id: params[:field_id])
    field = column&.to_field

    if !column || !field || !field.class.rest_api_serializable?
      deliver_error!(
        404,
        documentation_url: @documentation_url
      )
    end

    # Ensure the field is prefilled with the project association
    GitHub::PrefillAssociations.prefill_associations([field], :memex_project, available_records: [project])

    field
  end

  sig { params(project: MemexProject).returns(MemexProjectItem) }
  def find_item!(project)
    item = project.memex_project_items.find_by(id: params[:item_id])

    record_or_404(item)
  end

  sig { params(content_type: String, content_id: Integer).returns(T.any(Issue, PullRequest)) }
  def find_content!(content_type, content_id)
    issue_or_pr = case content_type
    when Issue.name
      Issue.find_by(id: content_id)
    when PullRequest.name
      PullRequest.find_by(id: content_id)
    else
      # Unexpected content type, shouldn't happen if the OpenAPI spec is followed
      deliver_error! 422, message: "Invalid content type: #{content_type}"
    end

    GitHub::PrefillAssociations.prefill_associations(issue_or_pr, [repository: :owner]) if issue_or_pr

    record_or_404(issue_or_pr)
  end

  sig do
    params(
     project: MemexProject,
     columns: T::Array[MemexProjectColumn],
     values_by_field_id: T::Hash[String, T.untyped]
   ).returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def build_updates!(project, columns, values_by_field_id)
    column_value_updates = []
    errors = []

    columns.each do |column|
      value = values_by_field_id[column.id]["value"]

      # The user is clearing the current value
      next column_value_updates << {
        column:,
        value: nil,
        append_only: false
      } if value.nil?

      # OpenAPI will validate that the user has provided a valid numeric or string value
      # For text columns, we can safely coerce the value into a string, replicating
      # behavior seen on the projects client
      value = column.text? ? value.to_s : value

      column_value = MemexProjectColumnValue.new(
        memex_project_column: column,
        value: value,
        memex_project_item: MemexProjectItem.new,
        creator: current_user
      )

      unless column_value.valid?
        column_value.errors.full_messages.each do |error|
          errors << {
            id: column.id,
            value:,
            error:,
          }
        end
      end

      column_value_updates << {
        column:,
        value: column_value.value,
        append_only: false
      }
    end

    deliver_error!(
      400,
      message: "Invalid field values",
      errors: { invalid_field_values: errors },
      documentation_url: @documentation_url
      ) unless errors.empty?

    column_value_updates
  end

  sig { params(owner: T.any(Organization, User)).returns(ActiveRecord::Relation) }
  def projects_base_scope(owner)
    owner.memex_projects.active_projects.filter_spam_for(current_user)
  end

  sig do
    params(
      projects: T.any(MemexProject, T::Array[MemexProject]),
      available_records: T::Array[ActiveRecord::Relation]
    ).void
  end
  def prefill_project_associations(projects, available_records: [])
    GitHub::PrefillAssociations.prefill_associations(projects, [:owner, :creator, { latest_status_update: :creator }], available_records:)
    GitHub::PrefillAssociations.prefill_batch_method(projects, :is_template?)
  end

  sig do
    params(
      resources: T.any(T::Array[ActiveRecord::Base], ActiveRecord::Base)
    ).void
  end
  def ensure_cap!(resources)
    resource_array = Array.wrap(resources)

    authorized_resources = cap_filter.authorized_resources(resource_array)
    deliver_error! 403 if authorized_resources.length != resource_array.length
  end

  # For single item endpoints, we need to ensure the item is not redacted
  # before allowing read or update operations.
  #
  # Given a redactor, this method will return an error if the item is redacted,
  # otherwise, it will return the item.
  sig do
    params(
      redactor: MemexProjectItemRedactor
    ).void
  end
  def ensure_non_redacted_item!(redactor)
    item = redactor.items.first

    if item.nil? || item.content_type == MemexProjectItem::REDACTED_ITEM_TYPE
      deliver_error! 404
    end
  end

  # Validates that the provided field IDs exist in the project, are serializable, and not unsupported.
  # Currently, we only support updating generic field types, with the addition of the Status field.
  sig do
    params(
      project: MemexProject,
      field_ids: T::Array[String]
    ).returns(T::Array[MemexProjectColumn::Field::Base])
  end
  def find_updateable_fields!(project, field_ids: [])
    ids = ensure_valid_field_ids!(field_ids.uniq)
    fields = ensure_valid_fields!(project, ids)

    special_types = fields.reject(&:generic_type?)
    unless special_types.empty?
      deliver_error!(
        400,
        message: FIELD_VALIDATION_ERROR_MESSAGE,
        errors: { unsupported_ids: special_types.map { |col| { id: col.id, message: "'#{col.data_type}' fields are currently unsupported" } } },
        documentation_url: @documentation_url
      )
    end

    fields
  end

  # Validates the provided field IDs and returns the corresponding field objects.
  # When no field IDs are specified, defaults to returning the project's title field.
  # Delivers an error if any field ID is invalid or if no title field exists when needed.
  sig do
    params(
      project: MemexProject,
      field_ids: T::Array[String]
    )
    .returns(T::Array[MemexProjectColumn::Field::Base])
  end
  def find_fields!(project, field_ids: [])
    return [find_default_field!(project)] if field_ids.empty?

    ids = ensure_valid_field_ids!(field_ids.uniq)
    ensure_valid_fields!(project, ids)
  end

  # Ensures that ALL of the provided field IDs exist in the project and are serializable.
  # If any field is not found or not serializable, an error will be returned.
  # Otherwise the corresponding field objects will be returned.
  sig do
    params(
      project: MemexProject,
      field_ids: T::Array[Integer]
    ).returns(T::Array[MemexProjectColumn::Field::Base])
  end
  def ensure_valid_fields!(project, field_ids)
    fields = project.memex_project_columns.where(id: field_ids).to_a.map(&:to_field).compact

    errors = {}

    # Check for missing fields
    missing_ids = field_ids - fields.map(&:id)
    errors[:invalid_ids] = missing_ids.map { |id| { id: id, message: "Field cannot be found" } } if missing_ids.any?

    # Check for non-serializable fields
    unsupported_ids = fields.filter_map { |field| field.id unless field.class.rest_api_serializable? }
    errors[:unsupported_ids] = unsupported_ids if unsupported_ids.any?

    deliver_error!(
      400,
      message: FIELD_VALIDATION_ERROR_MESSAGE,
      errors: errors,
      documentation_url: @documentation_url
    ) if errors.any?

    fields
  end

  # Due to the way query parameters are parsed and provided by OpenAPI
  # we need to ensure they are 'valid' Database IDs. A valid Database ID
  # is effectively any positive integer. When a field ID is invalid, we
  # preserve its original string representation, so that we can provide
  # more informative error messages.
  sig do
    params(
      field_ids: T::Array[String]
    ).returns(T::Array[Integer])
  end
  def ensure_valid_field_ids!(field_ids)
    invalid_ids = []
    valid_ids = []

    field_ids.each do |id|
      formatted_id = id.to_i
      formatted_id.positive? ? valid_ids << formatted_id : invalid_ids << id
    end

    deliver_error!(
      400,
      message: FIELD_VALIDATION_ERROR_MESSAGE,
      errors: { invalid_ids: },
      documentation_url: @documentation_url
    ) if invalid_ids.any?

    valid_ids
  end

  sig { params(project: MemexProject).returns(MemexProjectColumn::Field::Base) }
  def find_default_field!(project)
    title_field = project.memex_project_columns.find(&:title?)&.to_field
    deliver_error!(500, message: "Error fetching project fields") unless title_field
    title_field
  end

  sig { params(content: T.any(Issue, PullRequest)).returns(T::Boolean) }
  def viewer_can_access_content?(content)
    access_check = content.is_a?(Issue) ? :show_issue : :get_pull_request

    owner = content.repository&.owner
    org = owner.is_a?(Organization) ? owner : nil

    access_allowed?(access_check,
      resource: content,
      repo: content.repository,
      current_org: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    )
  end

  # Ensures that the content for an issue or pull request is valid and not already present in the project.
  # If the content is valid, it returns the issue or pull request object.
  # If the content is invalid or already exists, it raises an error.
  sig { params(project: MemexProject, content_type: String, content_id: Integer).returns(T.any(Issue, PullRequest)) }
  def ensure_valid_content_for_project_item!(project, content_type, content_id)
    if project.memex_project_items.exists?(content_type: content_type, content_id:)
      deliver_error! 422, message: CONTENT_ALREADY_EXISTS
    end

    issue_or_pr = find_content!(content_type, content_id)

    deliver_error! 404 unless viewer_can_access_content?(issue_or_pr)

    issue_or_pr
  end

  sig { params(project: MemexProject, content: T.any(Issue, PullRequest)).returns(MemexProjectItem) }
  def build_project_item(project, content)
    project.build_item(issue_or_pull: content, creator: current_user)
  end

  sig { void }
  def ensure_non_conflicting_cursor_params!
    if params.key?(:after) && params.key?(:before)
      deliver_error!(400, message: "Please do not provide both 'before' and 'after' parameters.")
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def parse_params!
    ensure_non_conflicting_cursor_params!

    query = params[:q] || ""
    after = params[:after].presence
    before = params[:before].presence

    per_page = [params[:per_page].presence&.to_i || DEFAULT_PER_PAGE, MAX_PER_PAGE].min

    cursor_opts = if before
      { last: per_page, before: before }
    elsif after
      { first: per_page, after: after }
    else
      { first: per_page }
    end

    {
      query:,
      per_page:,
      cursor_opts:,
      field_ids: params[:fields].presence || []
    }
  end

  sig do
    params(project: MemexProject)
    .returns(ActiveRecord::Relation)
  end
  def serializable_field_scope(project)
    columns = project.memex_project_columns.by_position_and_creation_time

    serializable_fields = columns.select do |column|
      column.to_field&.class&.rest_api_serializable?
    end

    project.memex_project_columns.where(id: serializable_fields.map(&:id))
  end

  sig do
    params(project: MemexProject, cursor_opts: T::Hash[Symbol, T.untyped])
    .returns(T::Array[MemexProjectColumn::Field::Base])
  end
  def paginated_fields(project, cursor_opts)
    fields_scope = serializable_field_scope(project)

    pagination = GH::Pagination::Cursor.new(**cursor_opts.merge(disable_auth: true))
    results = GH::Pagination::CursorScopePaginator.new(
      scope: fields_scope,
      pagination: pagination
    ).paginate

    @links.add_current({ before: results.start_cursor, per_page:, after: nil }, rel: "prev") if results.has_previous_page?
    @links.add_current({ after: results.end_cursor, per_page:, before: nil }, rel: "next") if results.has_next_page?

    fields = results.to_a.map(&:to_field).compact

    GitHub::PrefillAssociations.prefill_associations(fields, :memex_project, available_records: [project])

    fields
  end
end
