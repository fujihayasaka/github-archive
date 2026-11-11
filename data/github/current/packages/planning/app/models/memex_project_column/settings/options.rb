# typed: true
# frozen_string_literal: true

class MemexProjectColumn::Settings::Options
  include ActiveModel::Validations
  include ActionView::Helpers::TextHelper

  OPTION_LIMIT = 100

  attr_reader :options

  validate :each_option_is_valid
  validate :ids_are_unique
  validate :number_of_options_is_within_limit
  delegate :empty?, to: :options

  def initialize(options)
    @options = options.map do |option_entry_args|
      MemexProjectColumn::Settings::OptionEntry.new(option_entry_args.with_indifferent_access)
    end
  end

  def serialize
    return @serialized if defined?(@serialized)
    @serialized = @options.map(&:attributes)
  end

  def index(&block)
    @options.index(&block)
  end

  def delete_at(index)
    @options.delete_at(index)
  end

  def map(&block)
    @options = @options.map(&block)

    self
  end

  def find(&block)
    @options.find(&block)
  end

  def except(&block)
    @options = @options.reject(&block)

    self
  end

  def insert(index, option)
    @options.insert(index || -1, option)

    self
  end

  def compact
    @options = @options.compact

    self
  end

  private

  def each_option_is_valid
    @options.each do |opt|
      unless opt.valid?
        opt.errors.full_messages.each { |msg| errors.add(:option, msg.downcase) }
      end
    end
  end

  def number_of_options_is_within_limit
    unless @options.length <= OPTION_LIMIT
      errors.add(:options, "cannot contain more than #{pluralize(OPTION_LIMIT, "entry")}")
    end
  end

  def ids_are_unique
    validate_unique(:id, @options.map(&:id))
  end

  def validate_unique(name, values)
    unless values.uniq.length == values.length
      errors.add(:option, "#{name} must be unique")
    end
  end
end
