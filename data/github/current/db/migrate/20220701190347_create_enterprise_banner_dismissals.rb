# typed: true

class CreateEnterpriseBannerDismissals < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    create_table :enterprise_banner_dismissals, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.belongs_to :enterprise_banner, type: :bigint, unsigned: true, null: false, index: false
      t.belongs_to :user, type: :bigint, unsigned: true, null: false, index: true
      t.index [:enterprise_banner_id, :user_id], name: "index_dismissals_on_enterprise_banner_id_and_user_id", unique: true
    end
  end

  def down
    drop_table :enterprise_banner_dismissals, if_exists: true
  end
end
