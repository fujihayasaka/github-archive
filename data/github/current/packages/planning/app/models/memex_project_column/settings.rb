# typed: true
# frozen_string_literal: true

class MemexProjectColumn::Settings
  include ActiveModel::Validations

  class InitializationError < ArgumentError; end

  attr_reader :width,
              :options,
              :configuration,
              :progress_configuration

  DEFAULT_COLOR = "GRAY".freeze
  ALLOWED_COLORS = [DEFAULT_COLOR, "BLUE", "GREEN", "ORANGE", "RED", "PINK", "PURPLE", "YELLOW"].freeze
  MIN_WIDTH = 1
  MAX_WIDTH = 10000
  SUPPORTED_KEYS = %i(width options configuration progress_configuration)

  validates(
    :width,
    allow_blank: true,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: MIN_WIDTH,
      less_than_or_equal_to: MAX_WIDTH
    }
  )
  validate :no_unsupported_entries
  validate :no_unsupported_entries_for_data_type
  validate :options_are_valid
  validate :configuration_is_valid
  validate :progress_configuration_is_valid

  def initialize(data_type, settings)
    unless settings.is_a?(Hash)
      raise InitializationError, "must provide a hash"
    end

    if settings[:options] && !settings[:options].is_a?(Array)
      raise InitializationError, "options must be an array"
    end

    if settings[:options] && !settings[:options].all? { |o| o.is_a?(Hash) }
      raise InitializationError, "options must be an array of hashes"
    end

    if settings.slice(:options, :configuration, :progress_configuration).keys.length > 1
      raise InitializationError, "cannot provide more than one: options, configuration, and progress_configuration"
    end

    @width = settings[:width] && settings[:width].to_i
    @options = settings[:options] && MemexProjectColumn::Settings::Options.new(settings[:options])
    @configuration = settings[:configuration] && MemexProjectColumn::Settings::Configuration.new(settings[:configuration])
    @progress_configuration = settings[:progress_configuration] && MemexProjectColumn::Settings::ProgressConfiguration.new(settings[:progress_configuration])
    @unsupported_entries = settings.except(*SUPPORTED_KEYS)
    @data_type = data_type.to_sym
  end

  def serialize
    return @serialized if defined?(@serialized)

    @serialized = {
      width: @width,
      options: @options&.serialize,
      configuration: @configuration&.serialize,
      progress_configuration: @progress_configuration&.serialize,
    }.compact.with_indifferent_access
  end

  def add_option(name:, color: nil, description: nil, position: nil)
    @options = options.insert(position, MemexProjectColumn::Settings::OptionEntry.new({ name: name, color: color, description: description })).compact
  end

  def delete_option(option_id)
    option = options.find { |o| o.id == option_id }
    @options = options.except { |o| o.id == option_id } if option
  end

  # https://stackoverflow.com/a/47161783 for insertion fun
  def update_option(option_id, name: nil, color: nil, description: nil, position: nil)
    if previous_index = options.index { |o| o.id == option_id }
      option_to_update = @options.delete_at(previous_index)
      option_to_update.name = name if name
      option_to_update.color = color if color
      option_to_update.description = description if description

      new_position = position || previous_index
      # compact the options in case of a race condition
      # where the provided position is out of bounds and `nil` values are inserted
      # at earlier indexes
      @options = options.insert(new_position, option_to_update).compact
    end
  end

  # Public: when a settings object has configurations and iterations, we will
  # want to ensure that the iterations are properly placed, ordered, and
  # deduped.
  #
  # Returns an instance of Settings
  def allocate_iterations
    return self unless @configuration

    @configuration = Configuration
      .new(@configuration.serialize)
      .partition_iterations

    self
  end

  private

  def no_unsupported_entries
    if @unsupported_entries.present?
      errors.add(:base, "Contains unsupported keys: #{@unsupported_entries.keys.join(", ")}")
    end
  end

  def no_unsupported_entries_for_data_type
    if @data_type != :single_select && @options.present?
      errors.add(:base, "Options key is not supported for #{@data_type} column")
    end
  end

  def options_are_valid
    if @options && !@options.valid?
      @options.errors.full_messages.each { |msg| errors.add(:base, msg) }
    end
  end

  def configuration_is_valid
    if @configuration && !@configuration.valid?
      @configuration.errors.full_messages.each { |msg| errors.add(:base, msg) }
    end
  end

  def progress_configuration_is_valid
    if @progress_configuration && !@progress_configuration.valid?
      @progress_configuration.errors.full_messages.each { |msg| errors.add(:base, msg) }
    end
  end
end
