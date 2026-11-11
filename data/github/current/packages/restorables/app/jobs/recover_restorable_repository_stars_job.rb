# typed: strict
# frozen_string_literal: true

class RecoverRestorableRepositoryStarsJob < ApplicationJob
  queue_as :recover_restorable_repository_stars

  retry_on_dirty_exit

  READ_BATCH_SIZE = 1000
  WRITE_BATCH_SIZE = 100

  sig { params(restorable_id: Integer, user_id: T.nilable(Integer)).void }
  def perform(restorable_id:, user_id: nil)
    restorable = Restorable.find_by(id: restorable_id)
    return unless restorable&.restoring?([:restorable_repository_stars])

    user = Users.domain.by_id(user_id) if user_id

    batch = restorable.repository_stars.order(id: :asc).limit(READ_BATCH_SIZE)
    GitHub::PrefillAssociations.prefill_batch_method(batch, :repository)
    GitHub::PrefillAssociations.prefill_associations(batch, [:user], available_records: [user])

    batch.in_groups_of(WRITE_BATCH_SIZE, false) do |group|
      Star.throttle do
        with_write do
          group.each do |restorable_star|
            starring_user = restorable_star.user || user
            next if starring_user.nil?

            starred_repo = restorable_star.repository
            next if starred_repo.nil?

            Stars.domain.star_repository(
              user: starring_user,
              repository: starred_repo,
              context: "recovery",
              created_at: restorable_star.original_created_at,
            )
          end
        end
      end

      Restorable::RepositoryStar.throttle do
        with_write { group.each(&:destroy!) }
      end
    end

    if batch.size == READ_BATCH_SIZE
      self.class.perform_later(restorable_id: restorable_id, user_id: user&.id)
      return
    end

    with_write { restorable.restored(:restorable_repository_stars) }
  end
end
