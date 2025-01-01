# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveSponsorsKeyValues < MoveKeyValuesBase
      class SponsorsKeyValues < ApplicationRecord::Domain::Sponsors
        self.table_name = :sponsors_key_values
      end

      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        SponsorsKeyValues
      end

      iterate_key_values [
        "stafftools\\_repository\\_funding\\_links\\_disabled\\_%",
        "populate\\_sponsors\\_fraud\\_reviews\\_payout\\_entry.maint.id",
        "SponsorsLowCreditBalanceWarningJob:%",
        "sponsors.invoice\\_migration\\_lock.%",
        "sponsors\\_goal.near\\_complete\\_event.%.%",
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

  GitHub::Transitions::MoveSponsorsKeyValues.new(args).run
end
