# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillDependabotDefaultRule < Base
      # Most transitions iterate over a dataset. To do that, use and configure
      # an iterator using `iterate_over`. See the common database table
      # iterator example below, or check the iterators base class
      # (`GitHub::Transitions::Iterators::Base`) to learn how to implement
      # a custom iterator.
      #
      # In case you are not iterating over a dataset but want to perform a
      # one-off action, you can overwrite the `#perform` method.

      # Example: Iterate over a database table
      #
      #     class MyModel < ApplicationRecord::Domain::MyDomain
      #       self.table_name = :my_table
      #     end
      #
      #     iterate_over :database_table, params: {
      #       model_class: MyModel,
      #       conditions: "my_column IS NOT NULL",
      #       columns: %i[my_column],
      #     }
      #

      # sig { override.void }
      # def after_initialize
      #   # in case you need to initialize some instance variables
      # end

      sig { override.returns(T.untyped) }
      def perform
        if dry_run?
          puts "Tried to insert default rule, but dry run is enabled. Skipping..."
        else
          insert_default_rule
        end
      end

      private

      sig { returns(T.untyped) }
      def insert_default_rule
        if VulnerabilityAlertRule.where(target_type: "global", target_id: 0).exists?
          puts "Default rule already exists. Skipping..."
        else
          VulnerabilityAlertRule.find_or_create_by({
            target_type: "global",
            target_id: 0,
            name: "Dismiss low-impact alerts for development-scoped dependencies",
            conditions: {
              "ecosystem" => ["npm"],
              "scope" => ["development"],
              "cwe" => RepositoryVulnerabilityAlert::AutoDismissal::ALLOWED_CWE_IDS
            },
            enablement_behavior: "enabled_by_default_for_public",
            actions: {
              "alert_actions" => { "auto_dismiss" => "indefinitely" },
              "version" => 1
            }
          })
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

  GitHub::Transitions::BackfillDependabotDefaultRule.new(args).run
end
