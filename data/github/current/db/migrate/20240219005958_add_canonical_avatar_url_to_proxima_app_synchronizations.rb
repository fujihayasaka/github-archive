class AddCanonicalAvatarUrlToProximaAppSynchronizations < ActiveRecord::Migration[7.2]
  def change
    add_column :proxima_app_synchronizations, :canonical_avatar_url, :text, null: true
  end
end
