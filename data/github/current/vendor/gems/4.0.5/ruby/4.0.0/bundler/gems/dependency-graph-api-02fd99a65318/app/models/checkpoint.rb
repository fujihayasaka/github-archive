class Checkpoint < ApplicationRecord
  self.table_name = "dg_checkpoints"

  scope :with_name, -> (name) { where(name: name) }

  def self.names
    self.pluck(:name)
  end

  def reset!
    update(last_checkpointed_id: 0)
  end

  def set!(id)
    update(last_checkpointed_id: id)
  end

  def last_checkpointed_id
    super.to_i
  end
  alias_method :get, :last_checkpointed_id
end
