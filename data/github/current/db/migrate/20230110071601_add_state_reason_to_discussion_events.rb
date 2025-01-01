# typed: true
class AddStateReasonToDiscussionEvents < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    add_column :discussion_events, :state_reason, :integer, limit: 1, null: true
  end
end
