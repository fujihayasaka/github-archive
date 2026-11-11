# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221013153422_remove_content_references.rb --verbose | tee -a /tmp/remove_content_references.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221013153422_remove_content_references.rb --verbose -w | tee -a /tmp/remove_content_references.log
module GitHub
  module Transitions
    class RemoveContentReferences < Transition
      BATCH_SIZE = GitHub.enterprise? ? 10000 : 100

      CONTENT_REFERENCE  = "content_reference"
      CONTENT_REFERENCES = "content_references"

      def after_initialize
        @hook_event_subscriptions_iterator = HookEventSubscription.where(name: CONTENT_REFERENCE)
        @default_integration_permissions_iterator = DefaultIntegrationPermission.where(resource: CONTENT_REFERENCES)

        @permissions_iterator = Permission.where(subject_type: [
          "#{Repository::Resources::ABILITY_TYPE_PREFIX}/#{CONTENT_REFERENCES}",
          "#{Repository::Resources::ALL_ABILITY_TYPE_PREFIX}/#{CONTENT_REFERENCES}"
        ])
      end

      # Returns nothing.
      def perform
        message_prefix = dry_run? ? "Would have destroyed" : "Destroying batch of"

        readonly do
          @permissions_iterator.in_batches(of: BATCH_SIZE) do |batch|
            log("#{message_prefix} #{batch.count} permissions")
            process(Permission, batch) unless dry_run?
          end

          @hook_event_subscriptions_iterator.in_batches(of: BATCH_SIZE) do |batch|
            log("#{message_prefix} #{batch.count} hook event subscriptions")
            process(HookEventSubscription, batch) unless dry_run?
          end

          @default_integration_permissions_iterator.in_batches(of: BATCH_SIZE) do |batch|
            log("#{message_prefix} #{batch.count} default integration permissions")
            process(DefaultIntegrationPermission, batch) unless dry_run?
          end
        end
      end

      private

      def process(klass, batch)
        klass.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          batch.destroy_all
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby /workspaces/github/lib/github/transitions/20221013153422_remove_content_references.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |id|
      options[:start_id] = id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |id|
      options[:end_id] = id
    end

    opts.on("--batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
      options[:batch_size] = size
    end

    opts.on("--no-rollback", "Do not write a rollback file; this may speed up your transition or dry run.") do
      options[:no_rollback] = true
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  transition = GitHub::Transitions::RemoveContentReferences.new(**options)
  transition.run
end
