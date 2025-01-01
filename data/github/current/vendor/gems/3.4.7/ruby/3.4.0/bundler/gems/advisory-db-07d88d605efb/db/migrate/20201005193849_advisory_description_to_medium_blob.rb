# frozen_string_literal: true

class AdvisoryDescriptionToMediumBlob < ActiveRecord::Migration[6.0]
  def up
    change_column :advisories, :description, "mediumblob"
  end

  def down
    change_column :advisories, :description, "text"
  end
end
