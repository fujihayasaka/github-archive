# typed: true
# frozen_string_literal: true

class AddIndexOnEmailsOnUserSignups < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_index :user_signups, :email
  end
end
