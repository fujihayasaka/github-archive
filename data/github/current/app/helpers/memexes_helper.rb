# typed: true
# frozen_string_literal: true

module MemexesHelper
  extend T::Helpers

  include GitHub::Memoizer
  include GitHub::Tracing

  requires_ancestor { Object }

  # These are type aliases used in conjunction with `T.bind` to assert that
  # particular methods need to be used within a specific context.
  #
  # Since the methods in this module are included in many different places,
  # using `requires_ancestor` is too strict, because it would require that every place
  # this helper is included must inherit from the same set of modules/classes. That would
  # be difficult, since this helper is used across components, controllers, and other helpers.
  #
  # Instead, we use `T.bind` in each method to assert that the method is being used in the
  # correct context. These checks are made statically, as well as at run-time. In this way,
  # as long as the method is called in the correct context, then no errors will occur, and
  # the type-checker will be able to infer the correct type.
  MustBeUsedInApplicationController = T.type_alias { T.all(self, ApplicationController) }

  Chartable = MemexProjectColumn::Interface::Chartable

  include MemexAssetsHelper

  # Feature flags that are only used in this code base (and not on the front-end).
  MEMEX_BACKEND_FEATURE_FLAGS = [
    :issue_fields,
    :issue_fields_actor_can_see,
    :optimize_single_memex_hierarchy_prefill,
    :memex_project_consistency_score_ignore_inconsistent_fields,
    # Raise and rescue Elastomer client errors for gracefully degrading client-side
    :memex_raise_on_elastomer_error,
  ]

  # Feature gates are dependent upon the project owner user/org's billing plan (see plans.yml).
  # key: Feature gate as defined in plans.yaml
  # value: Feature name as exposed to the Memex client, suffixed with _public and _private
  #   to differentiate between public and private project features.
  MEMEX_FEATURE_GATES = {
    projectsv2_charts_basic: :memex_charts_basic,
    projectsv2_insights_limited: :memex_insights_limited,
    projectsv2_insights_basic: :memex_insights_basic
  }

  DEFAULT_SORT = "updated-desc"
  SORTS = T.let([
    ["Recently updated", "updated-desc"],
    ["Newest", "created-desc"],
    ["Oldest", "created-asc"],
    ["Least recently updated", "updated-asc"],
    ["Name", "title-asc"],
  ].freeze, T::Array[[String, String]])

  DOCS_PATH = "https://docs.github.com/issues/planning-and-tracking-with-projects"

  def this_memex
    return @this_memex if defined?(@this_memex)
    @this_memex = find_readable_memex(underscored_params[:memex_number])
  end

  sig { params(memex_number: T.nilable(T.any(String, Integer))).returns(T.nilable(MemexProject)) }
  def find_readable_memex(memex_number)
    return nil unless memex_number
    return nil unless (owner = memex_owner)
    owner.memex_projects.active_projects.includes(:owner).find_by(number: memex_number)
  end

  def allowed_generic_data_types
    return @allowed_generic_data_types if defined?(@allowed_generic_data_types)

    @allowed_generic_data_types = MemexProjectColumn::GENERIC_TYPES.map { |c| c.camelize(:lower) }
  end

  def require_memex_enabled
    T.bind(self, MustBeUsedInApplicationController)
    render_404 unless GitHub.projects_new_enabled?
  end

  def require_user_projects_enabled
    T.bind(self, T.any(Profiles::ProjectsController, Users::MemexesController, Users::ProjectsController))
    render_404 if this_user && !this_user.user_projects_enabled?
  end

  # Ensure a non-nil Memex project and owner.
  # The owner is explicitly checked to help protect against hacked cross-tenant API requests
  # such as this bounty issue: https://github.com/github/memex/issues/17198.
  # Note that this_memex and memex_owner are called on the Memexes::Controller class, not methods defined here in MemexesHelper.
  def require_this_memex
    T.bind(self, T.any(Orgs::MemexesController, Users::MemexesController, Memexes::Controller))
    render_404 unless this_memex && memex_owner
  end

  # To support the removal of legacy route constraints and preserve functionality
  # with migrated classic projects, when a Memex is not found we need to check if
  # the memex number is actually a classic project number that has been migrated.
  # If it is, we redirect to the migrated project.
  def handle_migrated_classic_project
    T.bind(self, T.any(Repos::MemexesController, Orgs::MemexesController, Users::MemexesController, Orgs::TeamMemexesController, Memexes::Controller))
    return unless underscored_params[:memex_number].present? && !this_memex && memex_owner

    classic_project = Project.includes(project_migration: :memex_project).find_by(number: underscored_params[:memex_number], owner_id: memex_owner.id, owner_type: memex_owner.class)
    return unless classic_project

    migration = classic_project.project_migration
    return unless migration&.completed?

    migrated_memex_project = migration.memex_project
    return unless migrated_memex_project&.readable_by?(current_user)

    redirect_to migrated_memex_project.url.to_s, status: :permanent_redirect
  end

  def require_verified_email
    T.bind(self, MustBeUsedInApplicationController)
    return if GitHub.enterprise?

    unless current_user.verified_emails?
      render_json_error(
        error: "You must verify an email address in order to take that action.",
        status: :forbidden,
        code: "Forbidden",
      )
    end
  end

  def verify_content_params(params)
    content_type = params[:content_type]
    content = params[:content]

    if MemexProjectItem::VALID_CONTENT_TYPES.include?(content_type)
      missing_params = []
      missing_params << "content.title" if content_type == DraftIssue.name && !content[:title]
      missing_params << "content.id" if content_type != DraftIssue.name && !content[:id]
      missing_params << "content.repositoryId" if content_type != DraftIssue.name && !content[:repository_id]

      if missing_params.any?
        render_json_error(
          error: "Must provide #{missing_params.join(" and ")} to create item of type #{content_type}",
          status: :unprocessable_entity,
        )
      end
    elsif !content_type
      render_json_error(
        error: "You must provide a content_type",
        status: :unprocessable_entity,
      )
    else
      render_json_error(
        error: "Cannot create an item of type #{content_type}",
        status: :unprocessable_entity,
      )
    end
  end

  sig do
    params(
      repository: Repository,
      content_type: String,
      content_id: T.any(String, Integer)
    ).returns(T.nilable(T.any(Issue, PullRequest)))
  end
  def find_content(repository:, content_type:, content_id:)
    case content_type
    when Issue.name
      repository.issues.find_by(id: content_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    when PullRequest.name
      repository.pull_requests.find_by(id: content_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    else
      nil
    end
  end

  def html_safe_json_island(id, data)
    T.bind(self, T.all(MemexesHelper, ActionView::Helpers::TagHelper))
    return unless data

    content_tag(
      :script,
      json_escape(data.to_json).html_safe, # rubocop:disable Rails/OutputSafety
      type: "application/json",
      id: id,
    )
  end

  def underscored_params
    T.bind(self, T.all(MemexesHelper, T.any(ApplicationController, ActionView::Base)))
    return @underscored_params if defined?(@underscored_params)
    @underscored_params = ActionController::Parameters.new(
      params.permit!.to_h.deep_transform_keys(&:underscore),
    )
  end

  sig { returns(T::Boolean) }
  def single_item_update_request?
    underscored_params.has_key?(:memex_project_item_id)
  end

  sig { returns(T::Boolean) }
  def bulk_item_update_request?
    underscored_params.has_key?(:memex_project_items)
  end

  # Returns a list of columns for sorting project items based on the `sortedBy` query parameter.
  #
  # If `sortedBy` is missing from the query string, the method returns `nil`, allowing the implementation
  # to determine fallback sorting behavior. If `sortedBy` is present but empty, it returns an empty array
  # to indicate a valid but unspecified sort order.
  #
  # Example:
  #
  #   Overriding any existing sort order saved on the current view by column ID:
  #   /orgs/github/projects/1?sortedBy[columnId]=1234&sortedBy[direction]=asc
  #   # => [MemexProjectColumn::Interface::Sortable::Param.new(column_id: 1234, direction: "asc")]
  #
  #   Overriding any existing sort order saved on the current view by column name:
  #   /orgs/github/projects/1?sortedBy[columnId]=Repository&sortedBy[direction]=desc
  #   # => [MemexProjectColumn::Interface::Sortable::Param.new(column_id: 4321, direction: "desc")]
  #
  #   Multiple sort orders are supported by passing multiple values for the same key:
  #   /orgs/github/projects/1?sortedBy[columnId]=Repository&sortedBy[direction]=desc&sortedBy[columnId]=Status&sortedBy[direction]=asc
  #   # => [MemexProjectColumn::Interface::Sortable::Param.new(column_id: 4321, direction: "desc"), MemexProjectColumn::Interface::Sortable::Param.new(column_id: 1234, direction: "asc")]
  #
  #   Clearing the sort order, overriding any existing sort order saved on the current view:
  #   /orgs/github/projects/1?sortedBy[columnId]=&sortedBy[direction]=
  #   # => []
  #
  sig { returns(T.nilable(T::Array[MemexProjectColumn::Interface::Sortable::Param])) }
  def memex_sort_params
    T.bind(self, MustBeUsedInApplicationController)
    return @memex_sort_params if defined?(@memex_sort_params)
    @memex_sort_params = nil

    # We parse our own params here because Rails doesn't support multiple values for the same param key.
    # This is because we accept multiple values for sortedBy params (columnId & direction) to allow sorting by multiple columns.
    # This matches client side behavior in useViewStateReducer and the existing URLs we create on the client for views with dirty state.

    # We use URI.parse to get the only the querystring from the original URL because Rails built in params will only have the last instance of the param.
    # Using the querystring we use CGI.parse to get a hash of the params as keys with arrays of values from the querystring.
    # We then match up the columnId and direction based on position.
    # See https://stackoverflow.com/a/35638684 for more info.

    querystring = URI.parse(request.original_url).query
    parsed_params = querystring ? CGI.parse(querystring) : {}

    # If a query string is present, accessing any key will return an empty array instead of nil.
    return @memex_sort_params unless parsed_params.key?("sortedBy[columnId]")

    column_ids = parsed_params["sortedBy[columnId]"]
    @memex_sort_params = []

    column_ids.each_with_index do |column_id, i|
      column = this_memex.find_column_by_name_or_id(column_id)
      if column
        direction = parsed_params.dig("sortedBy[direction]", i) == "desc" ? "desc" : "asc"
        @memex_sort_params.push(MemexProjectColumn::Interface::Sortable::Param.new(column_id: column.id, direction:))
      end
    end

    @memex_sort_params
  end

  # Returns [group_by_key, group_value] for both horizontal and vertical grouped by params given the corresponding params
  # are provided as part of the API request.
  #
  # For compatibility with existing client behavior, column_id can be the field name (synthetic id) or the field id.
  # group_by_key is the verified group_by_key of the field to group on, "" if overriding for no grouping, or nil if not specified.
  # group_value is an optional value for fetching project items within that group.
  def memex_group_params
    T.bind(self, MustBeUsedInApplicationController)
    return @memex_group_params if defined?(@memex_group_params)
    horizontal_group_by_field_param = underscored_params.fetch(:grouped_by, nil)
    vertical_group_by_field_param = underscored_params.fetch(:vertical_grouped_by, nil)
    @memex_group_params = {
      horizontal: horizontal_group_by_field_param ? parse_field_key_value_params(horizontal_group_by_field_param) : [],
      vertical: vertical_group_by_field_param ? parse_field_key_value_params(vertical_group_by_field_param) : [],
      field_ids_to_sum: underscored_params.fetch(:sum_fields, nil),
    }
  end

  # Loads the field models for a given list of field ids
  # and returns the subset of those fields that implement
  # MemexProjectColumn::Interface::Summable.
  sig do
    params(field_ids_to_sum: T.nilable(T.any(String, T::Array[T.untyped])))
    .returns(T.nilable(MemexProjectColumn::Interface::Groupable::FieldMetricOptions))
  end
  def collect_field_metric_options(field_ids_to_sum)
    return unless field_ids_to_sum
    begin
      # JSON parse field_ids_to_sum (typical of JSON string in the URL param)
      field_ids_to_sum = JSON.parse(field_ids_to_sum) if field_ids_to_sum.is_a?(String)
    rescue JSON::ParserError
      # nothing more needed here.
    end
    return unless field_ids_to_sum.is_a?(Array)
    field_ids_to_sum = field_ids_to_sum.map(&:to_i)

    fields_to_sum = this_memex.columns
      .filter_map do |c|
        next unless field_ids_to_sum.include?(c.id)
        field = c.to_field
        field if field.class.summable?
      end
    MemexProjectColumn::Interface::Groupable::FieldMetricOptions.new(
      sum: fields_to_sum,
    )
  end

  # Returns [slice_by, slice_value] params if provided as part of the API request.
  #
  # For compatibility with existing client behavior, column_id can be the field name (synthetic id) or the field id.
  # slice_by is the verified field Id of the field to slice on, "" if overriding for no slicing, or nil if not specified.
  # slice_value is an optional value for fetching items matching that slice field value.
  def memex_slice_params
    T.bind(self, MustBeUsedInApplicationController)
    return @memex_slice_params if defined?(@memex_slice_params)
    slice_by_field_param = underscored_params.fetch(:slice_by, nil)
    @memex_slice_params = slice_by_field_param ? parse_field_key_value_params(slice_by_field_param) : []
  end

  # Returns a `Chartable::Options` instance for memex project chart.
  # `memex_chart_params` may return `nil` if the required `x_axis` argument is missing.
  # In such cases, fallback to `chartable_options_x_axis` or `chartable_options_y_axis`,
  # as a valid `x_axis` or `y_axis` parameter may still be present as part of the request query params.
  sig { returns(T.nilable(Chartable::Options)) }
  def memex_chart_params
    T.bind(self, MustBeUsedInApplicationController)
    return @memex_chart_params if defined?(@memex_chart_params)

    x_axis = chartable_options_x_axis
    return unless x_axis

    @memex_chart_params = Chartable::Options.new(
      x_axis:,
      y_axis: chartable_options_y_axis,
      time: chartable_options_time,
    )
  end

  sig { returns(T.nilable(Chartable::Options::Time)) }
  private def chartable_options_time
    period = underscored_params[:period]

    # We don't need to initialize an instance of Time if the period param is not present
    # or if it is the ElasitcSearch default period of 2 Weeks
    return if period.nil? || period == "2W"

    Chartable::Options::Time.new(
      period:,
      start_date: underscored_params[:start_date],
      end_date: underscored_params[:end_date]
    )
  end

  sig { returns(T.nilable(Chartable::Options::XAxis)) }
  private def chartable_options_x_axis
    T.bind(self, MustBeUsedInApplicationController)
    x_axis = underscored_params.fetch(:x_axis, {})
    x_axis_data_source = x_axis.fetch(:data_source, {})
    period = underscored_params[:period]

    x_axis_column_id = x_axis_data_source[:column]
    is_burnup_chart_request = x_axis_column_id == "time" || (x_axis_column_id.blank? && period.present?)
    x_axis_field_or_id = if is_burnup_chart_request
      "time"
    else
      this_memex.find_column_by_name_or_id(x_axis_column_id)&.to_field
    end

    return nil unless x_axis_field_or_id.present?

    x_axis_group_by_id = x_axis[:group_by]
    x_axis_group_by_field = if x_axis_group_by_id.present?
      this_memex.find_column_by_name_or_id(x_axis_group_by_id)&.to_field
    end

    x_axis_group_by = if x_axis_group_by_field.present?
      Chartable::Options::XAxisGroupBy.new(field_object_or_id: x_axis_group_by_field)
    end

    Chartable::Options::XAxis.new(
      data_source: Chartable::Options::XAxisDataSource.new(
        field_object_or_id: x_axis_field_or_id,
      ),
      group_by: x_axis_group_by,
    )
  end

  # Example of the expected yAxis JSON configuration provided by the client:
  #
  #  {
  #    "yAxis": {
  #      "aggregate": {
  #        "columns": [32],
  #        "operation": "sum"
  #      }
  #    },
  #    "xAxis": {...}
  #  }
  sig { returns(T.nilable(Chartable::Options::YAxis)) }
  private def chartable_options_y_axis
    return unless (y_axis = underscored_params[:y_axis])
    y_axis_parameters = y_axis.require(:aggregate).permit(:operation, :columns)
    begin
      operation = MemexProjectChart::Operation.deserialize(y_axis_parameters[:operation])
    rescue KeyError
      raise Chartable::Options::InvalidYAxisAggregateOperation.new(y_axis_parameters[:operation])
    end
    columns = y_axis_parameters.fetch(:columns, "").split(",").collect(&:to_i).presence

    Chartable::Options::YAxis.new(
      aggregate: Chartable::Options::YAxisAggregate.new(
        field_object_or_id: columns&.first,
        operation:,
      )
    )
  rescue ActionController::UnpermittedParameters => e
    paths = e.params.collect { |key| "'yAxis.aggregate.#{key}'" }
    raise ArgumentError, "#{paths.to_sentence} #{'is'.pluralize(paths.length)} not valid"
  end

  def render_json_error(error:, status:, code: nil, headers: nil)
    T.bind(self, MustBeUsedInApplicationController)
    render(json: { errors: Array.wrap(error), code: code }.compact, status: status, headers:) # rubocop:disable GitHub/RailsViewRenderLiteral
  end

  def render_columns(columns: [], status: :ok)
    T.bind(self, MustBeUsedInApplicationController)
    if columns.is_a?(Array)
      render(json: { memexProjectColumns: columns.map(&:to_hash) }, status: status) # rubocop:disable GitHub/RailsViewRenderLiteral
    else
      render(json: { memexProjectColumn: columns.to_hash }, status: status) # rubocop:disable GitHub/RailsViewRenderLiteral
    end
  end

  def render_columns_with_items(columns: [], status: :ok, cap_filter: nil)
    T.bind(self, MustBeUsedInApplicationController)
    viewer = current_user || nil
    items = this_memex.prioritized_scope(:memex_project_items)
    prefilled_associations = prefill_associations(items, columns)
    redactor = MemexProjectItemRedactor.new(viewer: viewer, items: items, columns: columns, prefilled_associations: prefilled_associations, cap_filter: cap_filter)

    hash_args = {
      items: redactor.items,
      prefilled_associations: prefilled_associations,
      redacted_issue_ids: redactor.redacted_issue_ids
    }

    json = if columns.is_a?(Array)
      { memexProjectColumns: columns.map { |column| column.to_hash(**hash_args) } }
    else
      { memexProjectColumn: columns.to_hash(**hash_args) }
    end

    render(json: json, status: status) # rubocop:disable GitHub/RailsViewRenderLiteral
  end

  # Returns the list of columns in the memex
  # in the future we might want to use this to
  # return only a subset of columns based on some key
  # in the request
  sig { returns(T::Array[MemexProjectColumn::Field::Base]) }
  def item_create_required_fields
    Set.new(remove_excluded_fields(this_memex.columns)).to_a
  end

  # Returns columns that are always required for board view
  def board_required_columns
    # These columns are always displayed regardless of the view configuration.
    this_memex.columns.select { |c| c.title? || c.assignees? || c.repository? }
  end

  # Returns columns that are always required for hierarchy view
  # This is a relic of the past and most likely not used anymore (except in old, internal test projects)
  # Related Jan 2022 PR that added it: https://github.com/github/github/pull/207042
  # It should be considered for removal along with other deprecated Tracks/Tracked By code behind :tasklist_block FF
  def hierarchy_required_columns
    this_memex.columns.select { |c| c.title? || c.status? || c.assignees? || c.repository? }
  end

  # Returns columns that are always required for table view
  def table_required_columns
    # Titles should always be displayed regardless of the view configuration.
    this_memex.columns.select { |c| c.title? }
  end

  # Returns columns that are always required for roadmap view
  def roadmap_required_columns
    # These columns are always displayed regardless of the view configuration.
    this_memex.columns.select { |c| c.title? || c.assignees? }
  end

  def required_columns_for_current_view_layout
    type = this_memex_view_current_layout
    if type == "table"
      table_required_columns
    elsif type == "board"
      board_required_columns
    elsif type == "hierarchy" || type == "list"
      hierarchy_required_columns
    elsif type == "roadmap"
      roadmap_required_columns
    else
      []
    end
  end

  sig { returns(T::Array[MemexProjectColumn::Field::Base]) }
  memoize def required_columns_for_initial_load
    fields = remove_disabled_fields!(required_columns_for_current_view_layout | this_memex_view_required_columns)
    remove_issue_fields(fields)
  end

  # Returns the columns to serialize for a paginated items request.
  # Returns all columns if no field_ids param is provided.
  # Returns requested columns plus default required columns for the view type
  # when field_ids param is present.
  sig { returns(T::Array[MemexProjectColumn::Field::Base]) }
  memoize def required_fields_for_paginated_request
    fields = remove_disabled_fields!(required_columns_for_current_view_layout | columns_from_field_ids_param)
    remove_issue_fields(fields)
  end

  sig { params(columns: T::Array[MemexProjectColumn]).returns(T::Array[MemexProjectColumn::Field::Base]) }
  private def remove_disabled_fields!(columns)
    columns.reject! { |c| c.to_field_class&.disabled? }
    columns.map(&:to_field).compact
  end

  # Return the layout parameter if we're loading a project view, it exists, and it is valid
  # otherwise return the value from the current view directly
  def this_memex_view_current_layout
    return "table" unless this_memex_view
    return this_memex_view.layout_parameter if project_wildcard_route?
    return underscored_params[:layout] if underscored_params[:layout].present? && MemexProjectView.is_valid_layout_parameter(underscored_params[:layout])
    this_memex_view.layout_parameter
  end

  def this_memex_view_roadmap_date_fields
    return [] unless this_memex
    return [] unless this_memex_view
    return [] unless this_memex_view.layout == "roadmap_layout"

    this_memex
      .columns
      .find_all { |c| this_memex_view.column_in_roadmap?(c) }
  end

  def this_memex_view
    T.bind(self, MustBeUsedInApplicationController)
    return @this_memex_view if defined?(@this_memex_view)

    @this_memex_view = if underscored_params[:view_number]
      this_memex.memex_project_views.find_by(number: underscored_params[:view_number])
    else
      this_memex.default_view
    end
  end

  private def this_chart
    T.bind(self, MustBeUsedInApplicationController)
    return @this_chart if defined?(@this_chart)
    @this_chart = this_memex.charts.find_by(number: underscored_params[:chart_number])
  end

  # When the `:paths` param exists or the `:insights` param is truthy,
  # rails has matched the request to a route that
  # is not immediately showing the project board.
  #
  # This can be used to determine if we should
  # consider the given query parameters server side
  # for constructing the response - generally we shouldn't
  # when this is truthy, to avoid conflicting with
  # query parameters from client-side routing
  def project_wildcard_route?
    underscored_params.fetch(:paths, nil).present? || insights_route?
  end

  def project_view_route?
    !project_wildcard_route?
  end

  def insights_route?
    underscored_params.fetch(:insights, nil).present?
  end

  memoize def this_memex_view_required_columns
    if this_memex_view_current_layout == "roadmap"
      this_memex_view_aggregated_fields | this_memex_view_roadmap_date_fields
    else
      this_memex_view_aggregated_fields | this_memex_view_visible_columns | this_memex_view_sorted_columns
    end
  end

  # This uses the preloaded `columns` relation on `this_memex` to save an additional query as
  # compared to `this_memex_view.visible_columns`.
  def this_memex_view_visible_columns
    return @this_memex_view_visible_columns if defined?(@this_memex_view_visible_columns)
    return [] unless this_memex
    return [] unless this_memex_view

    begin
      # only read the param if we're on a project view path
      if visible_fields_param = project_view_route? && underscored_params.fetch(:visible_fields, nil)
        visible_fields = JSON.parse(visible_fields_param)

        if visible_fields.is_a?(Array)
          @this_memex_view_visible_columns = this_memex
            .columns
            .find_all { |c| visible_fields.include?(c.synthetic_id) }
        end
      end
    rescue JSON::ParserError
      # ignore parsing errors for visible_fields, and return
      # the view's visible fields directly
    end

    @this_memex_view_visible_columns ||= this_memex
      .columns
      .find_all { |c| this_memex_view.visible_fields.include?(c.id) && !excluded_columns_hash.key?(c.data_type) }
  end

  sig { returns(T::Array[MemexProjectColumn]) }
  memoize def this_memex_view_aggregated_fields
    return [] unless this_memex
    return [] unless this_memex_view
    aggregated_field_ids = this_memex_view.aggregation_settings&.dig("sum") || []
    this_memex.columns.find_all { |c| aggregated_field_ids.include?(c.id) }
  end

  sig { returns(T::Array[MemexProjectColumn]) }
  memoize def this_memex_view_sorted_columns
    return [] unless this_memex
    return [] unless this_memex_view
    active_sort_params = memex_sort_params
    active_sort_params ||= this_memex_view.sort_params
    sort_column_ids = active_sort_params.map(&:column_id)
    this_memex.columns.find_all { |c| sort_column_ids.include?(c.id) }
  end

  # Returns the columns to serialize for the current request, limited by an optional field_ids param.
  # field_ids can be an array of column_ids or a JSON string of an array of column_ids.
  memoize def columns_from_field_ids_param
    requested_columns = this_memex.columns
    field_ids = underscored_params[:field_ids]
    return requested_columns unless field_ids

    begin
      # JSON parse field_ids (typical of JSON string in the URL param)
      field_ids = JSON.parse(field_ids) if field_ids.is_a?(String)
    rescue JSON::ParserError
      # nothing more to needed here since we check for array next anyway.
    end

    # field_ids should now be an array whether from a GET URL param or a POST body param
    if field_ids.is_a?(Array)
      field_ids = field_ids.map(&:to_s)
      requested_columns = requested_columns.filter do |column|
        field_ids.include?(column.synthetic_id.to_s)
      end
    end

    requested_columns
  end

  SerializationResult = T.type_alias do
    {
      serialized_items: T::Array[T::Hash[T.untyped, T.untyped]],
      prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations)
    }
  end

  sig do
    params(
      items: T.any(T::Array[MemexProjectItem], ActiveRecord::AssociationRelation),
      fields: T::Array[MemexProjectColumn::Field::Base],
      cap_filter: T.nilable(ConditionalAccess::Filter),
      from_paginated_context: T::Boolean,
      redactor_results: T.nilable(Search::Queries::MemexProjectItemQueryRedactor::Results),
      run_prefilled_associations_experiment: T::Boolean,
    ).returns(SerializationResult)
  end
  def serialize_items(items, fields, cap_filter, from_paginated_context: false, redactor_results: nil, run_prefilled_associations_experiment: false)
    T.bind(self, MustBeUsedInApplicationController)
    items = items.to_a

    science "memex_serialize_without_prefilled_associations" do |e|
      e.run_if { run_prefilled_associations_experiment }

      e.context({ request_id: GitHub.context[:request_id] })

      e.try do
        serialization_candidate(
          items:,
          fields:,
          cap_filter:,
          redactor_results:,
          from_paginated_context:,
        )
      end

      e.use do
        serialization_control(
          items:,
          fields:,
          cap_filter:,
          redactor_results:,
          from_paginated_context:,
        )
      end

      e.compare do |control, candidate|
        (control[:serialized_items].zip(candidate[:serialized_items]))
          .reduce(true) do |result, (control_item, candidate_item)|

          # Short-circuit any further comparisons if we've already found a mismatch
          next false unless result

          # Title values have known discrepancies due to changes we've made to the title Markdown pipeline that were
          # not backfilled to existing values. Instead of trying to implement new comparison logic (which would be
          # expensive), just omit those values from the comparison.
          values_equal = control_item[:memexProjectColumnValues].reject { |v| v[:memexProjectColumnId] == "Title" } == \
                       candidate_item[:memexProjectColumnValues].reject { |v| v[:memexProjectColumnId] == "Title" }

          # Everything outside of the values array can be compared as is.
          metadata_equal = control_item.except(:memexProjectColumnValues) == \
                         candidate_item.except(:memexProjectColumnValues)

          values_equal && metadata_equal
        end
      end

      e.clean { |value| value[:serialized_items] }
    end
  end

  # Implements the candidate code (i.e. the code we hope will become the default) in an experiment aimed at
  # simplifying how we serialize project item data in internal API responses.
  sig do
    params(
      items: T::Array[MemexProjectItem],
      fields: T::Array[MemexProjectColumn::Field::Base],
      cap_filter: T.nilable(ConditionalAccess::Filter),
      redactor_results: T.nilable(Search::Queries::MemexProjectItemQueryRedactor::Results),
      from_paginated_context: T::Boolean,
    ).returns(SerializationResult)
  end
  private def serialization_candidate(items:, fields:, cap_filter:, redactor_results:, from_paginated_context:)
    this_memex.preload_web_api_response_data(items:, fields:)
    prefilled_associations = nil

    serialize_items_with_prefilled_associations(
      items:,
      fields:,
      cap_filter:,
      redactor_results:,
      from_paginated_context:,
      prefilled_associations:,
    )
  end

  # Implements the control code (i.e. the code we hope to deprecate) in an experiment aimed at simplifying how we
  # serialize project item data in internal API responses.
  sig do
    params(
      items: T::Array[MemexProjectItem],
      fields: T::Array[MemexProjectColumn::Field::Base],
      cap_filter: T.nilable(ConditionalAccess::Filter),
      redactor_results: T.nilable(Search::Queries::MemexProjectItemQueryRedactor::Results),
      from_paginated_context: T::Boolean,
    ).returns(SerializationResult)
  end
  private def serialization_control(items:, fields:, cap_filter:, redactor_results:, from_paginated_context:)
    prefilled_associations = prefill_associations(items, fields, from_paginated_context:)

    serialize_items_with_prefilled_associations(
      items:,
      fields:,
      cap_filter:,
      redactor_results:,
      from_paginated_context:,
      prefilled_associations:,
    )
  end

  sig do
    params(
      items: T::Array[MemexProjectItem],
      fields: T::Array[MemexProjectColumn::Field::Base],
      cap_filter: T.nilable(ConditionalAccess::Filter),
      redactor_results: T.nilable(Search::Queries::MemexProjectItemQueryRedactor::Results),
      from_paginated_context: T::Boolean,
      prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations)
    ).returns(SerializationResult)
  end
  private def serialize_items_with_prefilled_associations(items:, fields:, cap_filter:, redactor_results:, from_paginated_context:, prefilled_associations:)
    T.bind(self, MustBeUsedInApplicationController)

    serialized_items = MemexProjectItemSerializer
      .new(
        viewer: current_user,
        memex: this_memex,
        query_redactor_results: redactor_results,
        items:,
        columns: fields,
        prefilled_associations:,
        cap_filter:,
        from_paginated_context:,
      )
      .result
      .items

    { serialized_items:, prefilled_associations: }
  end

  # Returns the requested key/value pair [field key, field value] for the given field param for grouping and slicing.
  #  If key == nil: The key was not provided. Default to saved view configuration, if applicable.
  #  If key == "": The key was provided as empty. Consider it an override for no grouping or slicing.
  private def parse_field_key_value_params(field_param)
    field_hash = field_param.permit(:column_id, :value).to_h
    column_id = field_hash.dig("column_id")
    return ["", nil] if column_id == ""

    column = this_memex.find_column_by_name_or_id(column_id)
    key = column&.to_field&.group_by_key
    value = field_hash.dig("value")
    [key, value]
  end

  # Prefills associatons for the given MemexProjectItems and MemexProjectColumns.
  # Includes options for using denormalized values based on the relevant feature flags.
  private def prefill_associations(items, columns, from_paginated_context: false)
    options = {}

    options[:title_column] = this_memex.columns.find(&:title?)
    options[:add_item_id_clause_to_column_values_query] = from_paginated_context

    MemexProjectItemPrefiller.new(items, columns: Array(columns), **options).prefill
  end

  # The tracks and tracked by columns will always be created with new memex projects,
  # but these features are now explicitly disallowed for all targets (GHES, dotcom, and Proxima).
  private def tracks_and_tracked_by_enabled?
    T.bind(self, MustBeUsedInApplicationController)
    false
  end

  private def issue_types_enabled?
    T.bind(self, MustBeUsedInApplicationController)
    return @issue_types_enabled if defined?(@issue_types_enabled)
    @issue_types_enabled = memex_owner&.issue_types_enabled?
  end

  private def memex_status_updates_notifications_enabled?
    T.bind(self, MustBeUsedInApplicationController)
    @memex_status_updates_notifications_enabled ||= feature_enabled_globally_or_for_current_user_or_entity?(:memex_status_updates_notifications, memex_owner)
  end

  private def memex_resync_index_enabled?
    T.bind(self, MustBeUsedInApplicationController)
    return @memex_resync_index_enabled if defined?(@memex_resync_index_enabled)
    @memex_resync_index_enabled = feature_enabled_globally_or_for_current_user_or_entity?(:memex_resync_index, memex_owner)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  private def excluded_columns_hash
    excluded = {}
    unless tracks_and_tracked_by_enabled?
      excluded.merge!(MemexProjectColumn.data_types.slice("tracks"))
      excluded.merge!(MemexProjectColumn.data_types.slice("tracked_by"))
    end

    unless issue_types_enabled?
      excluded.merge!(MemexProjectColumn.data_types.slice("issue_type"))
    end

    excluded
  end

  sig { params(columns: T::Enumerable[MemexProjectColumn]).returns(T::Enumerable[MemexProjectColumn::Field::Base]) }
  private def remove_excluded_fields(columns)
    to_exclude = excluded_columns_hash
    without_excluded = columns.reject { |c| to_exclude.key?(c.data_type) }.map(&:to_field).compact
    remove_issue_fields(without_excluded)
  end

  sig { params(fields: T::Array[MemexProjectColumn::Field::Base]).returns(T::Array[MemexProjectColumn::Field::Base]) }
  private def remove_issue_fields(fields)
    T.bind(self, MustBeUsedInApplicationController)
    return fields unless this_memex.present? && current_user.present?
    return fields if IssueFieldsFeature.enabled?(this_memex, actor: current_user)

    fields.reject(&:issue_field?)
  end

  private def user_has_read_access_if_this_memex_present
    user_has_read_access if this_memex.present?
  end

  private def user_has_read_access
    T.bind(self, MustBeUsedInApplicationController)
    render_404 unless this_memex.viewer_can_read?(current_user)
  end

  private def user_has_write_access
    T.bind(self, MustBeUsedInApplicationController)
    render_404 unless this_memex.viewer_can_write?(current_user)
  end

  private def user_has_admin_access
    T.bind(self, MustBeUsedInApplicationController)
    head(:forbidden) unless this_memex.viewer_is_admin?(current_user)
  end

  sig { returns(T.nilable(Organization)) }
  private def memex_owner
    # todo: we are using T.unsafe here since we know that `this_organization` should exist
    # wherever this is used, but we don't have a class/interface that defines it
    # specifically. We should add that class/interface and use it here, like:
    # `T.bind(self, T.all(MemexesHelper, HasThisOrganization))`
    T.unsafe(self).this_organization
  end

  private def get_suggestions(suggestion_type, target)
    T.bind(self, MustBeUsedInApplicationController)
    case suggestion_type
    when "assignees"
      sorted_assignees = target.sorted_assignees_list(
        current_user: current_user).map do |user|
        user.memex_suggestion_hash(selected: target.assigned_to?(user))
      end

      # Adding the Copilot SWE agent to the list of suggested assignees in memex if
      #   1. item is not a draft (as drafts won't respond to a repository)
      #   2. SWE agent is enabled in the repository that has the issue or pull request
      if (
        target.respond_to?(:repository) &&
        target.repository&.copilot_swe_agent_enabled?(current_user)
      )
        if (swe_agent_app = Apps::Privileged.integration(:copilot_swe_agent)&.bot)
          swe_agent_app_memex_hash = swe_agent_app.memex_suggestion_hash(selected: target.assigned_to?(swe_agent_app))
          sorted_assignees.unshift(swe_agent_app_memex_hash).uniq!
        end
      end

      sorted_assignees
    when "labels"
      sorted_labels = target
        .repository
        .sorted_labels(issue_or_pr: target, cache_label_html: true)

      suggestions = sorted_labels.map do |label|
        label.memex_suggestion_hash(selected: target.unique_label_ids.include?(label.id))
      end

      suggestions
    when "milestones"
      open_milestones, closed_milestones = target
        .repository
        .available_milestones(current_milestone: target.milestone)

      sorted_milestones = [target.milestone].compact + open_milestones + closed_milestones

      suggestions = sorted_milestones.map do |milestone|
        milestone.memex_suggestion_hash(selected: target.milestone_id == milestone.id)
      end

      suggestions
    when "issue_types"
      repo = target.repository
      Issues.domain.issue_types.by_organization(repo.owner_id).map do |issue_type|
        issue_type.memex_suggestion_hash(selected: target.issue_type_id == issue_type.id)
      end
    else
      raise "Unsupported suggestion type: #{suggestion_type}"
    end
  end

  trace_method :serialization_candidate
  trace_method :serialization_control
end
