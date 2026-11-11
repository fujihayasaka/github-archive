# frozen_string_literal: true

class BackfillIssueUpdateConfigIds < ActiveRecord::Migration[6.0]
  def up
    issue_count = Issue.count
    i = 1

    # Update the Issues in blocks of 10,000
    while i < issue_count
      ActiveRecord::Base.connection.execute("
        UPDATE issues
        INNER JOIN update_jobs
          ON issues.update_job_id = update_jobs.id
        SET issues.update_config_id = update_jobs.update_config_id
        WHERE issues.id >= #{i}
        AND issues.id < #{i} + 10000
      ")
      i += 10000
    end
  end

  def down
    Issue.update_all(update_config_id: nil)
  end
end
