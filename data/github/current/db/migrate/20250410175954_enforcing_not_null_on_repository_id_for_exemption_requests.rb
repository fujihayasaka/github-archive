# typed: true

class EnforcingNotNullOnRepositoryIdForExemptionRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_column_null :exemption_requests, :repository_id, false
  end
end
