# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class FixPullRequestAlertLocations < Base

      class TokenScanResultLocation < ApplicationRecord::TokenScanningService
        self.table_name = :token_scan_result_locations_v2
      end

      conditions = "(content_type in (9, 10, 11)) "
      if GitHub.enterprise?
        conditions += "and created_at > '2023-09-19'"
      else
        conditions += "and created_at > '2023-08-15' and created_at < '2023-11-20'"
      end
      iterate_over :database_table, params: {
        model_class: TokenScanResultLocation,
        conditions: conditions,
        columns: [:content_id, :content_type],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        if verbose?
          verb = dry_run? ? "Would update" : "Updating"
          first_id = items.keys.first
          last_id = items.keys.last
          if first_id == last_id
            log("#{verb} row #{first_id}...")
          else
            log("#{verb} rows #{first_id} - #{last_id}...")
          end
        end

        # ISSUES
        # We need to get the issue ids associated with the current batch of issue locations
        batch_of_locations_by_id = items
        issue_ids_for_batch_of_locations = batch_of_locations_by_id
          .select { |_, values| values[:content_type] == 9 || values[:content_type] == 10 }
          .map { |_, values| values[:content_id] }

        # We need to get the issue comment ids associated with the current batch of issue locations
        issue_comment_ids_for_batch_of_locations = batch_of_locations_by_id.
        select { |_, values| values[:content_type] == 11 }.
        map { |_, values| values[:content_id] }

        # We need to check which of those issues have a pull request associated with it
        issue_ids_with_a_pull_request = T.let([], T::Array[T.any(Numeric, String)])
        ActiveRecord::Base.connected_to(role: :reading) do
          issue_ids_with_a_pull_request = ApplicationRecord::IssuesPullRequests.connection.select_rows(Arel.sql("SELECT id FROM issues WHERE id IN (:issue_ids) AND pull_request_id IS NOT NULL", issue_ids: issue_ids_for_batch_of_locations)).flatten
        end

        # We need to check which of those issue comments have a pull request associated with it
        issue_comment_ids_with_a_pull_request = T.let([], T::Array[T.any(Numeric, String)])
        ActiveRecord::Base.connected_to(role: :reading) do
          issue_comment_ids_with_a_pull_request = ApplicationRecord::IssuesPullRequests.connection.select_rows(Arel.sql("SELECT c.id FROM issue_comments c INNER JOIN issues i ON c.issue_id = i.id WHERE c.id IN (:issue_comment_ids) AND i.pull_request_id IS NOT NULL", issue_comment_ids: issue_comment_ids_for_batch_of_locations)).flatten
        end

        # And then update the locations that correspond with those issues
        locations_by_id_with_a_pull_request = batch_of_locations_by_id
          .select do |_, values|
            issue_ids_with_a_pull_request.include?(values[:content_id]) &&
            (values[:content_type] == 9 || values[:content_type] == 10) ||
            issue_comment_ids_with_a_pull_request.include?(values[:content_id]) &&
            values[:content_type] == 11
          end
        location_ids_with_a_pull_request = locations_by_id_with_a_pull_request.map { |key, _| key }

        if dry_run?
          log("Would set the content type to 4, 5, or 6 on #{location_ids_with_a_pull_request.length} rows")
        else
          write_to(model_class: TokenScanResultLocation) do
            TokenScanResultLocation.where(id: location_ids_with_a_pull_request).where(content_type: 9).update_all(content_type: 4)
            TokenScanResultLocation.where(id: location_ids_with_a_pull_request).where(content_type: 10).update_all(content_type: 5)
            TokenScanResultLocation.where(id: location_ids_with_a_pull_request).where(content_type: 11).update_all(content_type: 6)
          end
        end

        log("Processed batch ending with id #{items.keys.last}")
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

  GitHub::Transitions::FixPullRequestAlertLocations.new(args).run
end
