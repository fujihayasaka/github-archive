# typed: true
# frozen_string_literal: true

class AddSecurityContactEmailToBusinesses < ActiveRecord::Migration[8.1]
  self.use_connection_class ApplicationRecord::Domain::Users

  def up
    add_column :businesses, :security_contact_email, :string, limit: 255
  end

  def down
    remove_column :businesses, :security_contact_email
  end
end
