# frozen_string_literal: true

require "scientist/experiment"

# Provides a refactoring tool that allows us to run a comparative implementation
# while returning the response of the existing code.
#
# See: https://github.com/github/scientist
#
# Usage:
#   An experiment can be configured at a call site where you want to test
#   different implementations of some logic, like so:
#
#     experiment = Dependabot::Experiment.new("my-awesome-experiment") do |exp|
#       # Set some context values to be pushed to redis for mismatches
#       context { account_id: account.id, account_type: account.type }
#       # Add some additional information to `science.*` metrics
#       metric_tags { account_type: account.type }
#
#       exp.use { old_implementation }
#       exp.try { new_implementation }
#     end
#     exp.run
#
#   Each call will emit the following metrics:
#     - science.control.timing: the execution time of the `use` block
#     - science.candidate.timing: the execution time of the `try` block
#     - An indication of the experiment outcome via one of:
#       - science.match
#       - science.mismatch
#       - science.ignored
#
#   Unless specified by setting `store_mismatches = false` in your experiment,
#   the last 1000 mismatched results will be stored in Redis.
#
#   For further information, refer to the github/scientist documentation
#
# Enabling experiments:
#
#   Experiments are disabled by default, to enable your experiment, you must
#   set a sample rate in Redis.
#
#   This can be performed via a rake task:
#     script/rake experiment:set_sample_rate["my-awesome-experiment", 10]
#
# Experiment design:
#
#   This implementation of scientist is primarily orientated at giving us a
#   tool for refactoring code at scale.
#
#   If you are designing an experiment which significantly impacts the User
#   Experience of Dependabot, be mindful that this can impact core business
#   metrics.
#
#   Consider consulting the Experiment Oversight Council if you feel your
#   experiment strays beyond refactoring, see:
#     https://github.com/github/eoc
#
module Dependabot
  class Experiment
    include Scientist::Experiment

    MISMATCHES_KEPT = 1000

    attr_accessor :experiment_exceptions, :store_mismatches, :metric_tags
    attr_reader :name

    def self.sample_rate(experiment_name, percentage)
      new(experiment_name).sample_rate(percentage)
    end

    def self.current_sample_rate(experiment_name, percentage)
      new(experiment_name).current_sample_rate(percentage)
    end

    def initialize(name, store_mismatches: true)
      @name = name
      @sample_rate = get_redis_config(:sample_rate).to_i
      @store_mismatches = store_mismatches
      @metric_tags = {}
      @experiment_exceptions = []
      yield self if block_given?
    end

    def slug
      name.parameterize.underscore
    end

    def sample_rate(percentage)
      raise ArgumentError, "must be an integer" unless percentage.is_a?(Integer)
      raise ArgumentError, "cannot be negative" if percentage.negative?
      raise ArgumentError, "cannot exceed 100%" if percentage > 100

      set_redis_config(:sample_rate, percentage)
      @sample_rate = percentage
    end

    # Remove the experiment config from Redis, disabling the experiment
    def cleanup
      redis.del(config_redis_keys[:sample_rate])
    end

    # Remove the experiment config, disabling the experiment and irreversably delete
    # any mismatch data stored in Redis.
    def cleanup!
      cleanup
      redis.del(mismatch_redis_key)
    end

    def current_sample_rate
      @sample_rate
    end

    def enabled?
      return false unless @sample_rate

      rand(100) < @sample_rate
    end

    def store_mismatches?
      !!@store_mismatches
    end

    # Triggered when there is an exception inside any Scientist block other
    # than control or candidate(s)
    #
    # See: https://github.com/github/scientist#in-a-scientist-callback
    def raised(operation, error)
      experiment_exceptions << {
        operation: operation,
        exception: error.class,
        message: error.message,
        backtrace: error.backtrace,
      }

      # This outcome suggests the experiment itself is buggy, so let's report
      # it to Sentry.
      Dependabot::Exceptions.push(context.merge("gh.dependabot_api.experiment.slug": slug,
                                                "gh.dependabot_api.experiment.operation": operation))
      Dependabot::Exceptions.report(error)
    end

    def publish(result)
      MetricsClient.gauge("science.sample_rate",
                          current_sample_rate,
                          tags: tags)

      record_timing(result)

      outcome = if result.matched?
                  "matched"
                elsif result.ignored?
                  "ignored"
                else
                  "mismatched"
                end

      MetricsClient.increment("science.#{outcome}", tags: tags)

      return unless result.mismatched?

      log_mismatch(result)
      store_mismatch_data(result) if store_mismatches?
    end

    def mismatch_redis_key
      "science.#{slug}.mismatch"
    end

    def config_redis_keys
      {
        sample_rate: "science.#{slug}.config.sample_rate",
      }
    end

    private

    def get_redis_config(option)
      redis.get(config_redis_keys.fetch(option))
    end

    def set_redis_config(option, value)
      redis.set(config_redis_keys.fetch(option), value)
    end

    def record_timing(result)
      MetricsClient.timing("science.control",
                           result.control.duration,
                           tags: tags)

      # For now, we just report on the default candidate and consider multiple
      # candidates YAGNI
      #
      # see: https://github.com/github/scientist#trying-more-than-one-thing
      candidate = result.candidates.first
      MetricsClient.timing("science.candidate",
                           candidate.duration,
                           tags: tags)
    end

    def log_mismatch(result)
      Dependabot::Logger.info(
        {
          msg: "Mismatch found in experiment '#{name}'",
        }.merge(result_payload(result))
      )
    end

    # Maintains a list of the last 1000 mismatch results for inspection
    def store_mismatch_data(result)
      redis.lpush(mismatch_redis_key, result_payload(result).to_json)
      redis.ltrim(mismatch_redis_key, 0, MISMATCHES_KEPT)
    end

    def result_payload(result)
      {
        experiment: slug,
        context: context,
        control: observation_payload(result.control),
        candidate: observation_payload(result.candidates.first),
        execution_order: result.observations.map(&:name),
        experiment_exceptions: experiment_exceptions,
      }
    end

    def observation_payload(observation)
      if observation.raised?
        {
          exception: observation.exception.class,
          message: observation.exception.message,
          backtrace: observation.exception.backtrace,
        }
      else
        {
          value: observation.cleaned_value,
        }
      end
    end

    def tags
      metric_tags.merge({ experiment: slug })
    end

    def redis
      Dependabot.redis
    end
  end
end
