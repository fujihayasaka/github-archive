# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2ItemOrderField < Platform::Enums::Base
      description "Properties by which project v2 item connections can be ordered."

      value "POSITION", "Order project v2 items by the their position in the project", value: "position"
    end
  end
end
