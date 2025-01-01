# typed: true
# frozen_string_literal: true

require "github/config/notifications"

module GitHub
  class Experiment
    autoload :External, "github/experiment/external"
    autoload :Outcome, "github/experiment/outcome"
  end
end


Scientist::Result.module_eval do
  # Payload for internal instrumentation
  def payload
    T.bind(self, Scientist::Result)
    data = context.merge \
      name: experiment_name,
      execution_order: observations.map(&:name),
      pid: Process.pid,
      hostname: Socket.gethostname
    observations.each do |observation|
      data[observation.name.to_sym] = observation.payload
    end
    data
  end

  # provides Scientist::Result#outcome
  include ::GitHub::Experiment::Outcome
end

module GitHub

  module ObservationExtensions
    def initialize(name, experiment, fabricated_duration: nil, &block)
      super(name, experiment, fabricated_duration: fabricated_duration) do
        Failbot.push("#gh.scientist.experiment" => experiment.name, "#gh.scientist.observation" => name, &block)
      end
    end

    # Payload for internal instrumentation
    def payload
      this = T.cast(self, Scientist::Observation)
      {
        duration: this.duration * 1000, # milliseconds
        cpu_time: this.cpu_time * 1000, # milliseconds
        exception: serialized_exception,
        value: this.cleaned_value,
      }
    end

    def serialized_exception
      T.bind(self, Scientist::Observation)
      return nil unless exception
      {
        class: exception.class.name,
        message: exception.message,
        backtrace: exception.backtrace,
      }
    end
  end

  ::Scientist::Observation.prepend(ObservationExtensions)

  # Internal: Do experiments with our own feature flags, reporting, and statistics.
  class Experiment
    include Scientist::Experiment

    # When an experiment mismatch error occurs on CI, it's obscured by another error.
    # The other error occurs because the CI framework tries to marshal the mismatch
    # error which contains procs which can't be marshalled. See
    # https://github.com/github/data-partitioning/issues/580 for more info. The method
    # below fixes the marshalling errors.
    def marshal_dump
      [@name, @result, @raise_on_mismatches]
    end

    def marshal_load(array)
      @name, @result, @raise_on_mismatches = array
    end

    # Publish a given payload to the notification topic corresponding to outcome.
    def self.publish(outcome:, payload:)
      outcome = Outcome.coerce!(outcome)
      GitHub.instrument "science.#{outcome}", payload
    end

    # Public: ignore mismatches for the duration of the given block.
    def self.ignore_mismatches(&block)
      old_value = raise_on_mismatches?
      self.raise_on_mismatches = false
      yield
    ensure
      self.raise_on_mismatches = old_value
    end

    # Public: set a flag to raise on internal errors.
    #
    # An internal error is anything that occurs during a clean or ignore block.
    def self.raise_on_internal_errors=(val)
      @raise_on_internal_errors = val
    end

    # Public: should internal errors raise an exception?
    def self.raise_on_internal_errors?
      @raise_on_internal_errors
    end

    # Public: this experiment's name
    attr_reader :name

    # Public: intialize an experiment.
    #
    # name - required String name of the experiment
    #
    # yields a new instance if a block is provided.
    #
    def initialize(name, &block)
      @name = name
      yield self if block_given?
    end

    # Public: run this experiment
    def run(name = nil)
      # Keep track of when the experiment runs so it's included in the final
      # payload if there's a mismatch:
      context timestamp: Time.now
      super
    end

    # Public: define a candidate with a graphite-friendly name
    #
    # While it's possible to use alternate candidate names as described in the
    # Scientist documentation, it's not recommended. If you do use this feature,
    # though, the stats will be duly recorded in graphite.
    def try(name = nil, &block)
      name = (name || "candidate").to_s
      unless name =~ /\A[a-z-]+\Z/
        raise ArgumentError, "candidate #{name.inspect} must have a graphite-friendly name: a-z and - only"
      end
      super name, &block
    end

    # Internal: is this experiment enabled?
    #
    # raise_on_mismatches implies a test environemnt, otherwise defer to
    # killswitch and the enabled percentage retrieved from the database.
    def enabled?
      self.class.raise_on_mismatches? || (GitHub.scientist_enabled? && rand(100) < percentage)
    end

    # Internal: what percent of the time this experiment should run
    def percentage
      ::Experiment.percentage name
    end

    # Internal: publish this experiment's result
    def publish(result)
      self.class.publish(outcome: result.outcome, payload: result.payload)
    end

    # Internal: an exception was raised somewhere in this experiment's internals
    def raised(operation, exception)
      if self.class.raise_on_internal_errors?
        raise exception
      else
        Failbot.report!(
          exception,
          :message => "Scientist `#{operation}` operation failed: #{exception.message}",
          "#experiment" => name,
        )
      end
    end

    # Public: Declare this experiment is comparing sequences of ActiveRecord models.
    #
    # This defines a comparator and cleaner that take this into account,
    # asserting that the sorted list of ids is a match and only storing lists of
    # ids when there is a mismatch.
    def compare_record_sequence
      compare do |a, b|
        if a.nil? || b.nil?
          a == b
        else
          a_ids = a.map(&:id)
          b_ids = b.map(&:id)
          a_ids.sort == b_ids.sort
        end
      end

      clean do |members|
        if members
          members.map { |record| record ? record.id : -1 }.sort
        else
          nil
        end
      end
    end

    # Public: Declare this experiment is comparing values that should not be logged in plain text.
    #
    # Defines a comparator that compares values and a cleaner that filters values if they are not
    # nil or the string "".
    def compare_sensitive_values
      compare do |control, candidate|
        if block_given?
          yield(control, candidate)
        else
          if control.nil? || candidate.nil?
            control == candidate
          else
            control.to_s == candidate.to_s
          end
        end
      end

      clean do |members|
        members == "" ? "" : "[FILTERED]"
      end
    end

    # Public: Declare this experiment is comparing a sequence of sortable items.
    #
    # Defines a comparator and cleaner for sortable sequences (e.g. Integers).
    def compare_sorted_sequence
      compare do |a, b|
        if a.nil? || b.nil?
          a == b
        else
          a.sort == b.sort
        end
      end

      clean do |items|
        items ? items.sort_by { |val| val || -1 } : nil
      end
    end

    # Public: Declare this experiment "known bad" when it comes to testing / raise-on-mismatches.
    #
    # This allows us to focus on experiments which *shouldn't* fail during testing
    # science, and is easily greppable for reenabling once we have greater
    # confidence in the code underlying an experiment.
    #
    # has_known_mismatches should stand out as much as a FIXME.
    def has_known_mismatches
      run_if do
        !GitHub::Experiment.raise_on_mismatches?
      end
    end

    # Public: declare this experiment as being concerned with performance
    # measurement only.
    def performance_only
      compare { true } # ignore mismatches entirely
    end

    # Public: Declare this experiment is comparing ordered sequences of ActiveRecord models.
    #
    # This defines a comparator and cleaner for asserting that the list of ids match.
    # Sorting has been avoided for the purpose of identify ordering mismatches.
    def compare_ordered_records
      compare do |a, b|
        if a.nil? || b.nil?
          a == b
        else
          a.map(&:id) == b.map(&:id)
        end
      end

      clean do |members|
        if members
          members.map { |record| record ? record.id : -1 }
        else
          nil
        end
      end
    end
  end
end
