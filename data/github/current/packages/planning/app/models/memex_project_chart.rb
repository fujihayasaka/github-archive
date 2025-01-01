# typed: true
# frozen_string_literal: true

class MemexProjectChart < ApplicationRecord::Domain::Memexes
  include GitHub::Validations
  include Validators
  include Sequence::Context
  include Instrumentation::Model
  include ContextualActor
  extend GitHub::Encoding

  # Private projects owned by users/orgs with free plans can only include a limited number of saved charts.
  LIMITED_CHARTS_LIMIT = 2

  # This value is stored in a varchar(255) column, so account for the space
  # required to store 4-byte characters.
  NAME_CHARACTER_LIMIT = 63
  MAX_CHART_COUNT = 250
  CHART_TYPES = %w[bar column line stacked-area stacked-bar stacked-column].freeze
  SORT_ORDERS = %w[asc desc].freeze
  OPERATIONS = %w[count sum avg min max].freeze
  TIME_PERIODS = %w[2W 1M 3M max custom].freeze
  DEFAULT_PERIOD = "2W"

  belongs_to :memex_project, inverse_of: :charts
  belongs_to :creator, class_name: "User"

  validates :configuration, presence: true, memex_project_chart_configuration: true
  validates :creator, presence: true, on: :create
  validates :memex_project, presence: true, on: :create
  validates :name, presence: true, length: { maximum: NAME_CHARACTER_LIMIT }
  validates :number,
    presence: true,
    numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :memex_project_id },
    on: :create

  validate :chart_can_be_created, on: :create
  validate :validate_chart_count

  before_validation :set_number, on: :create
  before_validation :set_name, on: :create

  after_commit :instrument_creation, on: :create
  after_commit :instrument_update, on: :update
  after_destroy_commit :instrument_destroy

  def to_hash
    {
      name: name,
      number: number,
      configuration: configuration,
    }.compact
  end

  def sequence_context_type
    self.class.name
  end

  def sequence_context_id
    memex_project_id
  end

  private

  def set_number
    return if number
    return unless memex_project

    unless Sequence.exists?(self)
      Sequence.create(
        self,
        self.class.where(memex_project_id: memex_project_id).maximum(:number) || 0,
      )
    end

    self.number = Sequence.next(self)
  end

  def set_name
    return if name
    return unless number
    self.name = "Chart #{number}"
  end

  def validate_chart_count
    return unless (project = memex_project)

    # This is best-effort, as concurrent saves could exceed this limit.
    if project.charts.size > MAX_CHART_COUNT
      errors.add(:base, "Charts are limited to #{MAX_CHART_COUNT} per project")
    end
  end

  def chart_can_be_created
    return unless memex_project
    if memex_project&.has_reached_chart_limit?
      errors.add(:base, "This project is limited to #{LIMITED_CHARTS_LIMIT} custom charts.")
    end
  end

  def instrument_creation
    instrument_chart_on(:create)
  end

  def instrument_update
    instrument_chart_on(:update)
  end

  def instrument_destroy
    instrument_chart_on(:delete)
  end

  def instrument_chart_on(key)
    raise ArgumentError.new("#{key} is not a valid argument") unless key.is_a?(Symbol)

    GlobalInstrumenter.instrument("memex_project_chart.#{key}", {
      project: memex_project,
      actor: actor,
      project_chart: self
    })
  end
end
