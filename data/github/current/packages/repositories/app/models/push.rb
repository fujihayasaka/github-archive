# typed: true
# frozen_string_literal: true

class Push < ApplicationRecord::RepositoriesPushes
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include GH::Domain::Cache::Cachable::Dirtyable
  include ::Repositories::BelongsToRepository

  attribute :ref, StringFromBinary.new

  scope :branch_creation_or_deletion, -> { where(push_type: :branch_deletion).or(where(push_type: :branch_creation)) }
  scope :direct_push, -> { where.not(push_type: [:branch_deletion, :branch_creation, :pr_merge, :merge_queue_merge]) }

  validates :pushed_at, presence: true

  belongs_to_repository_via_domain
  belongs_to  :pusher, class_name: "User"

  before_create :set_push_type, if: -> do # rubocop:todo GitHub/AvoidActiveRecordCallbacks
    T.bind(self, Push)

    self.push_type.nil?
  end

  delete_in_background_with :repository,
    sharding_key: :repository_id,
    sharding_value_key: :id

  # rubocop:enable GitHub/AvoidActiveRecordCallbacks

  attr_writer :commits
  attr_accessor :push_options, :skip_after_commit_callbacks, :spokes_api_fail_fast_enabled

  enum :push_type, {
    push: 0,
    force_push: 1,
    branch_deletion: 2,
    branch_creation: 3,
    pr_merge: 4,
    merge_queue_merge: 5,
  }, suffix: true

  def set_push_type(merge_method: nil, merge_action: nil)
    if merge_action == :merge_queue_merge || merge_action == :api_merge_queue_merge
      self.push_type = :merge_queue_merge
    elsif merge_method.present?
      self.push_type = :pr_merge
    elsif before == GitHub::NULL_OID
      self.push_type = :branch_creation
    elsif after == GitHub::NULL_OID
      self.push_type = :branch_deletion
    elsif non_fast_forward?
      self.push_type = :force_push
    else
      self.push_type = :push
    end
  end

  # Queries the db to see if we've recorded a force_push push_type for this push
  # If we have, this push is a non-fast forward push. Otherwise, fallback to the
  # CommitsHelper#non_fast_forward? module method.
  sig { override.returns T::Boolean }
  def non_fast_forward?
    self.force_push_push_type? || super
  end

  include Pushes::PushRefUpdateMethods

  private

  sig { override.returns Push }
  def push
    self
  end
end
