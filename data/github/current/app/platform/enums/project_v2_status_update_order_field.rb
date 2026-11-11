# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2StatusUpdateOrderField < Platform::Enums::Base
      description "Properties by which project v2 status updates can be ordered."

      value "CREATED_AT", "Allows chronological ordering of project v2 status updates.", value: "created_at"
    end
  end
end
