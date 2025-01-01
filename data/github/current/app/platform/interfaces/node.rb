# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Node
      include Platform::Interfaces::Base
      description "An object with an ID."
      field(:id, ID, null: false, description: "ID of the object.")
    end
  end
end
