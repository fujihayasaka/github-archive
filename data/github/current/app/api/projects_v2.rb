# typed: true
# frozen_string_literal: true

class Api::ProjectsV2 < Api::App
  include MemexesHelper
  include ReceiveSchemaWithOpenApi
  include MemexProject::SharedMemexProjectsDependency
  include Api::ProjectsV2::Helpers

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
    field_types = fields.map { |f| f.data_type }.join(", ")

    current_span = OpenTelemetry::Trace.current_span
    current_span.add_attributes({
      "field_types" => field_types,
      "field_count" => fields.size,
    })

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
        viewer: current_user,
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
    field_types = fields.map { |f| f.data_type }.join(", ")

    current_span = OpenTelemetry::Trace.current_span
    current_span.add_attributes({
      "field_types" => field_types,
      "field_count" => fields.size,
    })

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
        viewer: current_user,
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
    field_types = fields.map { |f| f.data_type }.join(", ")

    current_span = OpenTelemetry::Trace.current_span
    current_span.add_attributes({
      "field_types" => field_types,
      "field_count" => fields.size,
      "page_size" => per_page,
    })

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

    redactor = MemexProjectItemRedactor.new(
      viewer: current_user,
      items: query_results.models,
      columns: fields,
      query_redactor_results: query_results.redactor_results,
      cap_filter:,
    )

    items = redactor.items

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_items_for_user_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(
        items,
        current_user:,
        available_records: [owner, current_user, project]
      )
    end

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_items_for_user_field_value_prefill"]) do
      project.preload_rest_api_response_data(
        items:,
        fields:,
        viewer: current_user,
      )
    end

    @links.add_current({ after: nil, before: query_results.start_cursor, per_page: }, rel: "prev") if query_results.has_previous_page
    @links.add_current({ after: query_results.end_cursor, before: nil, per_page: }, rel: "next") if query_results.has_next_page

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_list_items_for_user"]) do
      deliver :projects_item_hash, items, {
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
    field_types = fields.map { |f| f.data_type }.join(", ")

    current_span = OpenTelemetry::Trace.current_span
    current_span.add_attributes({
      "field_types" => field_types,
      "field_count" => fields.size,
      "page_size" => per_page,
    })

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

    redactor = MemexProjectItemRedactor.new(
      viewer: current_user,
      items: query_results.models,
      columns: fields,
      query_redactor_results: query_results.redactor_results,
      cap_filter:,
    )

    items = redactor.items

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_items_for_org_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(
        items,
        current_user:,
        available_records: [owner, current_user, project]
      )
    end

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_items_for_org_field_value_prefill"]) do
      project.preload_rest_api_response_data(
        items:,
        fields:,
        viewer: current_user
      )
    end

    @links.add_current({ after: nil, before: query_results.start_cursor, per_page: }, rel: "prev") if query_results.has_previous_page
    @links.add_current({ after: query_results.end_cursor, before: nil, per_page: }, rel: "next") if query_results.has_next_page

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_list_items_for_org"]) do
      deliver :projects_item_hash, items, {
        fields:,
        redacted_issue_ids: redactor.redacted_issue_ids,
      }
    end
  end

  get "/user/:user_id/projectsV2/:project_number/views/:view_number/items", operation_id: "projects/list-view-items-for-user" do
    receive_with_openapi

    parse_params! => { cursor_opts:, per_page:, field_ids: }

    owner = find_user!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    view = find_view!(project)
    fields = find_fields!(project, field_ids:)
    field_types = fields.map { |f| f.data_type }.join(", ")

    current_span = OpenTelemetry::Trace.current_span
    current_span.add_attributes({
      "field_types" => field_types,
      "field_count" => fields.size,
      "page_size" => per_page,
    })

    # Use only the view's saved filter for deterministic results
    query_obj = Search::Queries::MemexProjectItemQuery.new(
      project: project,
      viewer: current_user,
      cap_filter:,
      query: view.filter || "",
      before: cursor_opts[:before],
      after: cursor_opts[:after],
      first: cursor_opts[:first],
      last: cursor_opts[:last],
    )

    query_results = query_obj.execute

    redactor = MemexProjectItemRedactor.new(
      viewer: current_user,
      items: query_results.models,
      columns: fields,
      query_redactor_results: query_results.redactor_results,
      cap_filter:,
    )

    items = redactor.items

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_view_items_for_user_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(
        items,
        current_user:,
        available_records: [owner, current_user, project]
      )
    end

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_view_items_for_user_field_value_prefill"]) do
      project.preload_rest_api_response_data(
        items:,
        fields:,
        viewer: current_user,
      )
    end

    @links.add_current({ after: nil, before: query_results.start_cursor, per_page: }, rel: "prev") if query_results.has_previous_page
    @links.add_current({ after: query_results.end_cursor, before: nil, per_page: }, rel: "next") if query_results.has_next_page

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_list_view_items_for_user"]) do
      deliver :projects_item_hash, items, {
        fields:,
        redacted_issue_ids: redactor.redacted_issue_ids,
      }
    end
  end

  get "/organizations/:organization_id/projectsV2/:project_number/views/:view_number/items", operation_id: "projects/list-view-items-for-org" do
    receive_with_openapi

    parse_params! => { cursor_opts:, per_page:, field_ids: }

    owner = find_org!
    project = find_project!(owner)

    control_access :project_v2_read,
      resource: project,
      current_org: owner,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    view = find_view!(project)
    fields = find_fields!(project, field_ids:)
    field_types = fields.map { |f| f.data_type }.join(", ")

    current_span = OpenTelemetry::Trace.current_span
    current_span.add_attributes({
      "field_types" => field_types,
      "field_count" => fields.size,
      "page_size" => per_page,
    })

    # Use only the view's saved filter for deterministic results
    query_obj = Search::Queries::MemexProjectItemQuery.new(
      project: project,
      viewer: current_user,
      cap_filter:,
      query: view.filter || "",
      before: cursor_opts[:before],
      after: cursor_opts[:after],
      first: cursor_opts[:first],
      last: cursor_opts[:last],
    )

    query_results = query_obj.execute

    redactor = MemexProjectItemRedactor.new(
      viewer: current_user,
      items: query_results.models,
      columns: fields,
      query_redactor_results: query_results.redactor_results,
      cap_filter:,
    )

    items = redactor.items

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_view_items_for_org_content_prefill"]) do
      ItemContentPrefiller.prefill_associations(
        items,
        current_user:,
        available_records: [owner, current_user, project]
      )
    end

    GitHub.dogstats.distribution_time("api.prefill", tags: ["action:projects_list_view_items_for_org_field_value_prefill"]) do
      project.preload_rest_api_response_data(
        items:,
        fields:,
        viewer: current_user,
      )
    end

    @links.add_current({ after: nil, before: query_results.start_cursor, per_page: }, rel: "prev") if query_results.has_previous_page
    @links.add_current({ after: query_results.end_cursor, before: nil, per_page: }, rel: "next") if query_results.has_next_page

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_list_view_items_for_org"]) do
      deliver :projects_item_hash, items, {
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

    payload = receive_with_openapi.symbolize_keys
    content_type = payload[:type]

    content = find_content_for_project_item(project, content_type, payload)

    ensure_cap!([owner, content.repository])

    item = build_project_item(project, content)

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
      ItemContentPrefiller.prefill_associations(item, current_user: current_user, available_records: [content, owner, current_user, project])
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

    payload = receive_with_openapi.symbolize_keys
    content_type = payload[:type]

    content = find_content_for_project_item(project, content_type, payload)

    ensure_cap!([owner, content.repository])

    item = build_project_item(project, content)

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
      ItemContentPrefiller.prefill_associations(item, current_user: current_user, available_records: [content, owner, current_user, project])
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_add_item_for_org"]) do
      deliver :simple_projects_item_hash, item, status: 201
    end
  end

  post "/user/:user_id/projectsV2/:project_number/drafts", read_from_replicas: true, operation_id: "projects/create-draft-item-for-authenticated-user" do
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

    ensure_cap!(owner)

    body = receive_with_openapi.symbolize_keys
    item = build_draft_project_item(project, title: body[:title], body: body[:body])

    begin
      with_write(clusters: [ApplicationRecord::Memex]) do
        project.save_with_priority!(item, **{ position: :bottom })
      end
    rescue GitHub::Prioritizable::Context::LockedForRebalance
      deliver_error! 503, message: "This project is temporarily unavailable. Please try again.", documentation_url: @documentation_url
    rescue ActiveRecord::RecordInvalid => invalid
      deliver_error! 422, message: invalid.record.errors.full_messages.to_sentence, documentation_url: @documentation_url
    end

    unless item.persisted?
      deliver_error! 422, message: item.errors.full_messages.to_sentence, documentation_url: @documentation_url
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_add_draft_item_for_authenticated_user"]) do
      deliver :simple_projects_item_hash, item, status: 201
    end
  end

  post "/organizations/:organization_id/projectsV2/:project_number/drafts", read_from_replicas: true, operation_id: "projects/create-draft-item-for-org" do
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

    ensure_cap!(owner)

    body = receive_with_openapi.symbolize_keys
    item = build_draft_project_item(project, title: body[:title], body: body[:body])

    begin
      with_write(clusters: [ApplicationRecord::Memex]) do
        project.save_with_priority!(item, **{ position: :bottom })
      end
    rescue GitHub::Prioritizable::Context::LockedForRebalance
      deliver_error! 503, message: "This project is temporarily unavailable. Please try again.", documentation_url: @documentation_url
    rescue ActiveRecord::RecordInvalid => invalid
      deliver_error! 422, message: invalid.record.errors.full_messages.to_sentence, documentation_url: @documentation_url
    end

    unless item.persisted?
      deliver_error! 422, message: item.errors.full_messages.to_sentence, documentation_url: @documentation_url
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_add_draft_item_for_org"]) do
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
    fields = find_updateable_fields!(project, item, field_ids: values_by_field_id.keys)

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
            viewer: current_user,
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
    fields = find_updateable_fields!(project, item, field_ids: values_by_field_id.keys)

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
            viewer: current_user,
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

  post "/user/:user_id/projectsV2/:project_number/fields", read_from_replicas: true, operation_id: "projects/add-field-for-user" do
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

    ensure_cap!(owner)

    body = receive_with_openapi.deep_symbolize_keys

    new_field = begin
      with_write(clusters: [ApplicationRecord::Memex]) do
        add_user_defined_field!(project, **body)
      end
    rescue ActiveRecord::RecordInvalid => invalid
      deliver_error! 422, message: invalid.record.errors.full_messages.to_sentence, documentation_url: @documentation_url
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_add_field_for_user"]) do
      deliver :projects_v2_fields_hash, new_field, status: 201
    end
  end

  post "/organizations/:organization_id/projectsV2/:project_number/fields", read_from_replicas: true, operation_id: "projects/add-field-for-org" do
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

    ensure_cap!(owner)

    body = receive_with_openapi.deep_symbolize_keys

    new_field = begin
      with_write(clusters: [ApplicationRecord::Memex]) do
        add_org_field!(project, **body)
      end
    rescue ActiveRecord::RecordInvalid => invalid
      deliver_error! 422, message: invalid.record.errors.full_messages.to_sentence, documentation_url: @documentation_url
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_add_field_for_org"]) do
      deliver :projects_v2_fields_hash, new_field, status: 201
    end
  end

  post "/user/:user_id/projectsV2/:project_number/views", read_from_replicas: true, operation_id: "projects/create-view-for-user" do
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

    ensure_cap!(owner)

    body = receive_with_openapi.deep_symbolize_keys

    # Only validate visible fields for non-roadmap views as roadmap views do not have visible fields
    if body[:layout] == "roadmap"
      body[:visible_fields] = []
    elsif body[:visible_fields].present?
      body[:visible_fields] = ensure_valid_view_create_fields!(project, field_ids: body[:visible_fields])
    end

    view = begin
      with_write(clusters: [ApplicationRecord::Memex, ApplicationRecord::Mysql1]) do
        create_view!(project, **body)
      end
    rescue ActiveRecord::RecordInvalid => invalid
      deliver_error! 422, message: invalid.record.errors.full_messages.to_sentence, documentation_url: @documentation_url
    rescue GitHub::Prioritizable::Context::LockedForRebalance
      deliver_error! 503, message: "This project is temporarily unavailable. Please try again.", documentation_url: @documentation_url
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_create_view_for_user"]) do
      deliver :projects_v2_view_hash, view, status: 201
    end
  end

  post "/organizations/:organization_id/projectsV2/:project_number/views", read_from_replicas: true, operation_id: "projects/create-view-for-org" do
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

    ensure_cap!(owner)

    body = receive_with_openapi.deep_symbolize_keys

    # Only validate visible fields for non-roadmap views as roadmap views do not have visible fields
    if body[:layout] == "roadmap"
      body[:visible_fields] = []
    elsif body[:visible_fields].present?
      body[:visible_fields] = ensure_valid_view_create_fields!(project, field_ids: body[:visible_fields])
    end

    view = begin
      with_write(clusters: [ApplicationRecord::Memex, ApplicationRecord::Mysql1]) do
        create_view!(project, **body)
      end
    rescue ActiveRecord::RecordInvalid => invalid
      deliver_error! 422, message: invalid.record.errors.full_messages.to_sentence, documentation_url: @documentation_url
    rescue GitHub::Prioritizable::Context::LockedForRebalance
      deliver_error! 503, message: "This project is temporarily unavailable. Please try again.", documentation_url: @documentation_url
    end

    GitHub.dogstats.distribution_time("api.deliver", tags: ["action:projects_create_view_for_org"]) do
      deliver :projects_v2_view_hash, view, status: 201
    end
  end
end
