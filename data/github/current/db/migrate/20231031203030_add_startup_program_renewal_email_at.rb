class AddStartupProgramRenewalEmailAt < ActiveRecord::Migration[7.2]
  def change
    add_column :businesses, :startup_program_renewal_email_at, :datetime, precision: 6, null: true, after: :part_of_startup_program
  end
end
