# frozen_string_literal: true

class StoreReallyLongLanguageNames < ActiveRecord::Migration[6.0]
  def up
    change_column :repos, :primary_language, :string, limit: 255
  end

  def down
    change_column :repos, :primary_language, :string, limit: 20
  end
end
