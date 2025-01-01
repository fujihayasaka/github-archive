# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveNotificationKeyValues < MoveKeyValuesBase
      class NotificationKeyValues < ApplicationRecord::Domain::Notifications
        self.table_name = :notification_key_values
      end

      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        NotificationKeyValues
      end

      iterate_key_values [
        "user.notifications%", # New Notifications' Inbox settings
        "duplicate-content:%", # Notifications::DuplicateContentCheck
        "switch_to_new_subject_from", # GHES new subject format switch date
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

  GitHub::Transitions::MoveNotificationKeyValues.new(args).run
end
