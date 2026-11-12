# frozen_string_literal: true

class AddSourceCodeLocationToAdvisory < ActiveRecord::Migration[6.1]
  def change
    add_column :advisories, :source_code_location, "varbinary(1024)"
  end
end
