# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/20181128173010_create_github_actions_product_in_zuora.rb --verbose | tee -a /tmp/create_github_actions_product_in_zuora.log
#
module GitHub
  module Transitions
    class CreateGithubActionsProductInZuora < Transition
      # Returns nothing.
      def perform
        GitHub.zuorest_client.timeout = 300
        log "Syncing GitHub Actions rate plans to Zuora"
        ::Billing::Actions::ZuoraProduct.sync_to_zuora
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby create_github_actions_product_in_zuora.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::CreateGithubActionsProductInZuora.new(**options)
  transition.run
end
