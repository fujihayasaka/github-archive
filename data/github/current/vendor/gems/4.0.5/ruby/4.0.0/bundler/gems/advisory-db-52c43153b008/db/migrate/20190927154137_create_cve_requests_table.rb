# frozen_string_literal: true

class CreateCVERequestsTable < ActiveRecord::Migration[5.2]
  def change
    create_table :cve_requests do |t|
      t.string :ghsa_id, limit: 19, null: false

      # the user who requested, in case we want to get more information before making decision
      t.integer :actor_id, null: false
      t.string :actor_login, limit: 40, null: false # 40 char limit is from dotcom

      t.string :advisory_permalink, limit: 210, null: false # 141 is biggest name-with-owner, plus 19 for static https://github.com/ prefix, plus 40 for fixed length suffix = 200. plus 10 because why not
      t.string :advisory_state, limit: 20, null: false # longest current status is `published` at 9 chars. `withdrawn` if added would be 9.  Just giving us 20 for a bit of padding.

      # column types / limits mirror those in dotcom for these columns
      t.string :title, limit: 1024, null: false
      t.mediumblob :description, null: false
      t.string :ecosystem, limit: 50, null: false
      t.string :package, limit: 100, null: false

      # severity is an enum, and thus an integer
      t.integer :severity, null: true

      # in dotcom affected_versions is a blob for some reason?
      t.string :affected_versions, limit: 100
      # and patches is a mediumblob.
      t.string :patches, limit: 100

      t.index [:ghsa_id], unique: false # there could be multiple requests per ghsa, so unique is false
      t.timestamps
    end
  end
end
