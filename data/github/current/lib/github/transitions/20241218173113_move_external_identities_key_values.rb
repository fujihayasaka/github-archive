# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveExternalIdentitiesKeyValues < MoveKeyValuesBase
      class ExternalIdentitiesKeyValues < ApplicationRecord::Domain::Users
        self.table_name = :external_identities_key_values
      end

      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        ExternalIdentitiesKeyValues
      end

      iterate_key_values [
        "ent:attest:contractor%",
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

  GitHub::Transitions::MoveExternalIdentitiesKeyValues.new(args).run
end
