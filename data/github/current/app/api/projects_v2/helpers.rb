# typed: true
# frozen_string_literal: true

module Api::ProjectsV2::Helpers
  extend T::Helpers

  requires_ancestor { Api::App::ErrorDependency }
  requires_ancestor { Api::App::DeliveryDependency }

  CONTENT_ALREADY_EXISTS = "Content already exists in this project"
  FIELD_VALIDATION_ERROR_MESSAGE = "Field validation errors"
  MAX_FIELD_COUNT_EXCEEDED_MESSAGE = "Cannot specify more than #{MemexProject::COLUMN_LIMIT} field IDs."

  sig { params(owner: T.any(Organization, User)).returns(MemexProject) }
  def find_project!(owner)
    project = projects_base_scope(owner).find_by(number: params[:project_number])

    record_or_404(project)
  end

  sig { params(project: MemexProject).returns(MemexProjectColumn::Field::Base) }
  def find_field!(project)
    column = project.memex_project_columns.find_by(id: params[:field_id])
    field = column&.to_field
    invalid_issue_field = field&.issue_field? && !IssueFieldsFeature.enabled?(project, actor: current_user)
    invalid_issue_field ||= field&.issue_field? && !IssueFieldVisibility.visible_on_project_surfaces?(project, column&.issue_field)

    if !column || !field || !field.class.rest_api_serializable? || invalid_issue_field
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

  sig { params(project: MemexProject).returns(MemexProjectView) }
  def find_view!(project)
    view = project.memex_project_views.find_by(number: params[:view_number])

    record_or_404(view)
  end

  sig { params(content_type: String, content_id: Integer).returns(T.any(Issue, PullRequest, MemexAgentTask)) }
  def find_content!(content_type, content_id)
    content = case content_type
    when Issue.name
      Issue.find_by(id: content_id)
    when PullRequest.name
      PullRequest.find_by(id: content_id)
    when MemexAgentTask.name
      MemexAgentTask.find_by(id: content_id)
    else
      # Unexpected content type, shouldn't happen if the OpenAPI spec is followed
      deliver_error! 422, message: "Invalid content type: #{content_type}"
    end

    GitHub::PrefillAssociations.prefill_associations(content, [repository: :owner]) if content

    record_or_404(content)
  end

  sig { params(content_type: String, owner_login: String, repo: String, number: Integer).returns(T.any(Issue, PullRequest)) }
  def find_content_by_nwo!(content_type, owner_login, repo, number)
    if content_type == MemexAgentTask.name
      deliver_error! 422, message: "AgentTask content type does not support NWO references"
    end

    nwo = "#{owner_login}/#{repo}"
    repository = GitHub::IssueReferenceResolution.find_repo(nwo, nil)
    record_or_404(repository)

    nwo_reference = "#{nwo}##{number}"
    issue = GitHub::IssueReferenceResolution.resolve_issue_reference(nwo_reference, repository)

    issue_or_pr = case content_type
    when Issue.name
      issue unless issue&.pull_request?
    when PullRequest.name
      issue.pull_request
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
      value = column.text? || column.title? ? value.to_s : value

      # Special handling for title columns to set both value and json_value before validation
      if column.title?
        title_string = value
        value = { title: title_string }
        json_value = { title: { html: title_string, raw: title_string } }
      end

      column_value = MemexProjectColumnValue.new(
        memex_project_column: column,
        value: value,
        json_value: json_value,
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
  # The title field is also supported for draft issues.
  sig do
    params(
      project: MemexProject,
      item: MemexProjectItem,
      field_ids: T::Array[String],
    ).returns(T::Array[MemexProjectColumn::Field::Base])
  end
  def find_updateable_fields!(project, item, field_ids: [])
    ids = ensure_valid_field_ids!(field_ids.uniq)
    fields = ensure_valid_fields!(project, ids)

    special_types = fields.select(&:special_type?)

    # Allow title field updates for draft issues, similar to GraphQL API behavior
    if item.draft_issue?
      special_types = special_types.reject { |field| field.data_type.to_sym == :title }
    end

    if special_types.any?
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

  # Validates the provided field IDs for view creation and ensures the title field is included.
  # Delivers an error if any field ID is invalid or if no title field exists.
  sig do
    params(
      project: MemexProject,
      field_ids: T::Array[String]
    ).returns(T::Array[Integer])
  end
  def ensure_valid_view_create_fields!(project, field_ids: [])
    ids = ensure_valid_field_ids!(field_ids.uniq)
    fields = ensure_valid_fields!(project, ids)

    # Ensure title field is included (views must always have a title field)
    unless fields.any?(&:title?)
      title_field = find_default_field!(project)
      fields = [title_field] + fields
    end

    fields.map(&:id)
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

    # Clear out issue fields early if the user doesn't have access to issue fields so they return as invalid ids
    unless IssueFieldsFeature.enabled?(project, actor: current_user)
      fields.reject!(&:issue_field?)
    end

    if project.public?
      hidden_field_ids = IssueFieldVisibility.hidden_issue_field_ids_for(project, fields.filter_map { |f| f.issue_field_id if f.issue_field? })
      fields.reject! { |field| field.issue_field? && hidden_field_ids.include?(field.issue_field_id) } if hidden_field_ids.any?
    end

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

  sig { params(content: T.any(Issue, PullRequest, MemexAgentTask)).returns(T::Boolean) }
  def viewer_can_access_content?(content)
    if content.is_a?(MemexAgentTask)
      return content.readable_by?(current_user)
    end

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
  #
  # This method supports two ways of identifying content:
  # 1. By database ID (content_type, content_id)
  # 2. By repository owner, name, and issue/PR number (content_type, owner, repo, number)
  sig do
    params(
      project: MemexProject,
      content_type: String,
      content_id: T.nilable(Integer),
      owner: T.nilable(String),
      repo: T.nilable(String),
      number: T.nilable(Integer)
    ).returns(T.any(Issue, PullRequest, MemexAgentTask))
  end
  def ensure_valid_content_for_project_item!(project, content_type, content_id: nil, owner: nil, repo: nil, number: nil)
    # Determine which lookup method to use
    # OpenAPI schema validation ensures either content_id or owner/repo/number is provided
    content = if content_id
      find_content!(content_type, content_id)
    elsif owner && repo && number
      find_content_by_nwo!(content_type, owner, repo, number)
    else
      # This should never happen due to OpenAPI schema validation, but to satisfy sorbet we handle it
      deliver_error!(
        422,
        message: "Invalid content identification parameters",
        documentation_url: @documentation_url
      )
    end

    # Check if content already exists in the project
    if project.memex_project_items.exists?(content_type:, content_id: content.id)
      deliver_error! 422, message: CONTENT_ALREADY_EXISTS
    end

    deliver_error! 404 unless viewer_can_access_content?(content)

    content
  end

  sig { params(project: MemexProject, content: T.any(Issue, PullRequest, MemexAgentTask)).returns(MemexProjectItem) }
  def build_project_item(project, content)
    project.build_item(content:, creator: current_user)
  end

  sig { params(project: MemexProject, title: String, body: T.nilable(String)).returns(MemexProjectItem) }
  def build_draft_project_item(project, title:, body: nil)
    project.build_item(creator: current_user, draft_issue_title: title, draft_issue_body: body)
  end

  sig do
    params(
      project: MemexProject,
      content_type: String,
      payload: T::Hash[Symbol, T.untyped]
    ).returns(T.any(Issue, PullRequest, MemexAgentTask))
  end
  def find_content_for_project_item(project, content_type, payload)
    # Support both ID-based and NWO-based lookup
    # OpenAPI schema ensures either id or owner/repo/number is present
    if payload[:id]
      ensure_valid_content_for_project_item!(project, content_type, content_id: payload[:id])
    else
      # Must have owner, repo, and number (validated by OpenAPI schema)
      ensure_valid_content_for_project_item!(project, content_type, owner: payload[:owner], repo: payload[:repo], number: payload[:number])
    end
  end

  sig do
    params(
      project: MemexProject,
      name: String,
      data_type: String,
      single_select_options: T.nilable(T::Array[T.untyped]),
      iteration_configuration: T.nilable(T::Hash[Symbol, T.untyped])
    ).returns(MemexProjectColumn::Field::Base)
  end
  def add_user_defined_field!(project, name:, data_type:, single_select_options: nil, iteration_configuration: nil)
    settings = nil

    if data_type == "single_select"
      options = single_select_options || []
      if options.blank?
        deliver_error!(
          422,
          message: "At least one single select option is required for data_type \"single_select\".",
          documentation_url: @documentation_url
        )
      else
        settings = { options: options.map { |opt| opt.slice(:name, :color, :description) } }
      end
    end

    if data_type == "iteration" && iteration_configuration.present?
      iterations = (iteration_configuration[:iterations] || []).map { |iter| iter.slice(:title, :start_date, :duration) }
      configuration = {
        start_day: Date.iso8601(iteration_configuration[:start_date]).cwday,
        duration: iteration_configuration[:duration],
        iterations:,
      }
      settings = { configuration: }
    end

    column = project.add_user_defined_column(
      name:,
      data_type:,
      settings:,
      position: nil,
      creator: current_user,
    )

    field = column.to_field
    if !column.persisted? || !field || !field.class.rest_api_serializable?
      deliver_error!(
        422,
        message: "Error creating project field",
        documentation_url: @documentation_url
      )
    end

    # Ensure the field is prefilled with the project association
    GitHub::PrefillAssociations.prefill_associations([field], :memex_project, available_records: [project])

    field
  end

  sig do
    params(
      project: MemexProject,
      name: T.nilable(String),
      data_type: T.nilable(String),
      issue_field_id: T.nilable(Integer),
      single_select_options: T.nilable(T::Array[T.untyped]),
      iteration_configuration: T.nilable(T::Hash[Symbol, T.untyped])
    ).returns(MemexProjectColumn::Field::Base)
  end
  def add_org_field!(project, name: nil, data_type: nil, issue_field_id: nil, single_select_options: nil, iteration_configuration: nil)
    validate_org_field_creation_params!(issue_field_id, name, data_type, project)

    if should_create_issue_field?(issue_field_id, project)
      create_issue_field!(project, T.must(issue_field_id))
    else
      add_user_defined_field!(project, name: T.must(name), data_type: T.must(data_type), single_select_options:, iteration_configuration:)
    end
  end

  sig do
    params(
      project: MemexProject,
      issue_field_id: Integer
    ).returns(MemexProjectColumn::Field::Base)
  end
  private def create_issue_field!(project, issue_field_id)
    if project.public?
      issue_field = ::IssueField.find_by(id: issue_field_id)
      unless IssueFieldVisibility.visible_on_project_surfaces?(project, issue_field)
        deliver_error!(
          422,
          message: "This issue field is only visible to organization members and cannot be added to a public project.",
          documentation_url: @documentation_url
        )
      end
    end

    column = project.memex_project_columns
      .create_with(creator: current_user)
      .find_or_create_by(issue_field_id:)

    unless column.persisted?
      deliver_error!(
        422,
        message: "Error creating project issue field",
        documentation_url: @documentation_url
      )
    end

    field = column.to_field
    unless field
      deliver_error!(
        422,
        message: "Error creating project issue field",
        documentation_url: @documentation_url
      )
    end

    GitHub::PrefillAssociations.prefill_associations([field], :memex_project, available_records: [project])

    field
  end

  sig do
    params(
      issue_field_id: T.nilable(Integer),
      name: T.nilable(String),
      data_type: T.nilable(String),
      project: MemexProject
    ).void
  end
  private def validate_org_field_creation_params!(issue_field_id, name, data_type, project)
    # Check if issue field is requested but feature is disabled
    if issue_field_id.present? && !should_create_issue_field?(issue_field_id, project)
      deliver_error!(
        422,
        message: "Issue fields feature is not enabled. Please provide both name and data_type to create a user-defined field instead.",
        documentation_url: @documentation_url
      )
    end

    # Check if issue field and user-defined field params are provided
    if issue_field_id.present? && (name.present? || data_type.present?)
      deliver_error!(
        422,
        message: "Cannot provide both issue_field_id and name/data_type. Use one or the other.",
        documentation_url: @documentation_url
      )
    end
  end

  sig do
    params(
      issue_field_id: T.nilable(Integer),
      project: MemexProject
    ).returns(T::Boolean)
  end
  private def should_create_issue_field?(issue_field_id, project)
    !issue_field_id.nil? && IssueFieldsFeature.enabled?(project, actor: current_user)
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

    query = CGI.unescape(params[:q] || "")
    after = params[:after].presence
    before = params[:before].presence

    per_page = [params[:per_page].presence&.to_i || Api::App::DEFAULT_PER_PAGE, Api::App::MAX_PER_PAGE].min

    cursor_opts = if before
      { last: per_page, before: before }
    elsif after
      { first: per_page, after: after }
    else
      { first: per_page }
    end

    # Parse field_ids parameter which can be provided in multiple formats:
    # - Array format: fields[]=1&fields[]=2
    # - Comma-separated string: fields=1,2
    # - Mixed format: fields[]=1,2&fields[]=3
    # Always returns an array of individual field ID strings
    field_ids = Array(params[:fields]).flat_map { |f| f.to_s.split(",") }

    if field_ids.length > MemexProject::COLUMN_LIMIT
      deliver_error!(422, message: MAX_FIELD_COUNT_EXCEEDED_MESSAGE)
    end

    {
      query:,
      per_page:,
      cursor_opts:,
      field_ids:
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

    # Remove issue fields if the feature is not enabled for the project and current user
    issue_fields_enabled = IssueFieldsFeature.enabled?(project, actor: current_user)
    serializable_fields.reject! do |field|
      field.issue_field? && !issue_fields_enabled
    end

    if project.public?
      hidden_field_ids = IssueFieldVisibility.hidden_issue_field_ids_for(project, serializable_fields.filter_map { |f| f.issue_field_id if f.issue_field? })
      if hidden_field_ids.any?
        serializable_fields.reject! { |field| field.issue_field? && hidden_field_ids.include?(field.issue_field_id) }
      end
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

  sig do
    params(
      project: MemexProject,
      name: String,
      layout: String,
      filter: T.nilable(String),
      visible_fields: T.nilable(T::Array[Integer])
    ).returns(MemexProjectView)
  end
  def create_view!(project, name:, layout:, filter: nil, visible_fields: nil)
    deliver_error!(
      422,
      message: "Cannot create view for closed project",
      documentation_url: @documentation_url
    ) if project.closed?

    # Convert layout string to enum value
    layout_enum = case layout
    when "table"
      :table_layout
    when "board"
      :board_layout
    when "roadmap"
      :roadmap_layout
    else
      deliver_error!(
        422,
        message: "Invalid layout: #{layout}. Must be one of: table, board, roadmap",
        documentation_url: @documentation_url
      )
    end

    # Build view attributes
    view_attrs = {
      creator: current_user,
      name: name,
      layout: layout_enum,
      filter: filter,
    }

    # Add visible_fields if provided
    if visible_fields.present?
      view_attrs[:visible_fields] = visible_fields
    end

    view = project.memex_project_views.build(view_attrs)

    if view.valid?
      project.save_view_with_priority!(view, **{ position: :top })
    end

    unless view.persisted?
      deliver_error!(
        422,
        message: view.errors.full_messages.to_sentence,
        documentation_url: @documentation_url
      )
    end

    view
  end

  # Span attributes describing the fields a Projects v2 REST endpoint touches.
  # Keys must match entries in github/otelcol's redaction-allow-list.yaml
  # exactly — unregistered keys are silently dropped before reaching Datadog APM.
  sig do
    params(
      fields: T::Array[MemexProjectColumn::Field::Base],
      per_page: T.nilable(Integer),
    ).returns(T::Hash[String, T.untyped])
  end
  def field_tracing_attributes(fields, per_page: nil)
    attrs = T.let({
      "gh.memex.projects_v2.field_types" => fields.map(&:data_type).join(", "),
      "gh.memex.projects_v2.field_count" => fields.size,
    }, T::Hash[String, T.untyped])
    attrs["gh.memex.projects_v2.page_size"] = per_page unless per_page.nil?
    attrs
  end
end
