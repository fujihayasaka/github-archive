# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    module Errors
      class MissingFarFromCampusProof < StandardError
        sig { params(message: String).void }
        def initialize(message:)
          @message = message
        end

        sig { returns(String) }
        attr_reader :message
      end
    end
  end
end
