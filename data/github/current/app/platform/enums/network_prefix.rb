# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class NetworkPrefix < Platform::Enums::Base
      description "Network address prefix"
      visibility :internal

      value "SUBNET_24", "24-bit network prefix", value: 24
      value "SUBNET_32", "32-bit network prefix", value: 32
    end
  end
end
