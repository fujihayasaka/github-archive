# typed: true
# frozen_string_literal: true

class AddEmailDomainNeighborsIndexToUserEmails < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_index :user_emails, [:normalized_domain, :created_at, :user_id]
  end
end
