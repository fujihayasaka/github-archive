# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectOrderField < Platform::Enums::Base
      description "Properties by which project connections can be ordered."

      value "CREATED_AT", "Order projects by creation time", value: "created_at"
      value "UPDATED_AT", "Order projects by update time", value: "updated_at"
      value "NAME", "Order projects by name", value: "name"
    end
  end
end
