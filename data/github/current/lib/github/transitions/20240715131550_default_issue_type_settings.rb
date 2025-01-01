# rubocop:disable GitHub/UpsertAll
# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class DefaultIssueTypeSettings < Base

      class IssueType < ApplicationRecord::Domain::IssuesPullRequests
        self.table_name = :issue_types
      end

      iterate_over :database_table, params: {
        model_class: IssueType,
        conditions: "name IN ('Task', 'Bug', 'Enhancement') AND color = 'gray'"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        issue_types_attributes = ActiveRecord::Base.connected_to(role: :reading) do
          IssueType.where(id: items.keys).map do |issue_type|
            default_issue_type = ::IssueType::DEFAULTS.find { |d| d[:name] == issue_type.name }

            {
              id: issue_type.id,
              name: issue_type.name,
              color: ::IssueType::COLORS[default_issue_type[:color]],
              description: default_issue_type[:description],
              enabled: issue_type.enabled,
              issue_type: issue_type.issue_type,
              owner_id: issue_type.owner_id,
              updated_at: Time.current,
            } if default_issue_type.present?
          end
        end.compact

        if dry_run?
          log "Dry run: would update the following issue types: #{issue_types_attributes.pluck(:id).join(', ')}"
        else
          write_to(model_class: IssueType) do
            IssueType.upsert_all(issue_types_attributes)
          end
          log "Updated issue types: #{issue_types_attributes.pluck(:id).join(', ')}"
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

  GitHub::Transitions::DefaultIssueTypeSettings.new(args).run
end

# rubocop:enable GitHub/UpsertAll
