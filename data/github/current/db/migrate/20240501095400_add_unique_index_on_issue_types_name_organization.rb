# GitHub/DoNotAddUniqueIndexToExistingColumn is deliberately disabled,
# because we have done the work to ensure there are no duplicates that
# would cause a problem with adding this index.
# There is also ActiveRecord validation in place to prevent duplicates.

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class AddUniqueIndexOnIssueTypesNameOrganization < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    add_index :issue_types, [:name, :owner_id], unique: true
  end
end
