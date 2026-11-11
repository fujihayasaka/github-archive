# typed: true
# frozen_string_literal: true

# TasklistBlock is a non-ActiveRecord model that wraps the raw hierarchy data
# from the IssuesGraph service into Ruby objects. In this case, it wraps the
# tasklist block data, known sometimes as the legacy name "tracking block."
class TasklistBlock < T::Struct
  include GitHub::Relay::GlobalIdentification

  const :parent_issue, TasklistBlocks::Issue
  const :key, TasklistBlocks::Key
  const :order, Integer
  const :items, T::Array[TasklistBlocks::Issue]
  const :name, String

  alias_method :title, :name

  def platform_type_name
    # This class is a PORO defined in app/platform/objects/tracking_block.rb
    "TrackingBlock"
  end

  def global_id
    key.primary_key&.uuid
  end
end
