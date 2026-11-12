# frozen_string_literal: true

class AddRailsCommentIdToIgnoreCondition < ActiveRecord::Migration[6.0]
  def change
    add_column :ignore_conditions, :issue_comment_id, :bigint
  end
end
