# typed: strict
# frozen_string_literal: true

# Emits `github.v1.TeamDestroyMemberships` hydro events when an enterprise team
# is destroyed, so billing platform can remove the destroyed team from each
# member's cost center attribution document with point patches instead of a
# cross-partition query.
#
# The team no longer exists by the time billing platform processes the event, so
# the member list is carried in the payload. It is split into bounded batches
# (one event per batch) to keep every hydro message well under the per-message
# size ceiling, even for the largest teams.
#
# See ADR 0088:
# https://github.com/github/gitcoin/blob/main/docs/technical/architecture-decision-record/0088-split-team-membership-events-to-avoid-cross-partition-queries.md
class HydroEmitTeamDestroyMembershipsJob < BillingJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Matches our standard write batch size.
  BATCH_SIZE = T.let(100, Integer)

  SCHEMA = T.let("github.v1.TeamDestroyMemberships", String)

  # The destroyed team's attributes, captured at enqueue time because the team
  # no longer exists by the time this job runs. Mirrors the fields serialized
  # for the `hydro.schemas.github.v1.entities.Team` entity.
  sig do
    params(
      team_attributes: T::Hash[Symbol, T.untyped],
      customer_id: Integer,
      member_user_ids: T::Array[Integer],
    ).void
  end
  def perform(team_attributes, customer_id, member_user_ids)
    return if member_user_ids.empty?

    total_team_size = member_user_ids.size
    batches = member_user_ids.each_slice(BATCH_SIZE).to_a

    batches.each_with_index do |batch, batch_index|
      GitHub.hydro_publisher.publish(
        {
          team: team_attributes,
          customer_id: customer_id,
          member_user_ids: batch,
          batch_index: batch_index,
          total_batches: batches.size,
          total_team_size: total_team_size,
        },
        schema: SCHEMA,
      )
    end
  end
end
