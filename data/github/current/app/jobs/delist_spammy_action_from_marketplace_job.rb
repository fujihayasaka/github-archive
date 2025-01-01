# typed: true
# frozen_string_literal: true

class DelistSpammyActionFromMarketplaceJob < ApplicationJob
  queue_as :marketplace
  retry_on_dirty_exit

  def perform(user:)
    return unless user&.spammy?

    actions_by_repository = RepositoryAction
      .joins(:repository)
      .where(state: :listed, repositories: { owner_id: user.id })
      .all

    actions_by_repository.each do |action|
      with_write do
        RepositoryAction.throttle { action.delisted! }
      end
    end

    actions_by_release = RepositoryAction
      .joins(:releases)
      .where(state: :listed, releases: { author_id: user.id })
      .all

    actions_by_release.each do |action|
      with_write do
        RepositoryAction.throttle { action.delisted! }
      end
    end
  end
end
