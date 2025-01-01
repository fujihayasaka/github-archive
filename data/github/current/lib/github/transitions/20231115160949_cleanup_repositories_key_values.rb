# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class CleanupRepositoriesKeyValues < MoveKeyValuesBase
      sig { override.returns(T.untyped) }
      def model_class; end

      iterate_key_values ["repo.max\\_ref\\_updates.%", "repo:sidebar\\_section\\_visibility:%"]

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        cleanup_keys(items)
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
  GitHub::Transitions::CleanupRepositoriesKeyValues.new(args).run
end
