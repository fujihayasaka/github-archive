# GitHub/DoNotAddUniqueIndexToExistingColumn is deliberately disabled,
# because we have done the work to ensure there are no duplicates that
# would cause a problem with adding this index.
# See https://github.com/github/meao/issues/1833 for details.

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class AddUniqueKeyOnBusinessUserAccountsBusinessIdAndUserId < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_index :business_user_accounts, [:business_id, :user_id], unique: true
  end
end
