# typed: true
# frozen_string_literal: true

class MaintainTrackingRefJob < ApplicationJob
  use_replicas ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Spokes

  retry_on_dirty_exit
  queue_as do
    _, _, opts = T.unsafe(self).arguments

    if opts && opts[:importing]
      :maintain_tracking_ref_importing
    else
      :maintain_tracking_ref
    end
  end

  retry_on GitHub::DGit::ThreepcError
  retry_on GitHub::DGit::ThreepcBusyError
  retry_on GitHub::DGit::ThreepcFailedToLock

  def perform(pull_request_id, actor_id, options = {})
    ActiveRecord::Base.connected_to_many([ApplicationRecord::Repositories], role: :reading) do
      pull = PullRequest.find(pull_request_id)
      actor = User.find_by(id: actor_id)

      Failbot.push(
        "gh.repo.id": pull.repository_id,
        "gh.pull_request.id": pull.id
      )

      pull.maintain_tracking_ref_with_retries(actor, priority: :low)
    end
  end

end
