# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module CodeSearchError
      include Platform::Interfaces::Base

      description "An error that occurred while searching for code"

      mobile_only true

      field :message, String, description: "Details of the error", null: false
    end
  end
end
