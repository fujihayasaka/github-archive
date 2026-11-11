# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

#
# To run this transition directly from an ops host:
#
#   $ gh-k8s-shell -n dependabot-api-production bash
#   # First, run the transition in dry-run mode
#   $ bundle exec ruby lib/dependabot/transitions/20220913202131_remove_login_from_metadata_table.rb -v
#   # Then, run the transition in regular mode
#   $ bundle exec ruby lib/dependabot/transitions/20220913202131_remove_login_from_metadata_table.rb -v -w
#
module Dependabot
  module Transitions
    class ClearRegistriesFromDeletedConfigs < Dependabot::Transition
      # This Transition script is an alternative to running arbitary code in
      # production without code review, but remember there are some caveats
      # for Dependabot API at present:
      #
      # 1. We are using a k8s shell which is not very durable and may be
      #    displaced while the script is running.
      #    - Lock Dependabot API deploys while running a transition
      #    - Favour an approach that can be run in small batches to avoid this
      #    - Ensure your script is idempotent and safe to resume/re-run
      # 2. We do not have a readonly database connection at present, so make
      #    you test dry runs thoroughly!

      # Recommended batch size number, but you can modify for your use case
      BATCH_SIZE = 100

      attr_reader :iterator

      def after_initialize
        @iterator = UpdateConfigRegistry.joins(
          update_config: [:update_config_transitions]
        ).where(
          "update_config_transitions.to_state = 'deleted'"
        ).unscoped.in_batches(of: BATCH_SIZE)
      end

      # Returns nothing.
      def perform
        iterator.each do |rows|
          process(rows)
        end
      end

      def process(rows)
        rows.each do |registry_transition|
          if registry_transition.update_config.nil? || registry_transition.update_config.in_state?(:deleted)
            log "deleting UpdateConfigRegistry #{registry_transition.id}" if verbose?
            registry_transition.destroy unless dry_run?
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $PROGRAM_NAME == __FILE__
  slop = Slop.parse(help: true, strict: true) do |options|
    options.bool "-w",
                 "--write",
                 "Enable writes - this defaults to false for safety.",
                 default: false

    options.bool "-v",
                 "--verbose",
                 "Log verbose output"
  end

  options = slop.to_hash
  options = options.merge(dry_run: !options[:write])

  transition = Dependabot::Transitions::ClearRegistriesFromDeletedConfigs.new(**options)
  transition.run
end
