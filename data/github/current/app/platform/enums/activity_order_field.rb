# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class ActivityOrderField < Platform::Enums::Base
      description "Properties by which activity connections can be ordered."

      value "TIMESTAMP", "Order collection by timestamp", value: "timestamp"
    end
  end
end
