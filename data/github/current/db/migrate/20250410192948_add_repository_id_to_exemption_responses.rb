# typed: true

# rubocop:disable GitHub/AvoidRedundantIndex

class AddRepositoryIdToExemptionResponses < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :exemption_responses, bulk: true do |t|
      t.column :repository_id, :bigint, unsigned: true

      t.index [:exemption_request_id, :repository_id], name: "index_exemption_responses_exemption_request_and_repo_id"
    end
  end
end
