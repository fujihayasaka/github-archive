# typed: true
# frozen_string_literal: true

require "active_support/values/time_zone"
require "active_support/core_ext/object"
require "active_support/core_ext/time"

module GitHub
  class Experiment
    # Methods for importing experiments executed outside the monolith
    # intended for external services that interact with dotcom and wish
    # to take advantage of the extensive scientist tooling that dotcom
    # provides rather than rolling their own.
    # For example usage, see GitRPC::Experiment.
    #
    # The payload format is described by `schemas/scientist_result.json`
    # in this directory.
    module External
      InvalidPayload = Class.new(RuntimeError)

      # A mismatch, raised when raise_on_mismatches is enabled.
      # This is adapted from code in Scientist::Experiment
      class MismatchError < Exception
        attr_reader :name, :result

        def initialize(result)
          @result = result
          super "experiment '#{result.name}' observations mismatched"
        end

        def to_s
          super + ":\n" +
          format_observation("control", result.control) + "\n" +
          format_observation("candidate", result.candidate) + "\n" +
          "\n"
        end

        def format_observation(name, observation)
          name + ":\n" +
          if observation[:exception]
            lines = observation[:exception][:backtrace].map { |line| "    #{line}" }.join("\n")
            "  #{observation[:exception][:class]}: #{observation[:exception][:message]}" + "\n" + lines
          else
            "  #{observation[:value].inspect}"
          end
        end
      end

      # Given a serialzied `internal/scientist-result`-formatted hash
      # representing an externally executed experiment result, parse the
      # result, publish it to dotcom's scientist subscribers and return
      # the unwrapped control value.
      def self.process!(payload)
        payload = payload.deep_symbolize_keys
        parsed = parse!(payload)
        parsed.publish!
        if parsed.outcome == Outcome::Mismatch && GitHub::Experiment.raise_on_mismatches?
          raise MismatchError.new(parsed)
        end
        parsed.value
      end

      # Given a hash representing an externally performed experiment in
      # the format specified by the `internal/scientist-result` schema,
      # validate and translate it to a payload acceptable to `science.*`
      # event subscribers, returning an `ParsedResult`.
      # TODO @brasic I plan to add json-schema validation in a fast follow
      def self.parse!(payload)
        parser = Parser.new(payload)
        ParsedResult.new(
          outcome: parser.outcome,
          payload: {
            name: parser.name,
            context: parser.context,
            execution_order: parser.execution_order,
          }.merge(parser.observations)
        )
      end

      # A successfully imported result, ready to be published to
      # experiment subscribers and optionally for its control to be
      # returned to app code.
      class ParsedResult
        # outcome - An Experiment::Outcome describing whether the
        #           candidate matched or not, or whether the result was
        #           ignored.
        # payload - A payload suitable as an argument to
        #           GitHub::Experiment.publish
        def initialize(outcome:, payload:)
          @outcome = outcome
          @payload = payload
        end

        def publish!
          GitHub::Experiment.publish(
            outcome: outcome,
            payload: payload
          )
        end

        def name
          payload.fetch(:name)
        end

        def control
          payload.fetch(:control)
        end

        def candidate
          payload.fetch(:candidate)
        end

        # The result of the control arm of the experiment which should
        # be returned to calling code if needed.
        def value
          payload.fetch(:control).fetch(:value)
        end

        attr_reader :outcome, :payload
      end

      # Simple class which can validate and extract the structure of a
      # scientist_result Hash.
      class Parser
        def initialize(payload)
          @payload = payload.deep_symbolize_keys
        end

        attr_reader :payload

        def self.utc
          @utc ||= ActiveSupport::TimeZone["UTC"]
        end

        def outcome
          outcome = Outcome.coerce!(
            payload.delete(:outcome)
          )
        rescue Outcome::Unknown => e
          raise InvalidPayload, e.inspect
        end

        def name
          extract(:name)
        end

        def execution_order
          extract(:execution_order)
        end

        def context
          context = extract(:context).dup
          timestamp_epoch = extract(:timestamp_epoch, from: context)
          context.delete(:timestamp_epoch)
          context[:timestamp] = self.class.utc.at(timestamp_epoch)
          context
        rescue TypeError => e
          raise InvalidPayload, "#{e.inspect} #{context.inspect}"
        end

        # rearrange observations to be inline at the root level
        def observations
          observations = extract(:observations)
          observations.each_with_object({}) do |obs, obj|
            name = extract(:name, from: obs)
            obs.delete(:name)
            obj[name.to_sym] = obs
          end
        end

        def extract(key, from: payload)
          from[key] or fail(
            InvalidPayload,
            "missing #{key} in #{from.inspect}"
          )
        end
      end
    end
  end
end
