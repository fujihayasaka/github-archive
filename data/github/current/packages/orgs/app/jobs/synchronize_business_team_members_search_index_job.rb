# typed: strict
# frozen_string_literal: true

# Enterprise team membership and organization assignments give a user *indirect*
# membership of the team's organizations. `User#organization_ids` resolves that
# indirect membership at read time, but the user search index stores it as a
# denormalized `all_org_ids` snapshot taken when the user was last indexed, so
# any change to a team's members or organizations leaves those users stale in
# the index and invisible to organization people search.
class SynchronizeBusinessTeamMembersSearchIndexJob < ApplicationJob
  queue_as :synchronize_business_team_members_search_index

  BATCH_SIZE = T.let(100, Integer)

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # team_ids      - reindex every current member of these teams. Members overlap
  #                 across teams, so the roster is resolved as one deduplicated,
  #                 ordered set rather than per team.
  # user_ids      - reindex exactly these users instead. Membership changes use
  #                 this to reindex only the users they touched.
  # after_user_id - cursor into the roster. Set when the job chains itself.
  sig do
    params(
      team_ids: T.nilable(T::Array[Integer]),
      user_ids: T.nilable(T::Array[Integer]),
      after_user_id: T.nilable(Integer),
    ).void
  end
  def perform(team_ids: nil, user_ids: nil, after_user_id: nil)
    batch = next_batch(team_ids: team_ids, user_ids: user_ids, after_user_id: after_user_id)
    return if batch.empty?

    GitHub.logger.info(
      "Starting SynchronizeBusinessTeamMembersSearchIndexJob",
      "gh.team.ids" => team_ids&.join(","),
      "gh.user.ids.size" => batch.size,
      "gh.after_user_id" => after_user_id,
    )

    User.where(id: batch).each(&:synchronize_search_index)

    # Chain rather than fan out: both keep a single execution bounded, but
    # chaining also bounds how many jobs one execution can enqueue.
    return if batch.size < BATCH_SIZE

    self.class.perform_later(team_ids: team_ids, user_ids: user_ids, after_user_id: batch.last)
  end

  private

  sig do
    params(
      team_ids: T.nilable(T::Array[Integer]),
      user_ids: T.nilable(T::Array[Integer]),
      after_user_id: T.nilable(Integer),
    ).returns(T::Array[Integer])
  end
  def next_batch(team_ids:, user_ids:, after_user_id:)
    return slice_after(user_ids, after_user_id) unless user_ids.nil?
    return [] if team_ids.blank?

    member_ids_after(team_ids, after_user_id)
  end

  sig { params(user_ids: T::Array[Integer], after_user_id: T.nilable(Integer)).returns(T::Array[Integer]) }
  def slice_after(user_ids, after_user_id)
    ids = user_ids.uniq.sort
    return ids.first(BATCH_SIZE) if after_user_id.nil?

    ids.select { |id| id > after_user_id }.first(BATCH_SIZE)
  end

  # Walks team membership in user id order so the cursor is stable across runs.
  # Ability rows are the source of truth for enterprise team membership, and
  # reading them directly keeps this working once the team itself is deleted.
  sig { params(team_ids: T::Array[Integer], after_user_id: T.nilable(Integer)).returns(T::Array[Integer]) }
  def member_ids_after(team_ids, after_user_id)
    scope = Ability.where(
      actor_type: "User",
      subject_id: team_ids,
      subject_type: "BusinessTeam",
      priority: Ability.priorities[:direct],
    )
    scope = scope.where(actor_id: (after_user_id + 1)..) unless after_user_id.nil?

    scope.distinct.order(:actor_id).limit(BATCH_SIZE).pluck(:actor_id)
  end
end
