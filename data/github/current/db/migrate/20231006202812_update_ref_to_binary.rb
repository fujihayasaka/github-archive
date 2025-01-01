class UpdateRefToBinary < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)
  def up
    change_table :deployments, bulk: true do |t|
      t.change :ref, :binary, limit: 1024, default: nil
    end
  end

  def down
    t.change :ref, :string, limit: 255, default: nil
  end
end
