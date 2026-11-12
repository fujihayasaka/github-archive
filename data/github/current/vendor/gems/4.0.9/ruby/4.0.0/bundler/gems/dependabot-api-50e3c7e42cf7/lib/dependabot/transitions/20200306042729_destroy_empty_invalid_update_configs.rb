# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

#
# To run this transition directly from an ops host:
#
#   $ gh-k8s-shell -n dependabot-api-production bash
#   # First, run the transition in dry-run mode
#   $ bundle exec ruby lib/dependabot/transitions/20200306042729_destroy_empty_invalid_update_configs.rb -v
#   # Then, run the transition in regular mode
#   $ bundle exec ruby lib/dependabot/transitions/20200306042729_destroy_empty_invalid_update_configs.rb -v -w
#
module Dependabot
  module Transitions
    class DestroyEmptyInvalidUpdateConfigs < Dependabot::Transition
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
      BATCH_SIZE = 500

      attr_reader :iterator, :total_count, :processed_count,
                  :deleted_count, :limit, :offset

      def after_initialize
        @limit = @other_args.fetch(:limit)
        @offset = @other_args.fetch(:offset)
        @total_count = scope.count
        @processed_count = 0
        @deleted_count = 0
        @iterator = scope.in_batches(of: BATCH_SIZE)
      end

      # Returns nothing.
      def perform
        log "Found '#{total_count}' update configs"

        iterator.each do |rows|
          @processed_count += rows.count
          process(rows)
          log "Processed #{processed_count}/#{total_count}..."
          log "Deleted #{deleted_count}/#{total_count}..."
          log "Offset: #{processed_count - deleted_count}"
        end
      end

      def process(rows)
        rows.each do |uc|
          unique_update_configs = UpdateConfig.active.where(
            repo_id: uc.repo_id,
            package_manager: uc.package_manager,
            directory: uc.directory,
            target_branch: uc.target_branch,
          ).count
          next if unique_update_configs == 1

          if uc.update_jobs.empty?
            log "Deleting update config with no jobs: #{uc.id}"
            @deleted_count += 1
            destroy_update_config(uc)
          else
            log "Can't delete update config with jobs: #{uc.id}"
          end
        end
      end

      private

      def destroy_update_config(update_config)
        return if dry_run?

        update_config.destroy
        update_config.update_config_transitions.destroy_all
      end

      def scope
        UpdateConfig.active.limit(limit).offset(offset)
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

    options.integer "--limit",
                    "Limits the number of records",
                    default: nil

    options.integer "--offset",
                    "Offsets the number of records",
                    default: 0
  end

  options = slop.to_hash
  options = options.merge(dry_run: !options[:write])

  transition = Dependabot::Transitions::DestroyEmptyInvalidUpdateConfigs.new(
    options
  )
  transition.run
end
