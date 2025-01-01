# frozen_string_literal: true

class CreateAdvisoryReviewsAndCampaigns < ActiveRecord::Migration[7.0]
  def change
    create_table :campaigns do |t|
      t.string :name, null: false
      t.timestamps
      t.index :name, unique: true
    end

    create_table :advisory_reviews_campaigns do |t|
      t.bigint :campaign_id, null: false
      t.bigint :advisory_review_id, null: false
      t.timestamps
      t.index [:campaign_id, :advisory_review_id], unique: true, name: "index_on_campaign_id_and_advisory_review_id"
      t.index :advisory_review_id
    end
  end
end
