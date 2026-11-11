# typed: false
# frozen_string_literal: true

# Tapioca's protobuf DSL compiler finds message classes via
# `Google::Protobuf::DescriptorPool.generated_pool`, which only fills as
# `_pb.rb` files are required. Force-require them all under the `tapioca`
# CLI so DSL generation sees every message. (We can't key off
# `defined?(Tapioca)` — the gem is loaded at every dev boot.)
if File.basename($PROGRAM_NAME) == "tapioca"
  Dir[Rails.root.join("lib/proto/**/*_pb.rb")].sort.each { |f| require f }
end
