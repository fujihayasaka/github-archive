# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module Helpers
      module LiveMigrations
        def check_outdated_updated_at(model, updated_at)
          if model.updated_at > updated_at.to_time
            Twirp::Error.canceled(
              "Did not update #{model.class.name} due to outdated updated_at.",
              octoshift_error_code: "OUTDATED_UPDATED_AT"
            )
          end
        end
      end
    end
  end
end
