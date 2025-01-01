# typed: true
# rubocop:disable GitHub/MigrationCrossSchemaDomainConnection
class CreatePullRequestLastPushesIdSeq < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::VT)

  def change
    create_table :pull_request_last_pushes_id_seq, comment: "vitess_sequence", id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :id, primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.bigint :next_id, unsigned: true
      t.bigint :cache, unsigned: true
    end

    create_sequence(:pull_request_last_pushes_id_seq)
  end
end
