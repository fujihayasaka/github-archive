# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillBusinessTeamOrgAssignmentsBusinessId < Base
      iterate_over :database_table, params: {
        model_class: BusinessTeamOrgAssignment,
        conditions: "business_id IS NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        team_mappings = BusinessTeamOrgAssignment.where(id: items.keys).includes(:business_team).to_a.map { |a| [T.must(a.business_team).business_id, T.must(a.business_team).id] }
        team_mappings.group_by(&:first).each do |business_id, res|
          team_ids = res.map(&:last).uniq
          if dry_run?
            log("Would have updated BusinessTeamOrgAssignment for teams #{team_ids} with business id #{business_id}")
          else
            log("Updating BusinessTeamOrgAssignment for teams #{team_ids} with business id #{business_id}")
            write_to(model_class: BusinessTeamOrgAssignment) do
              BusinessTeamOrgAssignment.where(team_id: team_ids).update_all(business_id: business_id)
            end
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

  GitHub::Transitions::BackfillBusinessTeamOrgAssignmentsBusinessId.new(args).run
end
