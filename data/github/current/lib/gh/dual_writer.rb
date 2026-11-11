# typed: strict
# frozen_string_literal: true

module GH
  # GH::DualWriter wraps code that writes to a database table and provides
  # tracking/observability by setting a `dual_writer` key on GitHub.context.
  # The MySQL instrumenter reads this key and adds a `dual_writer:true`
  # tag to the `rpc.mysql.dist.time` metric.
  #
  # For simple tracking without secondary writes:
  #
  #   GH::DualWriter.track { user_role.save! }
  #
  # For full dual-write support, extend GH::DualWriter::Writable onto your
  # model class. See GH::DualWriter::Writable for details.
  #
  class DualWriter
    autoload :Handler, "gh/dual_writer/handler"
    autoload :Writable, "gh/dual_writer/writable"

    module WriteStages
      TRACK = T.let(:track, Symbol)
      BEST_EFFORT = T.let(:best_effort, Symbol)
    end

    # Wraps the given block, setting the `dual_writer` context key so that
    # any SQL executed within is tagged.
    #
    # Returns the block's return value. Exceptions are re-raised transparently.
    sig do
      type_parameters(:T)
        .params(block: T.proc.returns(T.type_parameter(:T)))
        .returns(T.type_parameter(:T))
    end
    def self.track(&block)
      GitHub.context.push(dual_writer: true) do
        block.call
      end
    end
  end
end
