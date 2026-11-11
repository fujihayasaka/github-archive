# typed: true
# frozen_string_literal: true

class RefUpdate < ApplicationRecord::Domain::RepositoriesPushes
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include GH::Domain::Cache::Cachable::Dirtyable
  include ::Repositories::BelongsToRepository

  attribute :ref, StringFromBinary.new

  scope :branch_creation_or_deletion, -> { where(ref_update_type: :branch_deletion).or(where(ref_update_type: :branch_creation)) }
  scope :direct_ref_update, -> { where.not(ref_update_type: [:branch_deletion, :branch_creation, :pr_merge, :merge_queue_merge]) }

  belongs_to_repository_via_domain
  belongs_to  :push

  before_create :set_ref_update_type, if: -> do # rubocop:todo GitHub/AvoidActiveRecordCallbacks
    T.bind(self, RefUpdate)
    self.ref_update_type.nil?
  end

  delete_in_background_with :repository,
    sharding_key: :repository_id,
    sharding_value_key: :id

  # rubocop:enable GitHub/AvoidActiveRecordCallbacks

  attr_writer :commits
  attr_accessor :push_options, :skip_after_commit_callbacks, :spokes_api_fail_fast_enabled

  serialize :after_oid, coder: GitHub::Hex
  serialize :before_oid, coder: GitHub::Hex

  alias_attribute :before, :before_oid
  alias_attribute :after, :after_oid

  enum :ref_update_type, {
    push: 0,
    force_push: 1,
    branch_deletion: 2,
    branch_creation: 3,
    pr_merge: 4,
    merge_queue_merge: 5,
  }, suffix: true

  def set_ref_update_type(merge_method: nil, merge_action: nil)
    if merge_action == :merge_queue_merge || merge_action == :api_merge_queue_merge
      self.ref_update_type = :merge_queue_merge
    elsif merge_method.present?
      self.ref_update_type = :pr_merge
    elsif before_oid == GitHub::NULL_OID
      self.ref_update_type = :branch_creation
    elsif after_oid == GitHub::NULL_OID
      self.ref_update_type = :branch_deletion
    elsif non_fast_forward?
      self.ref_update_type = :force_push
    else
      self.ref_update_type = :push
    end
  end

  sig { override.returns(T.nilable(Users::IUser)) }
  def pusher
    push&.pusher
  end

  # Queries the db to see if we've recorded a force_push ref_update_type.
  # If we have, this is a non-fast forward ref_update. Otherwise, fallback to the
  # CommitsHelper#non_fast_forward? module method.
  sig { override.returns T::Boolean }
  def non_fast_forward?
    self.force_push_ref_update_type? || super
  end

  def instrument_dependency_graph_snapshot_request
    push&.instrument_dependency_graph_snapshot_request
  end

  def create_check_suites
    push&.create_check_suites
  end

  include Pushes::PushRefUpdateMethods
end
