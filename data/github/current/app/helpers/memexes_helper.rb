# typed: true
# frozen_string_literal: true

module MemexesHelper
  extend T::Sig
  extend T::Helpers
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

  include MemexAssetsHelper
  include Issues::Domain::Provider

  # Additional feature flags which are associated with front-end functionality. These are
  # sent to the client for use on the front-end as well as in this code base.
  #
  # There are two things to note about tests for this list:
  #
  # 1. If you add or remove a flag from this list, you will need to update a
  #    test against MemexesControllerCommonTests that asserts on the specific flags
  #    in this list at any one time. That is an intentional safeguard.
  # 2. This variable should not be removed even if it contains an empty array,
  #    because we also test the empty behaviour of this array.
  MEMEX_CLIENT_FEATURE_FLAGS = [
    :memex_insights,
    :memex_charts_basic_allow,
    :tasklist_block,
    :memex_historical_charts_on_assignees_milestones,
    # redesign of tracked by pills and hovercards
    :tasklist_tracked_by_redesign,
    # group by changes to improve support for multi-value fields
    :memex_group_by_multi_value_changes,
    # Enable Resync Elasticsearch index button for project admins for Memex Without Limits
    :memex_resync_index,
    # Enable table view without limits (Elasticsearch powered backend)
    :memex_table_without_limits,
    # Feature flag to toggle the ChartCard on the insights memex page
    :memex_chart_cards_insights,
    # Disable fileupload in the side-panel for draft issues
    :memex_disable_draft_issue_file_upload,
    # live updates via gQL subscriptions for the issue viewer
    :graphql_subscriptions,
    # Disable autofocusing first item in project views
    :memex_disable_autofocus,
    # Enable the issue_types picker in issue_create
    :issue_types,
    # Enable drag & drop features for task lists
    :issues_react_checklist_improvements,
    # Enable notifications for status updates
    :memex_status_updates_notifications,
    # Display the sub-issues list and button group
    :sub_issues,
    # Whether to show the beta optout controls
    :mwl_beta_optout,
    # Enable filter bar validation for mwl
    :mwl_filter_bar_validation,

    # Enable board view swimlanes for Projects Without Limits
    :memex_mwl_swimlanes,

    # Respect server-side vertical group order
    :memex_mwl_server_group_order,

    # Only include requested field ids in paginated items responses
    :memex_mwl_limited_field_ids,

    # Allow users to create new label in the repo if the label is not found in the picker
    :issues_react_create_new_label,

    # disables the projects classic UI
    :projects_classic_sunset_ui,

    # ensures that the projects classic UI is enabled
    :projects_classic_sunset_override
  ].freeze

  # Feature flags that use custom actors to enable a feature on a per project basis.
  # Add the project via `MemexProject:id` to the flipper ID field to add the project to the feature flag.
  # These are also sent to the client for use on the front-end.
  MEMEX_PROJECT_ACTOR_FEATURE_FLAGS = [
    # Paginate the Archive view to support an archived items limit of 48K
    :memex_paginated_archive,
    # Enable table view without limits (Elasticsearch powered backend)
    :memex_table_without_limits,
  ]

  # Flags that, when enabled, will effectively disable the dependent array of flags.
  MEMEX_GROUP_TOGGLE_FEATURE_FLAGS = {
    memex_without_limits_kill_switch: [
      :memex_paginated_archive,
      :memex_table_without_limits,
    ].freeze
  }.freeze

  # Feature flags that are only used in this code base (and not on the front-end).
  MEMEX_BACKEND_FEATURE_FLAGS = [
    :optimize_single_memex_hierarchy_prefill,
    # Allow tasklist columns (Tracks and Tracked by) in the project, despite enabling memex_table_without_limits.
    # Add to a specific project via `MemexProject:id` to the flipper ID field to add the project to the feature flag.
    :memex_mwl_allow_tasklist_columns,
    :memex_project_consistency_score_ignore_inconsistent_fields,
    :memex_only_load_visible_fields,
    # Render emoji suggestions with preferred skin tone
    :emoji_suggestions_react_skin_tone,
    # Temporarily required to instantiate Profiles::Kv (which backs preferred_emoji_skin_tone) during dual-write transition period
    :profiles_write_to_target
  ]

  # Feature previews that are available to Memex users
  MEMEX_FEATURE_PREVIEWS = []

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
  SORTS = [
    ["Recently updated", "updated-desc"],
    ["Newest", "created-desc"],
    ["Oldest", "created-asc"],
    ["Least recently updated", "updated-asc"],
    ["Name", "title-asc"],
  ].freeze

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
      repository.issues.find_by(id: content_id)
    when PullRequest.name
      repository.pull_requests.find_by(id: content_id)
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

  def memex_sort_params
    T.bind(self, MustBeUsedInApplicationController)
    return @memex_sort_params if defined?(@memex_sort_params)
    @memex_sort_params = []

    # We parse our own params here because Rails doesn't support multiple values for the same param key.
    # This is because we accept multiple values for sortedBy params (columnId & direction) to allow sorting by multiple columns.
    # This matches client side behavior in useViewStateReducer and the existing URLs we create on the client for views with dirty state.

    # We use URI.parse to get the only the querystring from the original URL because Rails built in params will only have the last instance of the param.
    # Using the querystring we use CGI.parse to get a hash of the params as keys with arrays of values from the querystring.
    # We then match up the columnId and direction based on position.
    # See https://stackoverflow.com/a/35638684 for more info.

    querystring = URI.parse(request.original_url).query
    parsed_params = querystring ? CGI.parse(querystring) : {}
    column_ids = parsed_params["sortedBy[columnId]"] || []

    column_ids.each_with_index do |column_id, i|
      column = this_memex.find_column_by_name_or_id(column_id)
      if column
        direction = parsed_params.dig("sortedBy[direction]", i) == "desc" ? "desc" : "asc"
        @memex_sort_params.push(column.to_field.sort_fragment(direction: direction))
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
    }
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

  def render_json_error(error:, status:, code: nil)
    T.bind(self, MustBeUsedInApplicationController)
    render(json: { errors: Array.wrap(error), code: code }.compact, status: status) # rubocop:disable GitHub/RailsViewRenderLiteral
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
      require_prefilled_associations: true,
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
  def item_create_required_columns
    Set.new(remove_excluded_columns(this_memex.columns)).to_a
  end

  # Returns columns that are required on initial load for board view
  def board_initial_required_columns
    if memex_table_without_limits_enabled? && GitHub.flipper[:memex_only_load_visible_fields].enabled?
      # These columns are always displayed regardless of the view configuration.
      required_columns = this_memex.columns.select { |c| c.title? || c.assignees? || c.repository? }
      required_columns | this_memex_view_visible_columns
    else
      columns_to_preload([
        MemexProjectColumn::TITLE_COLUMN_NAME,
        MemexProjectColumn::STATUS_COLUMN_NAME,
        MemexProjectColumn::ASSIGNEES_COLUMN_NAME,
        MemexProjectColumn::REPOSITORY_COLUMN_NAME
      ])
    end
  end

  # Returns columns that are required on initial load for hierarchy view
  def hierarchy_initial_required_columns
    columns_to_preload([
      MemexProjectColumn::TITLE_COLUMN_NAME,
      MemexProjectColumn::STATUS_COLUMN_NAME,
      MemexProjectColumn::ASSIGNEES_COLUMN_NAME,
      MemexProjectColumn::REPOSITORY_COLUMN_NAME
    ])
  end

  # Returns columns that are required on initial load for table view
  def table_initial_required_columns
    if memex_table_without_limits_enabled? && GitHub.flipper[:memex_only_load_visible_fields].enabled?
      this_memex_view_visible_columns
    else
      columns_to_preload([
        MemexProjectColumn::TITLE_COLUMN_NAME,
        MemexProjectColumn::STATUS_COLUMN_NAME,
      ])
    end
  end

  # Returns columns that are required on initial load for roadmap view
  def roadmap_initial_required_columns
    if memex_table_without_limits_enabled? && GitHub.flipper[:memex_only_load_visible_fields].enabled?
      # These columns are always displayed regardless of the view configuration.
      required_columns = this_memex.columns.select { |c| c.title? || c.assignees? }
      required_columns | this_memex_view_roadmap_date_fields
    else
      columns_to_preload([
        MemexProjectColumn::TITLE_COLUMN_NAME,
        MemexProjectColumn::STATUS_COLUMN_NAME,
        MemexProjectColumn::ASSIGNEES_COLUMN_NAME
      ]).push(*this_memex_view_roadmap_date_fields)
    end
  end

  def columns_to_preload(required_column_names)
    required_columns = this_memex.columns.find_all { |c| required_column_names.include?(c.name) }

    if memex_table_without_limits_enabled? && GitHub.flipper[:memex_only_load_visible_fields].enabled?
      (
        this_memex_view_visible_columns |
        required_columns
      ).to_a
    else
      (
        this_memex_view_visible_columns |
        this_memex_view_horizontal_grouped_by_column |
        this_memex_view_vertical_grouped_by_column |
        this_memex_view_slice_by_columns |
        required_columns
      ).to_a
    end
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

  # If slicing on Tracked by, we need to include both the Tracked by and Tracks columns
  def add_tracks_if_tracked_by_slice_column(columns)
    is_tracked_by = columns.first&.tracked_by? && !excluded_columns_hash.key?(MemexProjectColumn::TRACKS_COLUMN_NAME)
    is_tracked_by ? [columns.first, this_memex.columns.find(&:tracks?)].compact : columns
  end

  def this_memex_view_horizontal_grouped_by_column
    return @this_memex_view_horizontal_group_by if defined?(@this_memex_view_horizontal_group_by)
    @this_memex_view_horizontal_group_by = this_memex_view_grouped_by_column(:grouped_by, this_memex_view&.group_by)
  end

  def this_memex_view_vertical_grouped_by_column
    return @this_memex_view_vertical_group_by if defined?(@this_memex_view_vertical_group_by)
    @this_memex_view_vertical_group_by = this_memex_view_grouped_by_column(:vertical_grouped_by, this_memex_view&.vertical_group_by)
  end

  def this_memex_view_grouped_by_column(group_by_param_name, group_by_field)
    return [] unless this_memex
    return [] unless this_memex_view

    begin
      # Check the URL paramters for a `group_by_param_name` param - either verticalGroupedBy or groupedBy
      # if the current page loading is a project view and the param exists and is valid
      if group_by_param = project_view_route? && underscored_params.fetch(group_by_param_name, nil)
        group_by = group_by_param.permit(:column_id, :value).to_h

        group_by.transform_values! { |v| parse_synthetic_id(v) }

        if group_by.is_a?(Hash)
          result = this_memex.columns.find_all { |c| group_by.values.include?(c.synthetic_id) }
        end
      end
    rescue JSON::ParserError
      # ignore parsing errors for group_by, and return
      # the view's grouped by fields directly
    end

    if group_by_field.nil?
      return result || []
    end

    # Otherwise check if the view has a saved grouped_by_field
    # Either `vertical_group_by` or `horizontal_group_by` depending
    # on the value of group_by_field
    result ||= this_memex
      .columns
      .find_all { |c| group_by_field.include?(c.id) }
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

  # When the `:paths` param exists,
  # rails has matched the request to a route that
  # is not immediately showing the project board.
  #
  # This can be used to determine if we should
  # consider the given query parameters server side
  # for constructing the response - generally we shouldn't
  # when this is truthy, to avoid conflicting with
  # query parameters from client-side routing
  def project_wildcard_route?
    underscored_params.fetch(:paths, nil).present?
  end

  def project_view_route?
    !project_wildcard_route?
  end

  # This uses the preloaded `columns` relation on `this_memex` to save an additional query as
  # compared to `this_memex_view.visible_columns`.
  def this_memex_view_visible_columns
    return @this_memex_view_visible_columns if defined?(@this_memex_view_visible_columns)
    return [] unless this_memex
    return [] unless this_memex_view

    begin
      # only read the param if we're on a project table path
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

  def this_memex_view_slice_by_columns
    return @this_memex_view_slice_by_columns if defined?(@this_memex_view_slice_by_columns)
    return [] unless this_memex
    return [] unless this_memex_view

    begin
      # only read the param if we're on a project path
      if slice_by_field_param = project_view_route? && underscored_params.fetch(:slice_by, nil)
        slice_by_hash = slice_by_field_param.permit(:column_id, :value).to_h
        slice_by_field = slice_by_hash.dig("column_id")
        slice_by_field = parse_synthetic_id(slice_by_field)

        if slice_by_field
          slice_by_column = this_memex
            .columns
            .find_all { |c| slice_by_field == c.synthetic_id && !excluded_columns_hash.key?(c.data_type) }

          @this_memex_view_slice_by_columns = add_tracks_if_tracked_by_slice_column(slice_by_column)
          return @this_memex_view_slice_by_columns if @this_memex_view_slice_by_columns
        end
      end
    rescue JSON::ParserError
      # ignore parsing errors for slice_by, and return
      # the view's slice by directly
    end

    if this_memex_view.slice_by&.dig("field").nil?
      return []
    end

    slice_by_column = this_memex
      .columns
      .find_all { |c| this_memex_view.column_sliced?(c) && !excluded_columns_hash.key?(c.data_type) }
    @this_memex_view_slice_by_columns = add_tracks_if_tracked_by_slice_column(slice_by_column)
  end

  def serialize_items(items, columns, cap_filter, from_paginated_context: false)
    T.bind(self, MustBeUsedInApplicationController)
    prefilled_associations = prefill_associations(items, columns, from_paginated_context:)
    serialized_items = MemexProjectItemSerializer
      .new(
        viewer: current_user,
        memex: this_memex,
        items: items,
        columns: columns,
        prefilled_associations: prefilled_associations,
        cap_filter: cap_filter,
        from_paginated_context:,
      )
      .result
      .items
    { serialized_items: serialized_items, prefilled_associations: prefilled_associations }
  end

  private

  # Prefills associatons for the given MemexProjectItems and MemexProjectColumns.
  # Includes options for using denormalized values based on the relevant feature flags.
  def prefill_associations(items, columns, from_paginated_context: false)
    options = {}

    options[:title_column] = this_memex.columns.find(&:title?)
    options[:read_denormalized_title] = true
    options[:read_denormalized_milestone] = true
    options[:add_item_id_clause_to_column_values_query] = from_paginated_context

    MemexProjectItemPrefiller.new(items, columns: Array(columns), **options).prefill
  end

  def parse_synthetic_id(string_id)
    synthetic_id = string_id
    begin
      synthetic_id = Integer(string_id)
    # For system column ids like Status, we can expect this conversion to fail
    rescue ArgumentError, TypeError
      synthetic_id = string_id
    end
    synthetic_id
  end

  # The tracks and tracked by columns will always be created with new memex projects,
  # but we control the visibility to the viewing user or owning org by the tasklist_block feature flag.
  # These columns are disabled by default for memex_table_without_limits (mwl) to improve performance,
  # but can be enabled with mwl via the :memex_mwl_allow_tasklist_columns feature flag.
  def tracks_and_tracked_by_enabled?
    T.bind(self, MustBeUsedInApplicationController)
    return @tracks_column_enabled if defined?(@tracks_column_enabled)
    @tracks_column_enabled = feature_enabled_globally_or_for_current_user_or_entity?(:tasklist_block, memex_owner) &&
      (!GitHub.flipper[:memex_table_without_limits].enabled?(this_memex) ||
      GitHub.flipper[:memex_mwl_allow_tasklist_columns].enabled?(this_memex))
  end

  def issue_types_enabled?
    T.bind(self, MustBeUsedInApplicationController)
    return @issue_types_enabled if defined?(@issue_types_enabled)
    @issue_types_enabled = current_user && memex_owner&.issue_types_enabled?
  end

  def sub_issues_enabled?
    T.bind(self, MustBeUsedInApplicationController)
    return @sub_issues_enabled if defined?(@sub_issues_enabled)
    @sub_issues_enabled = SubIssuesFeature.enabled?(memex_owner, actor: current_user) || SubIssuesFeature.enabled?(this_memex, actor: current_user)
  end

  def memex_status_updates_notifications_enabled?
    T.bind(self, MustBeUsedInApplicationController)
    @memex_status_updates_notifications_enabled ||= feature_enabled_globally_or_for_current_user_or_entity?(:memex_status_updates_notifications, memex_owner)
  end

  # Returns true if either memex_paginated_archive or memex_table_without_limits are enabled for this project.
  def memex_paginated_archive_enabled?
    T.bind(self, MustBeUsedInApplicationController)
    return @memex_paginated_archive_enabled if defined?(@memex_paginated_archive_enabled)
    @memex_paginated_archive_enabled = this_memex.memex_paginated_archive_enabled?
  end

  def memex_table_without_limits_enabled?(actor = this_memex)
    T.bind(self, MustBeUsedInApplicationController)
    return @memex_table_without_limits_enabled if defined?(@memex_table_without_limits_enabled)
    @memex_table_without_limits_enabled = !GitHub.flipper[:memex_without_limits_kill_switch].enabled? &&
      GitHub.flipper[:memex_table_without_limits].enabled?(actor)
  end

  def memex_resync_index_enabled?
    T.bind(self, MustBeUsedInApplicationController)
    return @memex_resync_index_enabled if defined?(@memex_resync_index_enabled)
    @memex_resync_index_enabled = feature_enabled_globally_or_for_current_user_or_entity?(:memex_resync_index, memex_owner)
  end

  def memex_mwl_server_group_order_enabled?
    T.bind(self, MustBeUsedInApplicationController)
    return @memex_mwl_server_group_order if defined?(@memex_mwl_server_group_order)
    @memex_mwl_server_group_order = feature_enabled_globally_or_for_current_user?(:memex_mwl_server_group_order)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def excluded_columns_hash
    excluded = {}
    unless tracks_and_tracked_by_enabled?
      excluded.merge!(MemexProjectColumn.data_types.slice("tracks"))
      excluded.merge!(MemexProjectColumn.data_types.slice("tracked_by"))
    end

    unless issue_types_enabled?
      excluded.merge!(MemexProjectColumn.data_types.slice("issue_type"))
    end

    unless sub_issues_enabled?
      excluded.merge!(MemexProjectColumn.data_types.slice("parent_issue"))
      excluded.merge!(MemexProjectColumn.data_types.slice("sub_issues_progress"))
    end

    excluded
  end

  sig { params(columns: T::Enumerable[MemexProjectColumn]).returns(T::Enumerable[MemexProjectColumn]) }
  def remove_excluded_columns(columns)
    to_exclude = excluded_columns_hash
    columns.reject { |c| to_exclude.key?(c.data_type) }
  end

  def user_has_read_access_if_this_memex_present
    user_has_read_access if this_memex.present?
  end

  def user_has_read_access
    T.bind(self, MustBeUsedInApplicationController)
    render_404 unless this_memex.viewer_can_read?(current_user)
  end

  def user_has_write_access
    T.bind(self, MustBeUsedInApplicationController)
    render_404 unless this_memex.viewer_can_write?(current_user)
  end

  def user_has_admin_access
    T.bind(self, MustBeUsedInApplicationController)
    head(:forbidden) unless this_memex.viewer_is_admin?(current_user)
  end

  sig { returns(T.nilable(Organization)) }
  def memex_owner
    # todo: we are using T.unsafe here since we know that `this_organization` should exist
    # wherever this is used, but we don't have a class/interface that defines it
    # specifically. We should add that class/interface and use it here, like:
    # `T.bind(self, T.all(MemexesHelper, HasThisOrganization))`
    T.unsafe(self).this_organization
  end

  def get_suggestions(suggestion_type, target)
    T.bind(self, MustBeUsedInApplicationController)
    case suggestion_type
    when "assignees"
      sorted_assignees = target.sorted_assignees_list(
        current_user: current_user).map do |user|
        user.memex_suggestion_hash(selected: target.assigned_to?(user))
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
      issues_domain.issue_types.by_organization(repo.owner_id).map do |issue_type|
        issue_type.memex_suggestion_hash(selected: target.issue_type_id == issue_type.id)
      end
    else
      raise "Unsupported suggestion type: #{suggestion_type}"
    end
  end
end
