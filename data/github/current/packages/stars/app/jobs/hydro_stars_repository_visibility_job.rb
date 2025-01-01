# typed: true
# frozen_string_literal: true

class HydroStarsRepositoryVisibilityJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_stars_repository_visibility

  retry_on_dirty_exit

  sig { void }
  def perform
    return unless repository.private?

    stargazer_ids = Star.where(starrable_id: repository.id, starrable_type: "Repository").pluck(:user_id)

    stargazer_ids.each_slice(1000) do |stargazer_ids_slice|
      stargazers = User.where(id: stargazer_ids_slice)

      Promise.all(
        stargazers.map do |user|
          repository.async_readable_by?(user).then do |readable|
            with_write do
              user.unstar(repository) unless readable
            end
          end
        end).sync
    end
  end
end
