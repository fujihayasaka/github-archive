# typed: true
# frozen_string_literal: true

require "scientist"
require "socket"

module GitRPC
  # A Scientist experiment class designed to execute on the GitRPC server.
  # Publication of experiment results in this context is difficult because we
  # lack access to the multiple datastores a dotcom experiment uses to publish
  # results. To overcome this limitation, we execute the experiment and send
  # the serialized experiment result over the wire to the GitRPC client
  # (presumably dotcom) where it can be reconstituted and published.
  #
  #  name            - The name of the experiment
  #  state_generator - A proc which returns an opaque repo state
  #                    when called.  (The only API the value
  #                    returned by the proc must support is #==).
  class Experiment
    include Scientist::Experiment
    attr_accessor :name, :result, :path, :state_generator, :pre_state, :post_state

    NULL_STATE = -> {}

    def initialize(name, state_generator: NULL_STATE)
      @name = name
      @state_generator = state_generator
    end

    def enabled?
      true
    end

    # Serialize the experiment's result to a hash.
    def to_h(clean: false)
      run unless result
      {
        name: name,
        outcome: outcome,
        context: self.class.default_context.merge(
          result.context,
          {
            pre_state: pre_state,
            post_state: post_state
          }
        ),
        execution_order: result.observations.map(&:name),
        observations: result.observations.map { |obs|
          {
            name: obs.name,
            duration: 1000 * obs.duration,
            cpu_time: 1000 * obs.cpu_time,
            value: (clean ? obs.cleaned_value : obs.value),
            exception: obs.exception && {
              class: obs.exception.class.name,
              message: obs.exception.message,
              backtrace: obs.exception.backtrace
            }
          }
        }
      }
    end

    # Ignore as data race if our state file changed mid-experiment.
    # Otherwise compare the match.
    def outcome
      unless result
        raise ArgumentError, "cannot determine outcome on un-executed experiment"
      end
      if @pre_state != @post_state
        "ignore"
      else
        result.matched? ? "match" : "mismatch"
      end
    end

    # Publication is simple: save the result value in memory for
    # retrieval during serialization.
    def publish(result)
      @result = result
    end

    def run(name = nil)
      @pre_state = state_generator.call
      res = super
      @post_state = state_generator.call
      res
    end

    # Run an experiment and return the control result alongside the
    # serialized result data.
    def self.run_appending_result(name, clean: false, state_generator: NULL_STATE)
      raise ArgumentError, "need block" unless block_given?
      experiment = new(name, state_generator: state_generator)
      yield experiment
      control_result = experiment.run
      [control_result, experiment.to_h(clean: clean)]
    end

    def self.default_context
      @process_info ||= {
        hostname: Socket.gethostname,
        pid: Process.pid
      }
      @process_info.merge(timestamp_epoch: Time.now.to_f)
    end
  end
end
