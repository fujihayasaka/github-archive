# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class RenameAndUpdateActionsCicdFgps < Base
      # This existing FGP will have its action type changed to write_organization_actions_secrets so it is more specific to Actions
      SECRETS_FGP_ACTION_ORIGINAL_NAME = T.let("write_organization_secrets".freeze, String)
      SECRETS_FGP_ACTION_NEW_NAME = T.let("write_organization_actions_secrets".freeze, String)

      # This existing FGP will have its action type changed to write_organization_actions_variables so it is more specific to Actions
      VARIABLES_FGP_ACTION_ORIGINAL_NAME = T.let("write_organization_variables".freeze, String)
      VARIABLES_FGP_ACTION_NEW_NAME = T.let("write_organization_actions_variables".freeze, String)

      # In transitions/20240205184758_add_cicd_admin_fg_ps.rb when this was originaly created the type was accidently set to Organization; The extra ; is invalid
      # so we're going to update the target_type to just "Organization" without the ; and without deleting the entire FGP
      PACKAGES_FGP_ACTION = T.let("write_organization_packages".freeze, String)
      PACKAGES_FGP_TARGET_TYPE = T.let("Organization".freeze, String)

      sig { override.void }
      def perform
        # update actions secrets FGP action type
        if secrets_fgp = FineGrainedPermission.find_by(action: SECRETS_FGP_ACTION_ORIGINAL_NAME)
          if dry_run?
            log "would update secrets fgp with action #{secrets_fgp.action} and ID #{secrets_fgp.id} to action #{SECRETS_FGP_ACTION_NEW_NAME}"
          else
            log "updating secrets fgp with action #{secrets_fgp.action} and ID #{secrets_fgp.id} to action #{SECRETS_FGP_ACTION_NEW_NAME}"
            write_to(model_class: FineGrainedPermission) do
              secrets_fgp.update(action: SECRETS_FGP_ACTION_NEW_NAME) unless dry_run?
            end
          end
        else
          log "could not find secrets fgp to update"
        end

        # update existing variables FGP action type
        if variables_fgp = FineGrainedPermission.find_by(action: VARIABLES_FGP_ACTION_ORIGINAL_NAME)
          if dry_run?
            log "would update variables fgp with action #{variables_fgp.action} and ID #{variables_fgp.id} to action #{VARIABLES_FGP_ACTION_NEW_NAME}"
          else
            log "updating variables fgp with action #{variables_fgp.action} and ID #{variables_fgp.id} to action #{VARIABLES_FGP_ACTION_NEW_NAME}"
            write_to(model_class: FineGrainedPermission) do
              variables_fgp.update(action: VARIABLES_FGP_ACTION_NEW_NAME) unless dry_run?
            end
          end
        else
          log "could not find variables fgp to update"
        end

        # Update existing packages FGP target_type
        if packages_fgp = FineGrainedPermission.find_by(action: PACKAGES_FGP_ACTION)
          if dry_run?
            log "would update packages fgp with action #{packages_fgp.action} and target_type #{packages_fgp.target_type} and ID #{packages_fgp.id} to #{PACKAGES_FGP_TARGET_TYPE} target_type"
          else
            log "updating fgp with action #{packages_fgp.action} and target_type #{packages_fgp.target_type} and ID #{packages_fgp.id} to #{PACKAGES_FGP_TARGET_TYPE} target_type"
            write_to(model_class: FineGrainedPermission) do
              packages_fgp.update(target_type: PACKAGES_FGP_TARGET_TYPE) unless dry_run?
            end
          end
        else
          log "could not find packages fgp to update"
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::RenameAndUpdateActionsCicdFgps.new(args).run
end
