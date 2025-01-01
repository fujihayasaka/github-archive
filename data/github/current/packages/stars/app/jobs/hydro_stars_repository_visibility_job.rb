# typed: true
# frozen_string_literal: true

class HydroStarsRepositoryVisibilityJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_stars_repository_visibility

  retry_on_dirty_exit

  BATCH_SIZE = 1000

  sig { void }
  def perform
    return unless repository.private?

    with_star_batch do |star_batch|
      next :stop unless repository.reload.private?

      promises = star_batch.map do |star|
        repository.async_readable_by?(star.user).then { |readable| star unless readable }
      end
      to_unstar = Promise.all(promises).sync.compact
      next unless to_unstar.any?

      restorable = load_restorable
      with_write do
        restorable&.save_stars(to_unstar)
        to_unstar.each do |star|
          Star.throttle { star.user.unstar(repository) }
        end
      end
    end

    restorable = load_restorable
    with_write { restorable&.save_stars_complete }
  end

  private

  def with_star_batch
    last_id = T.let(-1, Integer)
    loop do
      star_batch = Star
        .for_repository(repository)
        .where("id > ?", last_id)
        .order(id: :asc)
        .limit(BATCH_SIZE)
        .includes(:user)
        .to_a
      return if star_batch.empty?
      return if (yield star_batch) == :stop
      return if star_batch.size < BATCH_SIZE

      last_id = T.must(star_batch.last).id
    end
  end

  sig { returns(T.nilable(Restorable::IPrivateVisibilityChangedRepository)) }
  def load_restorable
    return nil unless repository.feature_enabled?(:visibility_change_recovery_storage)

    Restorable::VisibilityChangedRepository.continue(repository)
  end
end
