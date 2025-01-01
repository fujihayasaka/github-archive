# typed: true
# frozen_string_literal: true

class BlackbirdOnboardReposJob < ApplicationJob

  queue_as :blackbird
  retry_on_dirty_exit

  sig { params(actor_id: Integer, repo_ids: T::Array[Integer]).void }
  def perform(actor_id, repo_ids)
    return if repo_ids.empty?
    return unless actor = User.find_by(id: actor_id)

    Repository.where(id: repo_ids).each do |repo|
      GlobalInstrumenter.instrument("blackbird.repository.onboard",
        actor: actor,
        repository: repo,
      )
    end
  end
end
