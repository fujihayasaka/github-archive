# frozen_string_literal: true

class AddCommitMessagePrefixDevelopment < ActiveRecord::Migration[6.0]
  def change
    add_column(
      :update_configs,
      :commit_message_prefix_development,
      :string,
      limit: 15,
    )
  end
end
