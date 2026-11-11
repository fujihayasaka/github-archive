# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Offsettable
      include Platform::Interfaces::Base
      docs_category :meta

      required_capabilities [:mobile_only_schema_mask, :copilot_agents]

      description "Common connection fields assisting with clarity over offset-based pagination."

      field :limit,
        Integer,
        description: "Debugging only: used to see the calculated limit used for paging",
        null: false

      field :offset,
        Integer,
        description: "Debugging only: used to see the calculated limit used for paging",
        null: false

      field :page,
        Integer,
        description: "Debugging only: used to see the calculated limit used for paging",
        null: false
    end
  end
end
