# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class RemoveWhitespaceFromLabelNames < Base

      UNICODE_WHITESPACE_REGEXP = /[\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]/

      class Label < ApplicationRecord::Domain::IssuesPullRequests
        self.table_name = :labels
      end

      # Creating the query using HEX conversion to avoid collation issues
      # Map Unicode characters to their UTF-8 hex representations
      unicode_hex_map = {
        "\u00A0" => "C2A0",    # NO-BREAK SPACE
        "\u1680" => "E18680",  # OGHAM SPACE MARK
        "\u2000" => "E28080",  # EN QUAD
        "\u2001" => "E28081",  # EM QUAD
        "\u2002" => "E28082",  # EN SPACE
        "\u2003" => "E28083",  # EM SPACE
        "\u2004" => "E28084",  # THREE-PER-EM SPACE
        "\u2005" => "E28085",  # FOUR-PER-EM SPACE
        "\u2006" => "E28086",  # SIX-PER-EM SPACE
        "\u2007" => "E28087",  # FIGURE SPACE
        "\u2008" => "E28088",  # PUNCTUATION SPACE
        "\u2009" => "E28089",  # THIN SPACE
        "\u200A" => "E2808A",  # HAIR SPACE
        "\u202F" => "E280AF",  # NARROW NO-BREAK SPACE
        "\u205F" => "E2819F",  # MEDIUM MATHEMATICAL SPACE
        "\u3000" => "E38080"   # IDEOGRAPHIC SPACE
      }

      connection = ApplicationRecord::Domain::IssuesPullRequests.connection
      like_conditions = unicode_hex_map.values.map do |hex_value|
        "HEX(label_name) LIKE #{connection.quote("%#{hex_value}%")}"
      end

      like_conditions << "label_name LIKE #{connection.quote("%\n%")}"

      CONDITIONS_SQL = T.let(like_conditions.join(" OR "), String)

      iterate_over :database_table, params: {
        model_class: Label,
        conditions: CONDITIONS_SQL,
        columns: [:id, :label_name, :repository_id]
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        return if items.empty?

        item_ids = items.keys
        log "Processing batch of #{items.size} labels with Unicode whitespace characters (IDs: #{item_ids.first} - #{item_ids.last})"

        if dry_run?
          log "DRY RUN: Would normalize label_name for #{items.size} labels"

          # check for potential validation errors and conflicts
          check_for_validation_errors(items)
        else
          log "Normalizing label_name for #{items.size} labels"

          write_to(model_class: Label) do
            updates = []
            skipped_labels = []

            items.each do |id, columns|
              current_name = columns[:label_name]
              repository_id = columns[:repository_id]
              next unless current_name && repository_id

              # convert to UTF-8
              current_name = GitHub::Encoding.try_guess_and_transcode(current_name)
              next unless current_name

              # same normalization logic as Labelable#normalize_name
              normalized_name = current_name
                .gsub(UNICODE_WHITESPACE_REGEXP, " ")
                .strip
                .gsub(/\n/, " ")

              # skip labels that would be empty after normalization -- verify in dry run if cases exist
              if normalized_name.empty?
                skipped_labels << { id: id, original: current_name, reason: "would be empty" }
                next
              end

              if normalized_name != current_name
                updates << { id: id, label_name: normalized_name }
              end
            end

            if skipped_labels.any?
              log "WARNING: Skipping #{skipped_labels.size} labels that would cause validation errors:"
            end

            unless updates.empty?
              connection = Label.connection
              update_ids = updates.map { |u| u[:id] }

              label_name_cases = updates.map { |u| "WHEN #{u[:id]} THEN #{connection.quote(u[:label_name])}" }.join(" ")

              Label.where(id: update_ids).where(CONDITIONS_SQL).update_all(
                "label_name = CASE id #{label_name_cases} END"
              )
            end
          end

          log "Successfully normalized label_name for #{items.size} labels (IDs: #{item_ids.first} - #{item_ids.last})"
        end
      end

      private

      sig { params(items: Iterators::Items).void }
      def check_for_validation_errors(items)
        repositories = {}
        validation_errors = []
        updates = []

        items.each do |id, columns|
          repository_id = columns[:repository_id]
          current_name = columns[:label_name]
          next unless current_name && repository_id

          # convert to UTF-8
          current_name = GitHub::Encoding.try_guess_and_transcode(current_name)
          next unless current_name

          # same normalization logic as Labelable#normalize_name
          normalized_name = current_name
            .gsub(UNICODE_WHITESPACE_REGEXP, " ")
            .strip
            .gsub(/\n/, " ")

          # find empty labels
          if normalized_name.empty?
            validation_errors << {
              label_name: current_name,
              repository_id: repository_id,
              type: :empty
            }
            next
          end

          # track labels that would be updated
          if normalized_name != current_name
            updates << { id: id, original: current_name, normalized: normalized_name }
          end

          repositories[repository_id] ||= Hash.new { |h, k| h[k] = [] }
          repositories[repository_id][normalized_name] << { id: id, original: current_name }
        end

        repositories.each do |repository_id, normalized_counts|
          duplicates = normalized_counts.select { |_name, entries| entries.size > 1 }
          next unless duplicates.any?

          # add one validation error per repository that has duplicates
          validation_errors << {
            repository_id: repository_id,
            type: :duplicate
          }
        end

        # Report validation errors by type
        empty_errors = validation_errors.select { |e| e[:type] == :empty }
        duplicate_errors = validation_errors.select { |e| e[:type] == :duplicate }

        log "Summary for this batch:"
        log "  - #{updates.size} labels would be updated"

        if validation_errors.any?
          log "Validation error summary:"
          log "  - #{empty_errors.size} labels would be empty after normalization"
          log "  - #{duplicate_errors.size} repos would have duplicate labels"
        else
          log "No validation errors detected in this batch"
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

  GitHub::Transitions::RemoveWhitespaceFromLabelNames.new(args).run
end
