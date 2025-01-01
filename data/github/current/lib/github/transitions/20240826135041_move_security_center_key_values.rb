# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveSecurityCenterKeyValues < MoveKeyValuesBase
      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        ::SecurityCenter::KV::DataStore
      end

      iterate_key_values [
        "user.security-center-survey.%.%.dismissed",
        "security-configs-banner-component.dismissed.%",
        "security\\_center.total\\_open\\_alert\\_counts\\_by\\_feature.%.%",
        "SecurityOverviewAnalytics::RepositoryDataCleanupJob",
        "SecurityOverviewAnalytics::RepositoryDataCompressionJob",
        "SecurityCenter::OwnerReconciliationJob:%",
        "SecurityOverviewAnalytics::Reconciliation::OrganizationReconciliationJob:%",
        "security\\_overview\\_analytics.%\\_fanout\\_session.%\\_%.%",
        "security-center-dlq:%:%",
        "advisory\\_change\\_handler\\_job:%\\_%",
        "security\\_overview\\_analytics.initialization.business.%.%",
        "security\\_overview\\_analytics.initialization.organization.%",
        "security\\_overview\\_analytics.initialization.user.%"
      ]
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(cleanup))

  GitHub::Transitions::MoveSecurityCenterKeyValues.new(args).run
end
