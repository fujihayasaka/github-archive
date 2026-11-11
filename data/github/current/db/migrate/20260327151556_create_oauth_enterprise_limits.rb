# typed: strict
# frozen_string_literal: true

class CreateOauthEnterpriseLimits < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Authentication)

  sig { void }
  def change
    create_table :oauth_enterprise_limits, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :app_id, null: false, unsigned: true
      t.bigint :user_id, null: false, unsigned: true
      t.bigint :request_owner_id, null: false, default: 0, unsigned: true
      t.boolean :higher_limit_eligible, null: false, default: false
      t.timestamps

      t.index [:user_id, :app_id], unique: true, name: "index_oauth_enterprise_limits_on_user_id_and_app_id"
    end
  end
end
