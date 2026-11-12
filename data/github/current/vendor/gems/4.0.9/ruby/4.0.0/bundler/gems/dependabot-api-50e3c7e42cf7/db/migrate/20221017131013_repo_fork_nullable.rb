# frozen_string_literal: true

class RepoForkNullable < ActiveRecord::Migration[7.0]
  def change
    change_column_null(
      :repos,
      :fork,
      from: true,
      to: false
    )
  end
end
