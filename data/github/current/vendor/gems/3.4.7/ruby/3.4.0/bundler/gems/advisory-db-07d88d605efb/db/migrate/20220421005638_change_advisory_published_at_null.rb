# frozen_string_literal: true

class ChangeAdvisoryPublishedAtNull < ActiveRecord::Migration[6.1]
  def change
    change_column_null :advisories, :published_at, false
  end
end
