# typed: true

class ExtendRepositoryTopicLength < ActiveRecord::Migration[7.1]
  def up
    change_table :topics, bulk: true do |t|
      t.change :name, :string, limit: 50, null: false
      t.change :id, :bigint, unsigned: true
    end
  end

  def reversible
    # Not actually reversible; this is just to avoid a warning.
    # The data would be truncated if this migration were reversed,
    # and that makes other warnings or errors appear if implemented.
  end
end
