# typed: true
# frozen_string_literal: true

class MemexProjectView < ApplicationRecord::Domain::Memexes
  extend T::Helpers
  include GitHub::Validations
  include GitHub::Prioritizable
  include Instrumentation::Model
  include ContextualActor
  include Sequence::Context

  attribute :filter, StringFromBinary.new
  attribute :name, StringFromBinary.new

  MAX_BIGINT_VALUE = 9_223_372_036_854_775_807
  NAME_BYTESIZE_LIMIT = 128
  FILTER_CHARACTERS_LIMIT = 256
  JSON_BYTESIZE_LIMIT = ([MAX_BIGINT_VALUE, "desc"] * 50).to_json.bytesize
  LAYOUT_SETTINGS_JSON_BYTESIZE_LIMIT = 4096
  MAX_VIEW_COUNT = 50
  MIN_COLUMN_WIDTH = 1
  MAX_COLUMN_WIDTH = 10000

  SORT_BY_DIRECTIONS = %w[asc desc].freeze
  SORT_BY_ERROR = "must be a list of [field_id, \"asc\" | \"desc\"]"

  DEFAULT_LAYOUT_SETTINGS = {}.freeze
  LAYOUT_SETTINGS_SUPPORTED_KEYS = %w[table board roadmap]
  TABLE_LAYOUT_SETTINGS_SUPPORTED_KEYS = %w[column_widths]
  BOARD_LAYOUT_SETTINGS_SUPPORTED_KEYS = %w[column_limits]
  ROADMAP_LAYOUT_SETTINGS_SUPPORTED_KEYS = %w[date_fields zoom_level column_widths marker_fields]
  ROADMAP_LAYOUT_ZOOM_LEVELS = %w[month quarter year]
  SLICE_BY_SUPPORTED_KEYS = %w[field filter panel_width]
  SLICE_BY_SUPPORTED_COLUMNS = %w[tracked_by single_select iteration assignees labels milestone repository text number date issue_type parent_issue]

  LAYOUT_SETTINGS_SCHEMA_PATH = File.join(Rails.root, "packages/planning/app/models/memex_project_view/schema/v1/layout_settings.json")

  belongs_to :memex_project, inverse_of: :memex_project_views, touch: true
  belongs_to :creator, class_name: "User"

  prioritizable_by subject: :itself, context: :memex_project

  # Can't use ":table" as a key, as it's reserved by ActiveRecord.
  # Can't remove deprecated layouts to maintain enum values.
  enum :layout, [:table_layout, :board_layout, :list_layout, :deprecated_timeline_layout, :roadmap_layout], validate: { message: "'%{value}' is not a valid layout" }

  validates :creator, presence: true, on: :create
  validates :filter,
    length: { maximum: FILTER_CHARACTERS_LIMIT }
  validate :validate_horizontal_group_by
  validate :validate_vertical_group_by
  validates :layout, presence: true
  validates :memex_project, presence: true, on: :create
  validates :name,
    presence: true,
    bytesize: { maximum: NAME_BYTESIZE_LIMIT },
    unicode: true
  validates :number,
    presence: true,
    numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :memex_project_id },
    on: :create
  validates :priority,
    uniqueness: { scope: :memex_project_id, allow_nil: true },
    numericality: {
      less_than_or_equal_to: GitHub::Prioritizable::MAX_PRIORITY_VALUE,
      greater_than_or_equal_to: 0,
      allow_nil: true,
    }

  validate :validate_sort_by
  validate :validate_visible_fields
  validate :validate_view_count
  validate :validate_aggregation_settings
  validate :validate_layout_settings
  validate :validate_slice_by

  before_validation :set_defaults
  before_validation :set_default_vertical_group_by
  before_validation :set_default_aggregation_settings
  before_validation :set_default_layout_settings
  before_validation :set_default_slice_by
  before_validation :set_number, on: :create
  before_validation :set_name, on: :create

  scope :with_layouts, ->(included_layouts) { where(layout: included_layouts) }

  after_commit :instrument_creation, on: :create
  after_commit :instrument_update, on: :update
  after_destroy_commit :instrument_destroy

  # Initialize a MemexProjectView with default values. Useful for populating a
  # new Memex project view.
  #
  # Returns MemexProjectView
  def self.new_with_defaults
    new(
      id: 1,
      number: 1,
      name: "View 1",
      group_by: [],
      vertical_group_by: [],
      sort_by: [],
      visible_fields: [],
      filter: nil,
      layout: :table_layout,
      created_at: Time.zone.now,
      updated_at: Time.zone.now,
      aggregation_settings: {
        hide_items_count: false,
        sum: []
      },
      layout_settings: DEFAULT_LAYOUT_SETTINGS.deep_dup,
      slice_by: {},
    ).tap do |view|
      view.readonly!
    end
  end

  # When a column is destroyed or made not visible, remove it from any relevant
  # fields on the view.
  def remove_column!(column)
    if column_visible?(column)
      self.visible_fields = visible_fields.reject { |id| id == column.id }
    end

    if column_grouped?(column)
      self.group_by = group_by.reject { |id| id == column.id }
    end

    if column_vertical_grouped?(column)
      self.vertical_group_by = vertical_group_by.reject { |id| id == column.id }
    end

    if column_sorted?(column)
      self.sort_by = sort_by.reject { |id,| id == column.id }
    end

    if column_summed?(column)
      self.aggregation_settings["sum"] = aggregation_settings["sum"].reject { |id| id == column.id }
    end

    if column_sliced?(column)
      self.slice_by = {}
    end

    # Assign layout settings to a variable so we can do flow analysis
    layout_settings = self.layout_settings
    if column_in_roadmap_date_fields?(column) && layout_settings&.dig("roadmap", "date_fields")
      layout_settings["roadmap"]["date_fields"] = layout_settings["roadmap"]["date_fields"].reject { |id| id == column.id }
    end

    if column_in_roadmap_marker_fields?(column) && layout_settings&.dig("roadmap", "marker_fields")
      layout_settings["roadmap"]["marker_fields"] = layout_settings["roadmap"]["marker_fields"].reject { |id| id == column.id }
    end

    if column_has_width_for_layout?(column, "table")
      remove_width_column_for_layout(column, "table")
    end

    if column_has_width_for_layout?(column, "roadmap")
      remove_width_column_for_layout(column, "roadmap")
    end

    if column_has_limits_for_board?(column)
      remove_column_limits_for_board(column)
    end

    if changed?
      reset_project_columns
      save!
    end
  end

  def make_column_visible!(column)
    if !column_visible?(column)
      reset_project_columns
      update!(visible_fields: visible_fields.push(column.id))
    end
  end

  def column_grouped?(column)
    group_by.include?(column.id)
  end

  def column_vertical_grouped?(column)
    vertical_group_by&.include?(column.id)
  end

  def column_sorted?(column)
    sort_by.any? { |id, _direction| id == column.id }
  end

  def column_visible?(column)
    visible_fields.include?(column.id)
  end

  def column_sliced?(column)
    slice_by&.dig("field") == column.id
  end

  def column_summed?(column)
    aggregation_settings["sum"].any? { |id, _direction| id == column.id } if aggregation_settings && aggregation_settings["sum"].present?
  end

  def column_in_roadmap?(column)
    column_in_roadmap_date_fields?(column) || column_in_roadmap_marker_fields?(column)
  end

  def column_in_roadmap_date_fields?(column)
    layout_settings&.dig("roadmap", "date_fields")&.include?(column.id)
  end

  def column_in_roadmap_marker_fields?(column)
    layout_settings&.dig("roadmap", "marker_fields")&.include?(column.id)
  end

  def column_has_width_for_layout?(column, layout)
    layout_settings&.dig(layout, "column_widths")&.keys&.include?(column.id.to_s)
  end

  def column_has_limits_for_board?(column)
    layout_settings&.dig("board", "column_limits")&.keys&.include?(column.id.to_s)
  end

  def remove_width_column_for_layout(column, layout)
    layout_settings&.dig(layout, "column_widths").delete(column.id.to_s)
  end

  def remove_column_limits_for_board(column)
    layout_settings&.dig("board", "column_limits").delete(column.id.to_s)
  end

  def update_column_order!
    return unless (project = memex_project)

    visible_fields.sort_by! do |field_id|
      project.memex_project_columns.find(field_id).position
    end

    if changed?
      save!
    end
  end

  # Retrieves the `MemexProjectColumn` objects that are visible in this view.
  #
  # This is different from `visible_fields` (that attribute actually contains
  # IDs, not objects).
  #
  # Returns Array<MemexProjectColumn>
  def visible_columns
    memex_project&.memex_project_columns&.find_all { |c| visible_fields.include?(c.id) } || []
  end

  def to_hash
    # Assign layout settings to a variable so we can do flow analysisc
    current_layout_settings = self.layout_settings
    {
      id: id,
      number: number,
      name: name,
      groupBy: group_by,
      sortBy: sort_by,
      visibleFields: visible_fields,
      filter: filter,
      layout: layout,
      priority: priority,
      createdAt: created_at&.utc&.iso8601,
      updatedAt: updated_at&.utc&.iso8601,
      verticalGroupBy: vertical_group_by,
      aggregationSettings: {
        hideItemsCount: aggregation_settings ? aggregation_settings["hide_items_count"] : false,
        sum: aggregation_settings ? aggregation_settings["sum"] : [],
      },
      layoutSettings: current_layout_settings ? current_layout_settings.to_hash.deep_transform_keys { |k| k.to_s.camelize(:lower) } : {},
      sliceBy: slice_by ? slice_by.to_hash.deep_transform_keys { |k| k.to_s.camelize(:lower) } : {},
    }
  end

  def destroy
    # If the project is in the process of being destroyed, we can call the
    # normal #destroy method.
    return super unless (project = memex_project)

    # Lock all views for update for the project when destroying a view. This
    # allows us to ensure that a project always has at least one view.
    MemexProject.transaction do
      select_sql = Arel.sql(<<-SQL, memex_project_id: project.id)
        SELECT COUNT(*) FROM memex_project_views WHERE memex_project_views.memex_project_id = :memex_project_id FOR UPDATE
      SQL

      count = self.class.connection.select_all(select_sql).to_a.first["COUNT(*)"]

      if count <= 1
        errors.add(:base, "Cannot destroy the last remaining view of a project")
        false
      else
        super
      end
    end
  end

  def sequence_context_type
    self.class.name
  end

  def sequence_context_id
    memex_project_id
  end

  def platform_type_name
    @platform_type_name || "ProjectV2View"
  end

  def platform_type_name=(name)
    @platform_type_name = name
  end

  # Public: Retrieve the view's group by column
  #
  # Returns a Promise of either a MemexProjectColumn or nil.
  def async_group_by_column
    layout = layout_parameter
    return Promise.resolve(nil) if layout == "table" && group_by.empty?

    async_memex_project.then do |memex|
      group_by_id = case layout
      when "board"
        # note that Object#blank? was explicitly used to help prevent against vertical_group_by being
        # potentially nil.
        if vertical_group_by.blank?
          return Promise.resolve(T.must(memex).status_column)
        end

        vertical_group_by.first
      when "table"
        group_by.first
      end

      T.must(memex).async_memex_project_columns.then do |columns|
        columns.find { |c| c.id == group_by_id }
      end
    end
  end

  # Public: Retrieve the view's sort by column and direction
  #
  # Returns a Promise of either a Hash or nil.
  def async_sort_by_column
    return Promise.resolve(nil) unless sort_by.present?
    async_memex_project.then do |project|
      next unless project

      project.async_memex_project_columns.then do |columns|
        sort_by_id, sort_by_direction = sort_by.first
        sort_by_column = columns.find { |c| c.id == sort_by_id }

        {
          column: sort_by_column,
          direction: sort_by_direction
        }
      end
    end
  end

  sig { returns(Promise[T::Array[T::Hash[Symbol, T.untyped]]]) }
  def async_sort_by_columns
    return Promise.resolve(Array.new) unless sort_by.present?

    async_memex_project.then do |project|
      next unless project

      project.async_memex_project_columns.then do |columns|
        next unless columns.present?

        columns_by_id = columns.index_by(&:id)

        sort_by.filter_map do |(column_id, direction)|
          next unless (column = columns_by_id[column_id]).present?
          { column:, direction: }
        end
      end
    end
  end


  sig { returns MemexProjectColumn::Interface::Sortable::Params }
  def sort_params
    # The self.sort_by is stored as an array of tuples, where the first
    # item in the tuple is the column id for the field, and the second
    # item is the direction "asc" or "desc"
    (self.sort_by || []).map { |s| MemexProjectColumn::Interface::Sortable::Param.new(column_id: T.must(s[0]), direction: s[1]) }
  end

  # Public: Retrieve the view's group by field synthetic id.
  # Returns the synthetic_id or nil if not using horizontal grouping.
  sig { returns(T.nilable(T.any(String, Integer))) }
  def group_by_synthetic_id
    return unless self.group_by.present?

    group_by_field_id = self.group_by.first
    group_by_field = self.memex_project&.columns&.find { |c| c.id == group_by_field_id }
    group_by_field&.synthetic_id
  end

  private def set_number
    return if number
    return unless memex_project

    unless Sequence.exists?(self)
      Sequence.create(self, self.class.where(memex_project_id: memex_project_id).maximum(:number) || 0)
    end

    self.number = Sequence.next(self)
  end

  private def reset_project_columns
    # The view reads this in validations, so we reset it. Not necessary when
    # we remove double-writes.
    T.must(memex_project).memex_project_columns.reset
  end

  private def set_name
    return if name
    return unless number
    self.name = "View #{number}"
  end

  private def validate_view_count
    return unless (project = memex_project)

    # This is best-effort, as concurrent saves could exceed this limit.
    if project.memex_project_views.size > MAX_VIEW_COUNT
      errors.add(:base, "Views are limited to #{MAX_VIEW_COUNT} per project")
    end
  end

  private def validate_horizontal_group_by
    validate_group_by(:group_by)
  end

  private def validate_vertical_group_by
    validate_group_by(:vertical_group_by)
  end

  private def validate_group_by(group_by_field)
    return unless is_array?(group_by_field)
    return unless is_all_integers?(group_by_field)
    return unless is_within_bytesize_limit?(group_by_field)
    nil unless ensure_project_column_ids(group_by_field)
  end

  private def validate_sort_by
    return unless is_array?(:sort_by)
    return unless is_within_bytesize_limit?(:sort_by)

    unless sort_by.all? { |spec| valid_sort_by_spec?(spec) }
      errors.add(:sort_by, SORT_BY_ERROR)
      return
    end

    nil unless ensure_project_column_ids(:sort_by, -> { sort_by.map(&:first) })
  end

  private def valid_sort_by_spec?(spec)
    spec.is_a?(Array) and
      spec.size == 2 and
      spec[0].is_a?(Integer) and
      SORT_BY_DIRECTIONS.include?(spec[1])
  end


  private def normalize_column_widths(layout)
    return unless (project = memex_project)

    all_column_ids = Set.new(project.memex_project_columns.pluck(:id))
    get_attribute([:layout_settings, layout, "column_widths"]).filter { |key, _value| all_column_ids.include? key.to_i }.transform_values { |v| v.to_i if v }
  end

  private def validate_visible_fields
    return unless is_array?(:visible_fields)
    return unless is_all_integers?(:visible_fields)
    return unless is_within_bytesize_limit?(:visible_fields)
    nil unless ensure_project_column_ids(:visible_fields)
  end

  private def validate_aggregation_settings
    return unless is_within_bytesize_limit?(:aggregation_settings)

    sum_column_ids = self.aggregation_settings["sum"]
    unless sum_column_ids.is_a?(Array)
      errors.add(:aggregation_settings, "sum must be an array")
      return false
    end

    return unless (project = memex_project)
    number_columns = project.memex_project_columns.select { |column| column[:data_type] == "number" }
    number_column_ids = Set.new(number_columns.pluck(:id))
    self.aggregation_settings["sum"] = sum_column_ids.filter { |col,| number_column_ids.include? col }
  end

  private def validate_board_column_limits
    column_limits_attribute = [:layout_settings, "board", "column_limits"]
    return false unless is_hash?(column_limits_attribute)
    return false unless get_attribute(column_limits_attribute).all? do |(key)|
      column_limit_for_field_id_attribute = column_limits_attribute.clone.concat([key])
      return false unless is_hash?(column_limit_for_field_id_attribute)
      return false unless get_attribute(column_limit_for_field_id_attribute).all? do |option_id, limit_value|
        return true if !limit_value
        column_limit_option_id_attribute_name = get_attribute_name(column_limit_for_field_id_attribute.clone.concat([option_id]))

        unless limit_value.is_a?(Integer)
          errors.add(column_limit_option_id_attribute_name, "must be a number")
          return false
        end

        unless limit_value >= 0
          errors.add(column_limit_option_id_attribute_name, "must be greater than or equal to 0")
          return false
        end

        true
      end
      true
    end
    true
  end

  private def normalize_board_column_limits
    return unless (project = memex_project)
    all_column_ids = Set.new(project.memex_project_columns.pluck(:id))
    column_limits = get_attribute([:layout_settings, "board", "column_limits"])
    filtered_limits = column_limits.filter { |key, _value| all_column_ids.include? key.to_i }

    filtered_limits.reduce({}) do |memo, (key, value)|
      if column = project.memex_project_columns.find(key)
        if column.single_select?
          # we reload the column model here to ensure that the column model has the latest settings, as in some cases
          # we maybe reading default options from a stale cache
          valid_column_option_ids = column.reload.settings["options"].map { |opt| opt["id"] }
          memo[key.to_s] = value.compact.filter { |key| valid_column_option_ids.include?(key) }.transform_values(&:to_i) if value && value.is_a?(Hash)
        elsif column.iteration?
          valid_column_option_ids = column.settings_all_iterations.map { |opt| opt["id"] }
          memo[key.to_s] = value.compact.filter { |key| valid_column_option_ids.include?(key) }.transform_values(&:to_i) if value && value.is_a?(Hash)
        end
      end
      memo
    end
  end

  def self.layout_settings_schema
    schema = JsonSchema.parse!(JSON.parse(File.read(LAYOUT_SETTINGS_SCHEMA_PATH)))
    schema.expand_references!
    schema
  end

  private def validate_layout_settings
    return unless (project = memex_project)
    # Assign layout settings to a variable so we can do flow analysis
    layout_settings = self.layout_settings
    return unless layout_settings.present?
    return unless is_within_layout_settings_bytesize_limit?(:layout_settings)

    valid, validation_errors = MemexProjectView.layout_settings_schema.validate(layout_settings, fail_fast: true)

    if !valid
      validation_errors.each do |schema_validation_error|
        error_path = [:layout_settings].concat(schema_validation_error.path.slice(1..)).join(".")
        errors.add(error_path, schema_validation_error.message)
        if schema_validation_error.sub_errors.present?
          schema_validation_error.sub_errors.each do |sub_validations|
            sub_validations.each do |sub_validation|
              errors.add(error_path, sub_validation.message)
            end
          end
        end
      end
      return
    end

    normalize_layout_settings
  end


  private def normalize_layout_settings
    return unless (project = memex_project)
    # Assign layout settings to a variable so we can do flow analysis
    layout_settings = self.layout_settings
    return unless layout_settings.present?
    if layout_settings["table"].present?
      if layout_settings["table"]["column_widths"].present?
        layout_settings["table"]["column_widths"] = normalize_column_widths("table")
      end
    end

    if layout_settings["board"].present?
      if layout_settings["board"]["column_limits"].present?
        layout_settings["board"]["column_limits"] = normalize_board_column_limits
      end
    end

    if layout_settings["roadmap"].present?
      if layout_settings["roadmap"]["date_fields"].present?
        date_columns = project.memex_project_columns.select { |column| column.date? or column.iteration? }
        date_column_ids = Set.new(date_columns.pluck(:id))
        layout_settings["roadmap"]["date_fields"] = layout_settings["roadmap"]["date_fields"].filter { |col| date_column_ids.include? col or col == "none" }
      end

      if layout_settings["roadmap"]["marker_fields"].present?
        date_columns = project.memex_project_columns.select { |column| column.date? or column.iteration? or column.milestone? }
        date_column_ids = Set.new(date_columns.pluck(:id))
        layout_settings["roadmap"]["marker_fields"] = layout_settings["roadmap"]["marker_fields"].filter { |col| date_column_ids.include?(col) }
      end

      if layout_settings["roadmap"]["column_widths"].present?
        layout_settings["roadmap"]["column_widths"] = normalize_column_widths("roadmap")
      end
    end
  end

  private def validate_slice_by
    return unless (project = memex_project)
    return unless is_hash?(:slice_by)
    return unless is_within_bytesize_limit?(:slice_by)
    return unless has_only_allowed_keys?(:slice_by, MemexProjectView::SLICE_BY_SUPPORTED_KEYS)

    if slice_by["filter"].present?
      unless slice_by["filter"].is_a?(String)
        errors.add(get_attribute_name([:slice_by, "filter"]), "must be a string")
        return false
      end

      unless slice_by["filter"].length <= MemexProjectView::FILTER_CHARACTERS_LIMIT
        errors.add(get_attribute_name([:slice_by, "filter"]), "is too long (maximum is #{MemexProjectView::FILTER_CHARACTERS_LIMIT} characters)")
        return false
      end
    end

    if slice_by["field"].present?
      if !slice_by["field"].is_a?(Integer)
        errors.add(get_attribute_name([:slice_by, "field"]), "must be an integer")
        return false
      end

      slice_columns = project.memex_project_columns.select { |column| MemexProjectView::SLICE_BY_SUPPORTED_COLUMNS.include?(column.data_type) }
      slice_columns_ids = Set.new(slice_columns.pluck(:id))

      if !slice_columns_ids.include?(slice_by["field"])
        slice_by.delete("field")
      end
    end

    if !slice_by["field"].present?
      self.slice_by = {}
    end

    if slice_by["panel_width"].present?
      if !slice_by["panel_width"].is_a?(Integer)
        slice_by.delete("panel_width")
      end
    end
  end

  private def is_array?(attribute)
    unless get_attribute(attribute).is_a?(Array)
      errors.add(get_attribute_name(attribute), "must be an array")
      return false
    end

    true
  end

  private def has_length?(attribute, length)
    # if length is range, check if attribute is within range
    if length.is_a?(Range)
      unless length.include?(get_attribute(attribute).length)
        errors.add(get_attribute_name(attribute), "must have length in the range #{length}")
        return false
      end
    else
      unless get_attribute(attribute).length == length
        errors.add(get_attribute_name(attribute), "must have length #{length}")
        return false
      end
    end
    true
  end

  private def is_hash?(attribute)
    unless get_attribute(attribute).is_a?(Hash)
      errors.add(get_attribute_name(attribute), "must be a hash")
      return false
    end

    true
  end

  private def is_all_integers?(attribute)
    unless get_attribute(attribute).is_a?(Array) && get_attribute(attribute).all? { |e| e.is_a?(Integer) }
      errors.add(get_attribute_name(attribute), "must be an array of integers")
      return false
    end

    true
  end

  private def has_only_allowed_keys?(attribute, allowed_keys)
    hash = get_attribute(attribute)
    return false unless hash.is_a?(Hash)

    unsupported_entries = hash.except(*allowed_keys)
    if unsupported_entries.present?
      errors.add(get_attribute_name(attribute), "contains unsupported keys: #{unsupported_entries.keys.join(", ")}")
      return false
    end

    true
  end

  private def is_within_bytesize_limit?(attribute)
    if send(attribute).to_json.bytesize > JSON_BYTESIZE_LIMIT
      errors.add(attribute, "must be fewer than #{JSON_BYTESIZE_LIMIT} bytes as JSON")
      return false
    end

    true
  end

  private def is_within_layout_settings_bytesize_limit?(attribute)
    if send(attribute).to_json.bytesize > LAYOUT_SETTINGS_JSON_BYTESIZE_LIMIT
      errors.add(attribute, "must be fewer than #{LAYOUT_SETTINGS_JSON_BYTESIZE_LIMIT} bytes as JSON")
      return false
    end

    true
  end

  private def get_attribute(path)
    if path.is_a?(Array)
      # get the first hash from the current scope, then dig into the hash for the rest
      send(path.first).dig(*path.drop(1))
    else
      send(path)
    end
  end

  private def get_attribute_name(path)
    path.is_a?(Array) ? path.join(".") : path
  end

  private def ensure_project_column_ids(attribute, get_ids = -> { send(attribute) })
    return unless (project = memex_project)

    all_column_ids = Set.new(project.memex_project_columns.pluck(:id))
    value = self.send(attribute).filter { |col,| all_column_ids.include? col }

    self.write_attribute(attribute, value)
  end

  private def set_defaults
    return unless new_record?

    self.layout ||= :table_layout
    self.group_by ||= []
    self.sort_by ||= []

    if !visible_fields || visible_fields.empty?
      self.visible_fields = default_visible_field_ids
    end
  end

  private def set_default_vertical_group_by
    self.vertical_group_by ||= []
  end

  private def set_default_slice_by
    self.slice_by ||= {}
  end

  private def set_default_aggregation_settings
    self.aggregation_settings ||= {}
    self.aggregation_settings["hide_items_count"] ||= false
    self.aggregation_settings["sum"] ||= []
  end

  private def set_default_layout_settings
    self.layout_settings ||= DEFAULT_LAYOUT_SETTINGS.deep_dup
  end

  private def default_visible_field_ids
    return [] unless (project = memex_project)
    visible_system_column_names = MemexProjectColumn::SYSTEM_DEFINED_COLUMNS.select { |c| c[:default_column] }
      .map { |c| c[:name] }.to_set
    project.columns.select { |c| !c.user_defined? && visible_system_column_names.include?(c.name) }.map(&:id).compact
  end

  private def instrument_creation
    instrument_view_on(:create)
  end

  private def instrument_update
    instrument_view_on(:update)
  end

  private def instrument_destroy
    instrument_view_on(:delete)
  end

  private def instrument_view_on(key)
    raise ArgumentError.new("#{key} is not a valid argument") unless key.is_a?(Symbol)
    instrument key, prefix: "project_view", project_kind: "MemexProject"

    GlobalInstrumenter.instrument("memex_project_view.#{key}", {
      project: memex_project,
      actor: actor,
      project_view: self
    })
  end

  private def event_payload
    payload = {
      view: self,
      actor: actor,
      project: memex_project,
      project_number: memex_project&.number,
      public_project: memex_project&.public?,
    }

    if owner = memex_project&.owner
      payload[owner.event_prefix] = owner
    end

    payload
  end

  def layout_parameter
    case layout
    when "table_layout"
      "table"
    when "board_layout"
      "board"
    when "list_layout"
      "list"
    when "deprecated_timeline_layout"
      "roadmap"
    when "roadmap_layout"
      "roadmap"
    end
  end

  def self.is_valid_layout_parameter(layout_parameter)
    %w[
      table
      board
      list
      roadmap
    ].include?(layout_parameter)
  end
end
