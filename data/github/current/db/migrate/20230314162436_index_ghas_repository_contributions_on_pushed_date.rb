# typed: true
class IndexGhasRepositoryContributionsOnPushedDate < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::BillingCollab)

  def change
    add_index :ghas_repository_contributions, :pushed_date, name: "index_ghas_repository_contributions_on_pushed_date"
  end
end
