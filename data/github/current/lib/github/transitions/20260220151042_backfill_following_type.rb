# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillFollowingType < Base
      class Following < ApplicationRecord::Domain::Users
        self.table_name = "followers"
      end

      iterate_over :database_table, params: {
        model_class: Following,
        conditions: "following_type IS NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        row_ids = items.keys

        scope = Following
          .joins("INNER JOIN users ON users.id = followers.following_id")
          .where(id: row_ids)
          .where("followers.following_type IS NULL OR followers.following_type != users.type")

        if dry_run?
          counts = scope.group("users.type").count
          if counts.any?
            update_summary = counts
              .map { |(following_type, count)| "#{following_type} x#{count}" }
              .join(", ")
            log "Would update followers rows: #{update_summary}"
          end
        else
          updated_count = 0
          write_to(model_class: Following) do
            updated_count = T.cast(scope.update_all("followers.following_type = users.type"), Integer)
          end
          log "Updated #{updated_count} out of #{row_ids.size} followers row(s) (#{row_ids.min}-#{row_ids.max})"
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

  GitHub::Transitions::BackfillFollowingType.new(args).run
end
