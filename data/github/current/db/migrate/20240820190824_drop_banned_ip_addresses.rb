# typed: true
# frozen_string_literal: true

class DropBannedIpAddresses < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def change
    drop_table :banned_ip_addresses
  end
end
