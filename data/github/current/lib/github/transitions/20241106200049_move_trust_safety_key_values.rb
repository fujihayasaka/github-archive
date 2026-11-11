# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveTrustSafetyKeyValues < MoveKeyValuesBase
      class TrustSafetyKeyValues < ApplicationRecord::Domain::Spam
        self.table_name = :trust_safety_key_values
      end

      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        TrustSafetyKeyValues
      end

      iterate_key_values [
        "staff.unlock\\_private\\_audit\\_logs.%viewing%"
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

  GitHub::Transitions::MoveTrustSafetyKeyValues.new(args).run
end
