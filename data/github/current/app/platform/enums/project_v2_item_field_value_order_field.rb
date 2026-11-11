# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2ItemFieldValueOrderField < Platform::Enums::Base
      description "Properties by which project v2 item field value connections can be ordered."

      value "POSITION", "Order project v2 item field values by the their position in the project", value: "position"
    end
  end
end
