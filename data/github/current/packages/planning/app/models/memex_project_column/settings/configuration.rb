# typed: true
# frozen_string_literal: true

class MemexProjectColumn::Settings::Configuration
  include ActiveModel::Validations

  DUPLICATE_ITERATION_MESSAGE = "duplicate_iteration_removed"
  MAX_ITERATION_COUNT_LIMIT = 500

  attr_reader :start_day,
              :duration,
              :iterations,
              :completed_iterations

  validates :start_day, presence: true, numericality: true, inclusion: { in: 1..7 }
  # The duration of the iteration as it can cause a RangeError on the client
  # In the client it can only be set to a maximum of 99 weeks, so this can only be done via the API
  validates :duration, presence: true, numericality: { greater_than: 0,  less_than_or_equal_to: 9_999_999 }
  validate :iterations_are_valid
  validate :completed_iterations_are_valid
  validate :not_too_many_iterations

  def initialize(config)
    @start_day = as_int(config[:start_day])
    @duration = as_int(config[:duration])
    @iterations = Array.wrap(config[:iterations]).map do |iteration|
      MemexProjectColumn::Settings::Iteration.new(iteration.with_indifferent_access)
    end
    @completed_iterations = Array.wrap(config[:completed_iterations]).map do |iteration|
      MemexProjectColumn::Settings::Iteration.new(iteration.with_indifferent_access)
    end
  end

  def serialize
    return @serialized if defined?(@serialized)

    @serialized = {
      start_day: @start_day,
      duration: @duration,
      iterations: @iterations.map(&:attributes),
      completed_iterations: @completed_iterations.map(&:attributes)
    }.compact
  end

  # Public: iterations should come to us in the correct buckets, ordered, and
  # without duplicates. That's not always the case however. So this method takes
  # all iterations and puts them in the corect buckets, removes duplicates
  # (logging duplicates), and orders them.
  #
  # active iterations are ordered by start date asc
  # completed iterations are ordered by start date desc
  #
  # Returns an instance of Configuration
  def partition_iterations
    completed, active = deduplicate_and_log(@iterations + @completed_iterations)
      .sort_by(&:parsed_start)
      .partition(&:completed?)

    @iterations = active
    @completed_iterations = completed.reverse
    self
  end

  private

  # Instead of simply calling `uniq` we deduplicate _and_ log that we are
  # removing duplicates.
  def deduplicate_and_log(iterations)
    iterations
      .group_by(&:parsed_start)
      .flat_map do |_date, iterations|
      # log and then remove duplicates by not including them
      iterations[1..].each { |iteration| log_removal(iteration) }
      iterations.first
    end.compact
  end

  def log_removal(iteration)
    GitHub.logger.info(
      DUPLICATE_ITERATION_MESSAGE,
      iteration.attributes.map { |k, v| ["gh.memex.iteration.#{k}", v] }.to_h
    )
  end

  def as_int(entry)
    return if entry.nil?
    return unless entry.respond_to?(:to_i)

    entry.to_i
  end

  def iterations_are_valid
    return if @iterations.empty?

    @iterations.each do |iteration|
      next if iteration.valid?

      iteration.errors.full_messages.each { |msg| errors.add(:iterations, msg.downcase) }
    end
  end

  def completed_iterations_are_valid
    return if @completed_iterations.empty?

    @completed_iterations.each do |iteration|
      next if iteration.valid?

      iteration.errors.full_messages.each { |msg| errors.add(:completed_iterations, msg.downcase) }
    end
  end

  def not_too_many_iterations
    return if @iterations.size + @completed_iterations.size <= MAX_ITERATION_COUNT_LIMIT

    errors.add(:base, "exceeds the maximum limit of iterations allowed, #{MAX_ITERATION_COUNT_LIMIT}")
  end
end
