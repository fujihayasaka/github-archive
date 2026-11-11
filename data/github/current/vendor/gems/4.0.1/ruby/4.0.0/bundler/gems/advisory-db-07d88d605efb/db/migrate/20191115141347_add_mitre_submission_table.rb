# frozen_string_literal: true

class AddMITRESubmissionTable < ActiveRecord::Migration[5.2]
  def change
    create_table :mitre_cve_submissions do |t|
      # GHSA is the key for tying cve submissions to CVEReviews/CVERequests or Advisories/AdvisoryReviews
      t.string :ghsa_id, limit: 19, null: false

      # pull request URL in which CVE was submited to mitre
      # store the whole URL, since the to/from repo could change
      # right now, they tend to look like this: `https://github.com/CVEProject/cvelist/pull/2608`, which is 48 characters
      t.string :pull_request_url, limit: 100, default: nil, null: true

      t.index [:ghsa_id], unique: true
      t.timestamps
    end
  end
end
