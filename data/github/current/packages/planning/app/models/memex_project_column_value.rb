# typed: true
# frozen_string_literal: true

class MemexProjectColumnValue < ApplicationRecord::Domain::Memexes
  include GitHub::Memoizer
  include GitHub::Validations
  include ContextualActor
  include Instrumentation::Model
  include ActiveSupport::NumberHelper

  attribute :value, StringFromBinary.new

  # Transient attribute used to disable webhook event instrumentation.
  attr_accessor :disable_webhook_event_instrumentation

  # Transient attribute used to disable hydro event instrumentation.
  sig { returns(T::Boolean) }
  attr_accessor :disable_hydro_event_instrumentation

  # Transient attribute used to track changes to the `json_value` column
  # that are applied via direct SQL update rather than via ActiveRecord.
  #
  # This is the conceptual equivalent of `previous_changes[:json_value]`.
  attr_accessor :previous_json_value

  TEXT_VALUE_BYTESIZE_LIMIT = 1024
  NUMBER_VALUE_SIGNED_INT_LIMIT = 2147483647
  NUMBER_VALUE_PRECISION = 8
  ON_CREATE_INSTRUMENTATION_KEY = "column_value_create"
  ON_UPDATE_INSTRUMENTATION_KEY = "column_value_update"
  ON_DESTROY_INSTRUMENTATION_KEY = "column_value_destroy"

  belongs_to :memex_project_column, inverse_of: :memex_project_column_values
  belongs_to :memex_project_item, inverse_of: :memex_project_column_values, touch: true
  belongs_to :creator, class_name: "User"

  has_one :memex_project, through: :memex_project_column

  before_validation :normalize_generic_column_value
  before_validation :set_memex_project_column_data_type
  before_validation :set_json_value_id

  validates :memex_project_column, presence: true
  validates :memex_project_item, presence: true
  validates :creator, presence: true, on: :create
  validates :value, presence: true
  validates :value, bytesize: { maximum: TEXT_VALUE_BYTESIZE_LIMIT }, unicode: true, if: :text_value?
  validates :value, numericality: { greater_than_or_equal_to: -(NUMBER_VALUE_SIGNED_INT_LIMIT), less_than_or_equal_to: NUMBER_VALUE_SIGNED_INT_LIMIT }, if: :number_value?
  validates :memex_project_column_data_type, presence: true, inclusion: { in: MemexProjectColumn.data_types.values, allow_nil: true }

  validate :value_is_an_allowed_value
  validate :valid_number_precision
  validate :valid_date_format

  # These are hooks to emit Hydro events for column value operations.
  after_commit :instrument_create_event, on: :create
  after_commit :instrument_update_event, on: :update
  after_commit :instrument_destroy_event, on: :destroy, if: :should_instrument_hydro_destroy_event?

  scope :milestone_values, ->(milestone_id) do
    where(
      memex_project_column_data_type: MemexProjectColumn.data_types[:milestone],
      json_value_id: milestone_id
    )
  end

  validates_with MemexProjectColumnValue::JsonValueValidator

  delegate :data_type, :title?, :milestone?, :generic_type?, to: :memex_project_column, allow_nil: true

  def value=(value)
    val = format_value(value)
    super(val)
  end

  def platform_type_name
    @platform_type_name || "ProjectV2ItemFieldValue"
  end

  def platform_type_name=(name)
    @platform_type_name = name
  end

  def async_viewer_can_update?(viewer)
    async_memex_project_item.then do |memex_project_item|
      T.must(memex_project_item).async_viewer_can_update?(viewer)
    end
  end

  def async_readable_by?(viewer)
    async_memex_project_item.then do |memex_project_item|
      T.must(memex_project_item).async_readable_by?(viewer)
    end
  end

  def instrument_create_event
    safe_actor = creator || User.ghost

    # Instrument creation for webhooks via Instrumentation::Model.instrument,
    # which uses the legacy instrumentation service.
    instrument(:create, actor_id: safe_actor.id) if should_instrument_webhook_create_event?

    # Instrument creation for Hydro using the new GlobalInstrumenter directly.
    return unless should_instrument_hydro_event?
    GlobalInstrumenter.instrument "memex_event", {
      actor: safe_actor,
      memex_project_column: memex_project_column,
      memex_project_item: memex_project_item,
      memex_project: memex_project,
      performed_at: Time.current,
      name: ON_CREATE_INSTRUMENTATION_KEY,
      context: self.previous_changes[:json_value]&.to_json,
      value: self.value
    }
  end

  def instrument_update_event
    # Instrument creation for webhooks via Instrumentation::Model.instrument,
    # which uses the legacy instrumentation service.
    instrument(:update) if should_instrument_webhook_update_event?

    # Instrument creation for Hydro using the new GlobalInstrumenter directly.
    return unless should_instrument_hydro_event?
    previous_json_value = self.previous_json_value || previous_changes[:json_value]
    GlobalInstrumenter.instrument "memex_event", {
      actor: actor,
      memex_project_column: memex_project_column,
      memex_project_item: memex_project_item,
      memex_project: memex_project,
      performed_at: Time.current,
      name: ON_UPDATE_INSTRUMENTATION_KEY,
      context: previous_json_value.to_json,
      previous_value: self.previous_changes[:value]&.first,
      value: self.value
    }
  end

  def instrument_destroy_event
    # Instrument creation for webhooks via Instrumentation::Model.instrument,
    # which uses the legacy instrumentation service.
    instrument(:delete) if should_instrument_webhook_destroy_event?

    return unless should_instrument_hydro_event?
    # Instrument creation for Hydro using the new GlobalInstrumenter directly.
    GlobalInstrumenter.instrument "memex_event", {
      actor: actor,
      memex_project_column: memex_project_column,
      memex_project_item: memex_project_item,
      memex_project: memex_project,
      performed_at: Time.current,
      name: ON_DESTROY_INSTRUMENTATION_KEY,
      value: self.value
    }
  end

  # Override ApplicationRecord::Base#reset_memoized_attributes to make sure that we clear memoization variables
  # on reload.
  sig { void }
  def reset_memoized_attributes
    remove_instance_variable(:@insights_entity_org) if defined?(@insights_entity_org)
    remove_instance_variable(:@memex_project) if defined?(@memex_project)
  end

  sig { returns(T.nilable(MemexProject)) }
  def memex_project
    return @memex_project if defined?(@memex_project)
    @memex_project = if association(:memex_project_column).loaded?
      memex_project_column&.memex_project
    elsif association(:memex_project_item).loaded?
      memex_project_item&.memex_project
    else
      super # hit the `has_one :memex_project, through:` relation
    end
  end

  # Implements Instrumentation::Model#event_payload, which is used to generate
  # webhook event payloads via calls to Instrumentation::Model#instrument.
  memoize def event_payload
    organization_id = memex_project&.organization_owner_id
    return unless organization_id

    {
      actor_id: actor.id,
      memex_project_item_id: memex_project_item_id,
      changed_field_id: memex_project_column_id,
      organization_id: organization_id,
      changes: self.previous_changes,
    }
  end

  private

  def should_instrument_webhook_create_event?
    !@disable_webhook_event_instrumentation && event_payload.present?
  end

  def should_instrument_webhook_update_event?
    !@disable_webhook_event_instrumentation &&
      json_value_changed? &&
      event_payload.present?
  end

  def should_instrument_hydro_event?
    !@disable_hydro_event_instrumentation
  end

  def should_instrument_webhook_destroy_event?
    event_payload.present?
  end

  def json_value_changed?
    if memex_project_column_data_type == MemexProjectColumn.data_types[:milestone]
      # While diagnosing https://github.com/github/memex/issues/10167, we observed symptoms in production
      # that previous changes included the `json_value` key even when the contents of that hash had not
      # changed substantively for a milestone. Hence this makes the comparison a bit narrower and more reliable
      # by comparing just the ID values.
      previous_changes.dig(:json_value, 0, :value, :id) != previous_changes.dig(:json_value, 1, :value, :id)
    else
      previous_changes.has_key?(:json_value)
    end
  end

  def normalize_generic_column_value
    return unless generic_type?

    self.value = format_value(self.value)

    return if self.value.nil?
    self.json_value = build_generic_type_json_value(self.value)
  end

  def set_memex_project_column_data_type
    self.memex_project_column_data_type = MemexProjectColumn.data_types[data_type]
  end

  def set_json_value_id
    self.json_value_id = memex_project_column&.json_value_id(json_value)
  end

  def format_value(value)
    return value unless date_value?

    DateTime.parse(value).iso8601
  rescue ArgumentError
    value
  end

  def text_value?
    memex_project_column&.text?
  end

  def number_value?
    memex_project_column&.number?
  end

  def date_value?
    memex_project_column&.date?
  end

  def single_select_value?
    memex_project_column&.single_select?
  end

  def iteration_value?
    memex_project_column&.iteration?
  end

  def value_is_an_allowed_value
    return unless single_select_value? || iteration_value?

    if single_select_value?
      options = memex_project_column&.settings_options || []
      unless options.find { |o| o["id"] == value }
        errors.add(:value, "is not a valid option for this column")
      end
    else
      # handle cases where any of these values are nil and ensure an array is returned
      iterations = [memex_project_column&.settings_iterations, memex_project_column&.settings_completed_iterations].compact.reduce([], :|)
      unless iterations.find { |o| o["id"] == value }
        errors.add(:value, "is not a valid option for this column")
      end
    end
  end

  def valid_number_precision
    return unless number_value?

    unless number_to_rounded(value, precision: NUMBER_VALUE_PRECISION).to_f == value.to_f
      errors.add(:value, "must not exceed precision of #{NUMBER_VALUE_PRECISION}")
    end
  end

  def valid_date_format
    return unless date_value?

    MemexDateTimeFormat.parse(value)
  rescue ArgumentError
    # swipe left, not a valid date
    errors.add(:value, "is not a date")
  end

  def build_generic_type_json_value(value)
    case
    when text_value?
      {
        raw: value,
        html: GitHub::Goomba::MemexTextColumnPipeline.to_html(value)
      }
    when single_select_value?, iteration_value?
      {
        id: value
      }
    when date_value?
      {
        value: value
      }
    when number_value?
      {
        value: value.to_f
      }
    else
      raise NotImplementedError, "Must define column value for generic column of '#{memex_project_column&.data_type}' type"
    end
  end

  # We skip emitting these messages currently
  # to avoid processing these in the live-update
  # stream processor. This could be moved
  # as a consideration in the processor later, but for now this seems fair
  def should_instrument_hydro_destroy_event?
    memex_project_column.present? && !memex_project_column&.destroyed? && memex_project_item.present? && !memex_project_item&.destroyed?
  end
end
