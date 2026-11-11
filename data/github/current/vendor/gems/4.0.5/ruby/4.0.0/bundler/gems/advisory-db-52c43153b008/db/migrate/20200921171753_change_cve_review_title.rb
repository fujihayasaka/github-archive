# frozen_string_literal: true

class ChangeCVEReviewTitle < ActiveRecord::Migration[6.0]
  def up
    change_column :cve_reviews, :title, "varbinary(1024)", null: true, default: nil
  end

  def down
    change_column :cve_reviews, :title, "varchar(140)", null: true, default: nil
  end
end
