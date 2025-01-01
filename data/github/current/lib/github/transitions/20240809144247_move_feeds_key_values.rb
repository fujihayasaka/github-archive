# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveFeedsKeyValues < MoveKeyValuesBase
      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        Feeds::KV::DataStore
      end

      iterate_key_values [
        "%:feeds:Feed Implicit Relationships",
        "%:growth:New Organization Copilot Add-on - Shows Copilot add-on when creating a new organization",
        "%:growth:Enterprise trial organization create",
        "%:userengagement:%",
        "%:webex:Pricing validation test",
        "%:webex:Features Copilot new video test",
        "conduit\\_feed.%",
        "azureexp.assignment.%",
        "topic\\_feed:top\\_contributors:v1:%",
        "topic\\_feed:top\\_repos:v1:%",
        "user.last-stratocaster-event-timestamp.%",
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

  GitHub::Transitions::MoveFeedsKeyValues.new(args).run
end
