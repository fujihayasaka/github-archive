# typed: true
# frozen_string_literal: true

# Ensures that people who starred the repository are people who are allowed
# to star it. Useful for private repositories and transferring between
# owners who may change who has access to the repository (collabs -> teams).
class HydroCorrectStargazersRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_correct_stargazers_repository_transferred

  # Public: process a Hydro message
  #
  # Returns nothing
  def perform
    with_write do
      correct_stargazers
    end
  end

  private

  def correct_stargazers
    return if repository.public?

    stargazer_ids = Star.where(starrable_id: repository.id, starrable_type: "Repository").pluck(:user_id)

    stargazer_ids.each_slice(Repository::REPO_STARGAZERS_BATCH_SIZE) do |stargazer_ids_slice|
      stargazers = User.where(id: stargazer_ids_slice)

      Promise.all(stargazers.map do |user|
        repository.async_readable_by?(user).then do |readable|
          user.unstar(repository) unless readable
        end
      end).sync
    end
  end
end
