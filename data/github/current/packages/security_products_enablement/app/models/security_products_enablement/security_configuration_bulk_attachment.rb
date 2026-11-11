# typed: strict
# frozen_string_literal: true

# One row per bulk attachment request. Captures the customer's intent to attach
# a configuration to a set of repositories and tracks staging progress via a
# cursor.
#
# The state machine is driven by three actors:
#
#   * planner  -- ready -> staging, staged -> completed
#   * stager   -- staging -> ready, staging -> staged, staging -> cancelled
#   * sweeper  -- staging -> ready (recovery), staging -> failed
#
# See:
#   * https://github.com/github/security-products-enablement/issues/2791
#   * Attachment Pipeline ADR (2026-03-18)
class SecurityProductsEnablement::SecurityConfigurationBulkAttachment < ApplicationRecord::Domain::SecurityProductsEnablement
  self.table_name = "security_configuration_bulk_attachments"

  STATES = T.let({
    ready: 0,
    staging: 1,
    staged: 2,
    completed: 3,
    failed: 4,
    cancelled: 5,
  }.freeze, T::Hash[Symbol, Integer])

  # Map of allowed transitions per the ADR's state machine. Terminal states
  # (completed, failed, cancelled) have no outbound transitions.
  VALID_STATE_TRANSITIONS = T.let({
    ready: [:staging].freeze,
    staging: [:ready, :staged, :cancelled, :failed].freeze,
    staged: [:completed].freeze,
    completed: [].freeze,
    failed: [].freeze,
    cancelled: [].freeze,
  }.freeze, T::Hash[Symbol, T::Array[Symbol]])

  # Immutable inputs that describe the original request. The cursor and state
  # fields (`state`, `state_reason`, `staging_cursor`, `staging_attempt`,
  # `attachment_progress`) advance over the lifetime of the record; everything
  # else is frozen at creation time.
  attr_readonly :parent_id,
    :security_configuration_id,
    :security_configuration_version,
    :business_id,
    :owner_id,
    :actor_id,
    :repository_selection,
    :attachment_options

  belongs_to :security_configuration
  belongs_to :owner, class_name: User.name
  belongs_to :actor, class_name: User.name
  belongs_to :business, optional: true
  belongs_to :parent,
    class_name: name,
    optional: true,
    inverse_of: :children
  has_many :children,
    class_name: name,
    foreign_key: :parent_id,
    inverse_of: :parent

  enum :state, STATES, validate: true

  validates :security_configuration, presence: true
  validates :owner, presence: true
  validates :actor, presence: true
  validates :security_configuration_version, presence: true
  # Use not-nil checks for JSON columns -- `{}` is `blank?` but is a valid
  # value (e.g., a fresh attachment with no recorded progress).
  validates :repository_selection, exclusion: { in: [nil], message: :blank }
  validates :attachment_options, exclusion: { in: [nil], message: :blank }
  validates :attachment_progress, exclusion: { in: [nil], message: :blank }
  validate :state_transition_allowed, if: :state_changed?, on: :update

  private

  sig { void }
  def state_transition_allowed
    # The `on: :update` guard ensures this only runs on persisted records whose
    # `state` has just changed, so both values must be present. A nil here would
    # indicate a bug (e.g., the validation being wired up on `:create`), so we
    # raise rather than silently skipping the check.
    previous = T.must(T.cast(state_was, T.nilable(String))).to_sym
    current = T.must(T.cast(state, T.nilable(String))).to_sym

    allowed = VALID_STATE_TRANSITIONS.fetch(previous, T.let([], T::Array[Symbol]))
    unless allowed.include?(current)
      errors.add(:state, "cannot transition from #{previous} to #{current}")
    end
  end
end
