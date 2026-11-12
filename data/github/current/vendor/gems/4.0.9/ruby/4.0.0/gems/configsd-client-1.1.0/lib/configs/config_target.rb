# frozen_string_literal: true

require_relative "proto/configs_pb"

# Configs::ConfigTarget represents a target with its type and ID,
# returned by list_targets_by_config_value.
Configs::ConfigTarget = Data.define(:id, :type) do
  def self.from_proto(proto_target)
    new(
      id: proto_target.id,
      type: proto_target.type.to_s
    )
  end
end
