# frozen_string_literal: true

class BackfillPrUpdateConfigIds < ActiveRecord::Migration[6.0]
  def up
    pr_count = PullRequest.count
    i = 1

    # Update the PRs in blocks of 10,000
    while i < pr_count
      ActiveRecord::Base.connection.execute("
        UPDATE pull_requests
        INNER JOIN update_jobs
          ON pull_requests.update_job_id = update_jobs.id
        SET pull_requests.update_config_id = update_jobs.update_config_id
        WHERE pull_requests.id >= #{i}
        AND pull_requests.id < #{i} + 10000
      ")
      i += 10000
    end
  end

  def down
    PullRequest.update_all(update_config_id: nil)
  end
end
