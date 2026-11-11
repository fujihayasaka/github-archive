# typed: true
# frozen_string_literal: true

class AddIndexUsersOnBusinessIdTypeSoftDeletedAt < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Usersd)

  disable_ddl_transaction!

  def change
    add_index :users, [:business_id, :type, :soft_deleted_at],
      name: "index_users_on_business_id_type_soft_deleted_at",
      algorithm: :inplace
  end
end
