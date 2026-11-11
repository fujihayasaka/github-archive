# typed: strict
# frozen_string_literal: true

module GH
  # GH::DualWriter wraps code that writes to a database table and provides
  # tracking/observability by setting a `dual_writer` key on GitHub.context.
  # The MySQL instrumenter reads this key and adds a `dual_writer:true`
  # tag to the `rpc.mysql.dist.time` metric.
  #
  # Usage:
  #
  #   GH::DualWriter.track { user_role.save! }
  #
  #   GH::DualWriter.track do
  #     Role.transaction do
  #       role.save!
  #       RolePermission.create!(role: role, action: fgp)
  #     end
  #   end
  #
  class DualWriter
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
