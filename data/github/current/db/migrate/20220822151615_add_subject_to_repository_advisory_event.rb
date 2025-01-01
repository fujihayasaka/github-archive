# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class AddSubjectToRepositoryAdvisoryEvent < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    add_column :repository_advisory_events, :subject_id, :bigint, unsigned: true, null: true, default: nil, comment: "User ID of the subject of the advisory event"
  end
end
