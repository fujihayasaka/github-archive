# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module TeamReviewRequestable
      include Platform::Interfaces::Base
      docs_category :teams

      description "Represents a team that can be requested to review a pull request."

      field :id, ID, description: "The Node ID of the TeamReviewRequestable object", method: :global_relay_id, null: false
      field :name, String, "The name of the team.", null: false
      field :slug, String, "A unique, human-readable identifier for the team.", null: false
    end
  end
end
