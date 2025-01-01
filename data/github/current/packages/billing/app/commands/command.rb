# typed: strict
# frozen_string_literal: true

class Command
  extend T::Helpers

  abstract!

  # Create and call the command with the given arguments.
  sig do
    params(
      args: T.untyped,
      kwargs: T.untyped,
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
      perform
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
          GitHub::Logger.log_context(command: self.class.to_s) do
            yield
          end
        end
      rescue => e # rubocop:todo Lint/GenericRescue
        GitHub.dogstats.increment "#{name}.errors"
        raise e
      end
    end
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
