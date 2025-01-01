# typed: true

class AddLanguageToCopilotEngagedOssUsers < ActiveRecord::Migration[7.0]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_engaged_oss_users, bulk: true do |t|
      t.string :language, limit: 20, null: false, default: "all", index: true, comment: "the language of the processor job (default all for all of github)"
      t.string :role, limit: 20, null: false, default: "read", index: true, comment: "the highest role of the user in this repo"
    end
  end
end
