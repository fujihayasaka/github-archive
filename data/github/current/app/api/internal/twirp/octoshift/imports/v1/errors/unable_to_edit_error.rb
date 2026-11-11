# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      module Errors
        class UnableToEditError < StandardError
          attr_accessor :twirp_error

          def initialize(twirp_error)
            self.twirp_error = twirp_error
          end

          def message
            twirp_error
          end
        end
      end
    end
  end
end
