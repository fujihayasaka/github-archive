# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

#
# To run this transition directly from an ops host:
#
#   $ gh-k8s-shell -n dependabot-api-production bash
#   # First, run the transition in dry-run mode
#   $ bundle exec ruby lib/dependabot/transitions/20220816085937_set_active_storage_blob_service_name.rb -v
#   # Then, run the transition in regular mode
#   $ bundle exec ruby lib/dependabot/transitions/20220816085937_set_active_storage_blob_service_name.rb -v -w
#
module Dependabot
  module Transitions
    class SetActiveStorageBlobServiceName < Dependabot::Transition
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
      # This value is the top-level key defined in config/storage.yml, which is
      # then passed to config.active_storage.service in config/environments/production.rb.
      # In our case, it's is called "amazon", so that's the value we should use.
      # We hardcode it instead of grabbing it from
      # ActiveStorage::Blob.service_name, that way we can set these values
      # _before_ upgrading to rails 6.1 (before that version, the service_name
      # method is not available).
      SERVICE_NAME = "amazon"

      attr_reader :iterator, :configured_service

      def after_initialize
        @iterator = ActiveStorage::Blob.unscoped.where(service_name: nil).in_batches(of: BATCH_SIZE)
      end

      # Returns nothing.
      def perform
        iterator.each do |rows|
          process(rows)
        end
      end

      def process(rows)
        ids_to_process = rows.pluck(:id)

        log "set service_name to #{configured_service} for #{ids_to_process}" if verbose?
        ActiveStorage::Blob.where(id: ids_to_process).update_all(service_name: SERVICE_NAME) unless dry_run?
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

  transition = Dependabot::Transitions::SetActiveStorageBlobServiceName.new(options)
  transition.run
end
