# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module Helpers
      module LiveMigrations
        # warn_not_error should normally be false; it's here so that we can get logs for edits that _would_ have
        # failed due to outdated updated_at. (This is useful for debugging.)
        def check_outdated_updated_at(model, updated_at, warn_not_error: false)
          if model.updated_at > updated_at.to_time
            if warn_not_error
              GitHub.logger.warn(
                "check_outdated_updated_at failed, but we're continuing to run because warn_not_error is true.",
                model: model.class.name,
                model_id: model.id.to_s,
                model_updated_at: model.updated_at.to_s,
                twirp_updated_at: updated_at.to_time.to_s,
              )
              nil
            else
              Twirp::Error.canceled(
                "Did not update #{model.class.name} due to outdated updated_at.",
                octoshift_error_code: "OUTDATED_UPDATED_AT",
                model_id: model.id.to_s,
                model_updated_at: model.updated_at.to_s,
                twirp_updated_at: updated_at.to_time.to_s,
              )
            end
          end
        end
      end
    end
  end
end
