# typed: false
# frozen_string_literal: true

class GistDiskUsageJob < ApplicationJob
  queue_as :gist_disk_usage
  retry_on_dirty_exit

  def perform(gist_id)
    gist = Gist.find_by_id(gist_id)

    return unless gist

    Failbot.push("gh.gist.id": gist.id)
    with_write do
      gist.update_disk_usage
    end
  end
end
