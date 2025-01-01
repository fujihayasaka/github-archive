# typed: true
# frozen_string_literal: true

class ChangeNetworkRootJob < ApplicationJob
  queue_as :change_network_root

  use_primaries ApplicationRecord::Repositories,
                ApplicationRecord::IamAbilities

  def perform(repo_id)
    return unless repo = Repository.find_by(id: repo_id)
    Failbot.push "gh.repo.id": repo.id
    repo.make_network_root!
  end
end
