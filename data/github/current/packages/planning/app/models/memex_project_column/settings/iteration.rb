# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Settings::Iteration
  include GitHub::Memoizer
  include ActiveModel::Validations
  include MemexProjectColumn::Interface::Groupable::Metadata
  include MemexProjectColumn::Interface::Sliceable::Metadata

  class UnparseableDateError < StandardError; end

  sig { returns(String) }
  attr_reader :id

  sig { returns(T.nilable(String)) }
  attr_reader :title

  sig { returns(T.nilable(String)) }
  attr_reader :title_html

  sig { returns(T.nilable(String)) }
  attr_reader :start_date

  sig { returns(T.nilable(Integer)) }
  attr_reader :duration

  ID_REGEX = /\A[a-f0-9]{8}\z/

  # Pattern for checking if a date string follows the ISO 8601 date format: YYYY-MM-DD.
  # Technically, ISO 8601 format could be more complicated than this, but we don't support anything beyond
  # this format on the client-side anyway.
  ISO_DATE_REGEX = /\A\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])\z/

  validates :id, format: { with: ID_REGEX }, allow_blank: false
  validates :title, presence: true, length: { maximum: 500 }
  validates :start_date, presence: true, format: { with: ISO_DATE_REGEX }
  # The duration of the iteration as it can cause a RangeError on the client
  # In the client it can only be set to a maximum of 99 weeks, so this can only be done via the API
  validates :duration, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 9_999_999 }
  validate :start_date_parseable

  sig { params(config: T::Hash[Symbol, T.untyped]).void }
  def initialize(config)
    @id = T.let(config[:id].presence || SecureRandom.hex(4), String)
    @title = T.let(config[:title], T.nilable(String))
    @title_html = T.let(((config[:title_html] || title_to_html) if @title), T.nilable(String))
    @start_date = T.let(config[:start_date], T.nilable(String))
    @duration = T.let(as_int(config[:duration]), T.nilable(Integer))
  end

  # Public: the public attributes of this object as a hash with indifferent access.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def attributes
    {
      id: @id,
      title: @title,
      title_html: @title_html.presence || title_to_html,
      start_date: @start_date,
      duration: @duration,
    }.compact.with_indifferent_access
  end
  alias_method :group_metadata, :attributes
  alias_method :slice_metadata, :attributes

  # Public: a predicate method for determining if the iteration is complete. To
  # be complete, the current day must be later than or equal to the start_date
  # and greater than the end date.
  sig { returns(T::Boolean) }
  def completed?
    Date.current > end_date
  end

  # Public: a predicate method for determining if the iteration is the current
  # iteration. To be current, the current day must be later than or equal to the
  # start_date and less than the end date.
  sig { returns(T::Boolean) }
  def current?
    started? && !completed?
  end

  # Public: the date that an iteration ends. The end date is computed by adding
  # the duration (number of days) to the start date, and then subtracting 1.
  # We subtract 1 because the end date is inclusive, so we don't actually want
  # to include the full duration in the range.
  # For example a for a start_date of Jan 1, and a duration of 2 days,
  # the end_date should be Jan 2, _not_ Jan 3.
  sig { returns(Date) }
  def end_date
    parsed_start.next_day((@duration || 1) - 1)
  end

  sig { returns(Date) }
  memoize def parsed_start
    raise UnparseableDateError unless @start_date
    begin
      Date.parse(@start_date)
    rescue ArgumentError
      raise UnparseableDateError
    end
  end

  private

  sig { returns(T::Boolean) }
  def started?
    Date.current >= parsed_start
  end

  sig { params(entry: T.nilable(T.any(String, Integer))).returns(T.nilable(Integer)) }
  def as_int(entry)
    return if entry.nil?
    return unless entry.respond_to?(:to_i)

    entry.to_i
  end

  sig { void }
  def start_date_parseable
    Date.parse(start_date || "")
  rescue ArgumentError
    errors.add(:start_date, "not a recognized date format")
  end

  sig { returns(String) }
  def title_to_html
    GitHub::Goomba::MemexTextColumnPipeline.to_html(@title)
  end
end
