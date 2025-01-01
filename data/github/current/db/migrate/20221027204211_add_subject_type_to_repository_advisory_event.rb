# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class AddSubjectTypeToRepositoryAdvisoryEvent < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    change_table(:repository_advisory_events, bulk: true) do |t|
      t.column :subject_type, :string, limit: 30, default: "User", null: false, after: :subject_id, comment: "Class of the advisory event subject (eg. User or Team)"
      t.index  [:subject_id, :subject_type], name: "index_repository_advisory_events_on_subject_id_and_subject_type"
    end
  end
end
