# typed: true

class DropReviewRequestDelegationIncludedMembers < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    drop_table :review_request_delegation_included_members, if_exists: true
  end
end
