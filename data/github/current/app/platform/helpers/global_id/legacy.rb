# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module GlobalId
      class Legacy
        def self.parse(unparsed_id)
          begin
            decoded_global_id = Base64.strict_decode64(unparsed_id)
          rescue ArgumentError
            malformed = true
            decoded_global_id = Base64.decode64(unparsed_id)
          end

          length_string, rest = decoded_global_id.split(":", 2)

          unless rest
            raise Platform::Errors::NotFound, "Could not resolve to a node with the global id of '#{unparsed_id}'"
          end

          if malformed
            GitHub.dogstats.increment("platform.malformed_global_id")
          end

          length = length_string.to_i
          type = rest[0..length - 1]
          id = rest[length..-1]

          new(id, type)
        end

        attr_reader :id, :type
        def initialize(id, type)
          @id   = id
          @type = type
        end
      end
    end
  end
end
