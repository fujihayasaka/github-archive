# frozen_string_literal: true

class MakeAllowAutomergingNonNullable < ActiveRecord::Migration[6.0]
  def change
    change_column_null :accounts, :allow_automerging, false
  end
end
