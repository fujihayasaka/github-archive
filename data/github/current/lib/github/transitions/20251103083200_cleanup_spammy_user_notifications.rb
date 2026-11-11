# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class CleanupSpammyUserNotifications < Base
      # Custom model class to avoid STI issues with the users table
      class UserModel < ApplicationRecord::Domain::Users
        self.table_name = "users"
        # Disable Single Table Inheritance to avoid conflicts with the 'type' column
        self.inheritance_column = nil
      end

      iterate_over :database_table, params: {
        model_class: UserModel,
        conditions: "`spammy` = 1 AND `updated_at` >= '#{5.months.ago.utc.to_fs(:db)}'",
        columns: %i[id login spammy updated_at],
      }

      sig { override.void }
      def after_initialize
        @total_users_processed = T.let(0, T.nilable(Integer))
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log "#{dry_run? ? "Would process" : "Processing"} users from #{items.keys.first} to #{items.keys.last}"

        items.each_pair do |user_id, values|
          login = values[:login]
          spammy = values[:spammy]
          updated_at = values[:updated_at]

          log "#{dry_run? ? "Would process" : "Processing"} user #{user_id} (#{login}) - spammy: #{spammy}, updated_at: #{updated_at}"

          @total_users_processed = T.must(@total_users_processed) + 1

          if dry_run?
            log "Would enqueue ToggleNotificationsForSpammyUsersJob for user #{user_id} (#{login})"
          else
            # Enqueue the job to move notifications from notification_entries to spammy_notification_entries
            # Mode "hide" moves from notification_entries -> spammy_notification_entries
            begin
              ToggleNotificationsForSpammyUsersJob.perform_later(user_id, "hide")
              log "Enqueued ToggleNotificationsForSpammyUsersJob for user #{user_id} (#{login})"
            rescue => e
              log "Failed to enqueue job for user #{user_id} (#{login}): #{e.message}"
              raise e
            end
          end
        end

        log "#{dry_run? ? "Would have processed" : "Processed"} #{@total_users_processed} users"
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

  GitHub::Transitions::CleanupSpammyUserNotifications.new(args).run
end
