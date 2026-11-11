# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillExternalGroupTeamsBusinessId < Base
      iterate_over :database_table, params: {
        model_class: ExternalGroupTeam,
        conditions: "business_id IS NULL",
        columns: %i[id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        external_group_team_ids = items.keys

        if GitHub.single_business_environment?
          if dry_run?
            log("Would have updated #{external_group_team_ids.size} external group teams (sample: #{external_group_team_ids.first(10)}) with business_id #{GitHub.global_business.id}")
          else
            log("Updating #{external_group_team_ids.size} external group teams (sample: #{external_group_team_ids.first(10)}) with business_id #{GitHub.global_business.id}")
            write_to(model_class: ExternalGroupTeam) do
              ExternalGroupTeam.where(id: external_group_team_ids).update_all(business_id: GitHub.global_business.id)
            end
          end
        else
          if dry_run?
            log("Would have updated #{external_group_team_ids.size} external group teams (sample: #{external_group_team_ids.first(10)}) via external_groups join")
          else
            log("Updating #{external_group_team_ids.size} external group teams (sample: #{external_group_team_ids.first(10)}) via external_groups join")
            write_to(model_class: ExternalGroupTeam) do
              ExternalGroupTeam.where(id: external_group_team_ids)
                .joins("INNER JOIN external_groups ON external_groups.id = external_group_teams.external_group_id")
                .where.not(external_groups: { business_id: nil })
                .update_all("external_group_teams.business_id = external_groups.business_id")
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

  GitHub::Transitions::BackfillExternalGroupTeamsBusinessId.new(args).run
end
