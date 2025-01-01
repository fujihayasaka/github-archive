# typed: strict
# frozen_string_literal: true

# we're really not going to be able to sorbet this for a bit https://sorbet.org/docs/error-reference#7019

module Copilot
  class Command
    extend T::Helpers

    include Copilot::Helpers

    abstract!

    # Create and call the command with the given arguments.
    sig do
      params(
        args: T.untyped, # rubocop:disable Sorbet/ForbidTUntyped
        kwargs: T.untyped, # rubocop:disable Sorbet/ForbidTUntyped
        block: T.nilable(T.proc.void),
      ).void
    end
    def self.call(*args, **kwargs, &block)
      new(*T.unsafe(args), **kwargs, &block).call # rubocop:disable Sorbet/ForbidTUnsafe
    end

    # Call the command. Subclasses should *not* override this. Instead, see
    # #perform.
    sig { void }
    def call
      collect_metrics("#{name}#call") do
        with_read do # all commands are read only - make sure to override this if you need to write
          perform
        end
      end
    end

    protected

    sig do
      type_parameters(:A).params(
        name: String,
        block: T.proc.returns(T.type_parameter(:A)),
      ).returns(T.type_parameter(:A))
    end
    def collect_metrics(name, &block)
      GitHub.tracer.in_span(name, kind: :internal) do |_span|
        begin
          GitHub.dogstats.distribution_time("#{name}.latency") do
            GitHub.dogstats.increment("#{name}.count")
            GitHub.logger.with_named_tags("gh.copilot.command" => self.class.to_s) do
              yield
            end
          end
        rescue => e # rubocop:todo Lint/GenericRescue
          GitHub.dogstats.increment "#{name}.errors"
          raise e
        end
      end
    end

    sig do
      type_parameters(:A).params(
        block: T.proc.returns(T.type_parameter(:A)),
      ).returns([T.type_parameter(:A), T.any(Float, Integer)])
    end
    def value_with_timing(&block)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      [yield, (1000 * (Process.clock_gettime(Process::CLOCK_MONOTONIC) - now))]
    end

    # Perform the command. Subclasses must implement this method.
    sig { abstract.void }
    def perform; end

    # The name of the command for tracing and stats purposes.
    sig { returns(String) }
    def name
      self.class.name.to_s.underscore
    end
  end
end
