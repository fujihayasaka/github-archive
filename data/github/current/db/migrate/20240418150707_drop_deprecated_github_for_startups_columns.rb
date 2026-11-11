class DropDeprecatedGitHubForStartupsColumns < ActiveRecord::Migration[7.2]
  def up
    change_table :businesses, bulk: true do |t|
      t.remove :part_of_startup_program
      t.remove :startup_program_renewal_email_at
    end
  end

  def down
    change_table :businesses, bulk: true do |t|
      t.column :part_of_startup_program, :tinyint, null: true, default: 0
      t.column :startup_program_renewal_email_at, :datetime, precision: 6, null: true
    end
  end
end
