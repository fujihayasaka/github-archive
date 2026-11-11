class CreateTeamOrganizationPricingDemo < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    create_table :team_organization_pricing_demos, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, index: { unique: true }, null: false
      t.bigint :referral_organization_id, unsigned: true, null: false
      t.bigint :repository_id, unsigned: true, index: { unique: true }, null: false
      t.timestamps
    end
  end
end
