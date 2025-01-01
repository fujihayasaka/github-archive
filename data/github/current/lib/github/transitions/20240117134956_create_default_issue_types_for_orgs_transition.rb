# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class CreateDefaultIssueTypesForOrgsTransition < Base
      iterate_over :database_table, params: {
        model_class: User,
        conditions: "type = 'Organization'"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        orgs = User.where(id: items.keys)

        log("Creating default issue types for #{orgs.pluck(:id).join(", ")} #{dry_run? ? " (dry run)" : ""}")
        unless dry_run?
          write_to(model_class: IssueType) do
            IssueType.create_default_issue_types_for(orgs)
          end
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

  GitHub::Transitions::CreateDefaultIssueTypesForOrgsTransition.new(args).run
end
