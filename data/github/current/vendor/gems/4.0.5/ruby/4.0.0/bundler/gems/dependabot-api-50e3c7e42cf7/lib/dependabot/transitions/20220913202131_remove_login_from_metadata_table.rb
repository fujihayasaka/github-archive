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
    class RemoveLoginFromMetadataTable < Dependabot::Transition
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
        @iterator = AccountTransition.unscoped.in_batches(of: BATCH_SIZE)
      end

      # Returns nothing.
      def perform
        iterator.each do |rows|
          process(rows)
        end
      end

      def process(rows)
        rows.each do |account_transition|
          current_metadata = account_transition.metadata
          metadata_minus_login = current_metadata.except("initiator_github_login")

          log "updated metadata is #{metadata_minus_login}" if verbose? && should_log?(account_transition)

          account_transition.update(metadata: metadata_minus_login) unless dry_run?
        end
      end

      private

      def should_log?(account_transition)
        account_transition.id % 1_000 == 1
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

  transition = Dependabot::Transitions::RemoveLoginFromMetadataTable.new(**options)
  transition.run
end
