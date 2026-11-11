# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Trigger
      include Platform::Interfaces::Base
      description "Entities that can trigger a workflow run."
      visibility :internal

      global_id_field :id, description: "The Node ID of the Trigger object"
    end
  end
end
