# typed: true

class DropFlipperFeatureIdFromFeatures < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::FeaturePreviews)

  def up
    change_table :features, bulk: true do |t|
      t.remove_index name: "index_features_on_flipper_feature_id"
      t.remove_index name: "idx_on_published_at_flipper_feature_id_legal_agreement_required"
      t.remove :flipper_feature_id
    end
  end

  def down
    change_table :features, bulk: true do |t|
      t.bigint :flipper_feature_id, unsigned: true
      t.index :flipper_feature_id, unique: true, name: "index_features_on_flipper_feature_id"
      t.index [:published_at, :flipper_feature_id, :legal_agreement_required], name: "idx_on_published_at_flipper_feature_id_legal_agreement_required"
    end
  end
end
