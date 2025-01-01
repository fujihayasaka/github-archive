# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20190823181007_create_github_package_registry_product_in_zuora.rb -v | tee -a /tmp/create_github_package_registry_product_in_zuora.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20190823181007_create_github_package_registry_product_in_zuora.rb -v -w | tee -a /tmp/create_github_package_registry_product_in_zuora.log
#
module GitHub
  module Transitions
    class CreateGithubPackageRegistryProductInZuora < Transition
      # Returns nothing.
      def perform
        ApplicationRecord::Collab.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          log "Syncing GitHub Package Registry rate plans to Zuora"
          ::Billing::PackageRegistry::ZuoraProduct.sync_to_zuora unless dry_run?
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end
    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::CreateGithubPackageRegistryProductInZuora.new(options)
  transition.run
end
