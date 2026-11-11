# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class BackfillUsersDisplayName < Base
      class User < ApplicationRecord::Domain::Users
        self.table_name = :users
      end

      class Profile < ApplicationRecord::Domain::Users
        self.table_name = :profiles
      end

      iterate_over :database_table, params: {
        model_class: Profile,
        conditions: "name IS NOT NULL",
        columns: %i[user_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        user_ids = items.values.map { |vals| vals[:user_id] }

        users_ids_with_no_display_name = User.where(id: user_ids, display_name: nil).pluck(:id)
        return if users_ids_with_no_display_name.empty?

        user_ids_and_profile_names = Profile
          .where(user_id: users_ids_with_no_display_name)
          .where.not(name: nil)
          .pluck(:user_id, :name)

        return if user_ids_and_profile_names.empty?

        if dry_run?
          log "Would have backfilled display_name column for #{user_ids_and_profile_names.size} users with IDs: #{users_ids_with_no_display_name}"
        else
          case_clauses_arr = user_ids_and_profile_names.map do |user_id, profile_name|
            sanitized_name = User.connection.quote(profile_name)
            "WHEN #{user_id.to_i} THEN #{sanitized_name}"
          end
          case_clauses = case_clauses_arr.join(" ")

          update_user_ids = user_ids_and_profile_names.map { |user_id, _| user_id.to_i }

          updated = write_to(model_class: User) do
            User.where(id: update_user_ids, display_name: nil)
              .update_all("display_name = CASE id #{case_clauses} END")
          end
          log "Backfilled display_name column for #{updated} users with IDs: #{users_ids_with_no_display_name}"
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

  GitHub::Transitions::BackfillUsersDisplayName.new(args).run
end
