# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module ArgumentsDependency
        # Find the first non-empty (non-zero) ID argument.
        #
        # Go uses 0 for empty int values, so we need to discard them.
        #
        # Returns an Integer if a non-empty ID is found, nothing
        # otherwise.
        def id_argument(*possible_ids)
          provided_ids = possible_ids.compact
          provided_ids.detect { |id| id > 0 }
        end
      end
    end
  end
end
