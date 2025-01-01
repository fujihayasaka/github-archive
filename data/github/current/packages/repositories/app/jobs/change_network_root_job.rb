# typed: true
# frozen_string_literal: true

class ChangeNetworkRootJob < ApplicationJob
  queue_as :change_network_root
  retry_on_dirty_exit

  use_primaries ApplicationRecord::Repositories,
                ApplicationRecord::IamAbilities

  def perform(repo_id)
    repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: repo_id)
    end
    return unless repo
    Failbot.push "gh.repo.id": repo.id
    repo.make_network_root!
  end
end
