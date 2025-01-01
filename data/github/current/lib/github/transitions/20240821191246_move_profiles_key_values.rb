# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveProfilesKeyValues < MoveKeyValuesBase
      class ProfilesKeyValues < ApplicationRecord::Domain::Users
        self.table_name = :profiles_key_values
      end

      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        ProfilesKeyValues
      end

      iterate_key_values [
        "nodeinfo.software.v1:%",
        "contribs-accessor-ns:%",
        "user.large\\_scale\\_contributor.%",
        "user.flagged\\_contribution\\_classes.%",
        "user.followers\\_count.%",
        "user.following\\_count.%",
        "user.emoji\\_skin\\_tone\\_preference.%",
        "user.show\\_private\\_contribution\\_count.%",
        "user.activity\\_overview.%",
        "user.disable\\_pro\\_badge.%",
        "user.disable\\_acv\\_badge.%",
        "user.disable\\_achievements.%",
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

  GitHub::Transitions::MoveProfilesKeyValues.new(args).run
end
