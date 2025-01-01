# typed: true
# frozen_string_literal: true

class AddApplicationAndCreatedAtIndexOnOauthAuthorizations < ActiveRecord::Migration[7.1]
  def up
    change_table :oauth_authorizations, bulk: true do |t|
      t.change :id,             :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_id,        :bigint, unsigned: true, null: false
      t.change :application_id, :bigint, unsigned: true, null: false

      t.index [:application_id, :application_type, :created_at], name: "index_authorizations_on_application_and_created_at"
    end
  end

  def down
    change_table :oauth_authorizations, bulk: true do |t|
      t.remove_index name: "index_authorizations_on_application_and_created_at"

      t.change :application_id, :int, null: false
      t.change :user_id,        :int, null: false
      t.change :id,             :int, null: false, auto_increment: true
    end
  end
end
