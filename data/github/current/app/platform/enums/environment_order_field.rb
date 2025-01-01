# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnvironmentOrderField < Platform::Enums::Base
      description "Properties by which environments connections can be ordered"

      value "NAME", "Order environments by name.", value: "name"
    end
  end
end
