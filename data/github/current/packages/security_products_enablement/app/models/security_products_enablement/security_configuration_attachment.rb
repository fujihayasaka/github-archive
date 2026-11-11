# typed: strict
# frozen_string_literal: true

# One row per repository per attachment operation. Self-contained work item
# carrying everything an attacher needs to attach a SecurityConfiguration to
# a Repository -- no joins back to the parent bulk request required.
#
# State machine (from the ADR):
#
#   pending   -> attaching -> attached  (attachment succeeded)
#                          -> failed    (attachment failed)
#             -> skipped               (config version is stale)
#             -> failed                (sweeper marks stale pending rows)
#   attaching -> failed                (sweeper marks stale attaching rows)
#
# See:
#   * https://github.com/github/security-products-enablement/issues/2796
#   * Attachment Pipeline ADR (2026-03-18)
class SecurityProductsEnablement::SecurityConfigurationAttachment < ApplicationRecord::Domain::SecurityProductsEnablement
  STATES = T.let({
    pending: 0,
    attaching: 1,
    attached: 2,
    failed: 3,
    skipped: 4,
  }.freeze, T::Hash[Symbol, Integer])

  # Map of allowed transitions per the ADR's state machine. Terminal states
  # (attached, failed, skipped) have no outbound transitions.
  VALID_STATE_TRANSITIONS = T.let({
    pending: [:attaching, :skipped, :failed].freeze,
    attaching: [:attached, :failed].freeze,
    attached: [].freeze,
    failed: [].freeze,
    skipped: [].freeze,
  }.freeze, T::Hash[Symbol, T::Array[Symbol]])

  # Request inputs are immutable after creation. Attachment rows represent a
  # single unit of work targeting one repository for one configuration owned
  # by one business/owner -- mutating these would silently retarget the work.
  attr_readonly :repository_id, :owner_id, :business_id, :security_configuration_id

  belongs_to :bulk_attachment,
    class_name: SecurityProductsEnablement::SecurityConfigurationBulkAttachment.name,
    optional: true
  belongs_to :security_configuration
  # `User` is STI; `Organization` is one subclass. Using `User.name` keeps the
  # association future-flexible (e.g. user-owned repos) without changing the
  # behavior for the current org-owned case.
  belongs_to :owner, class_name: User.name
  belongs_to :actor, class_name: User.name
  belongs_to :business, optional: true
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain

  enum :state, STATES, validate: true

  validates :security_configuration_id, presence: true
  validates :owner_id, presence: true
  validates :actor_id, presence: true
  validates :repository_id, presence: true
  # `security_configuration_version` is a snapshot of the
  # SecurityConfiguration's `version` at enqueue time. The sweeper / attacher
  # compares this snapshot against the live SecurityConfiguration#version to
  # detect stale work that should transition to `:skipped` rather than apply
  # an outdated configuration.
  # See: https://github.com/github/security-products-enablement/issues/2787
  validates :security_configuration_version, presence: true
  # `{}` is `blank?` but is a valid value for a JSON column.
  # TODO: replace with a Sorbet-typed struct + custom validator when the
  # stager starts carrying real options to attachment rows (deferred from
  # https://github.com/github/security-products-enablement/issues/2796).
  validates :attachment_options, exclusion: { in: [nil], message: :blank }
  validate :state_transition_allowed, if: :state_changed?, on: :update

  private

  sig { void }
  def state_transition_allowed
    # `on: :update` + `if: :state_changed?` guarantee both values are set;
    # a nil here would be a programmer bug and should fail loudly.
    previous = T.must(T.cast(state_was, T.nilable(String))).to_sym
    current = T.must(T.cast(state, T.nilable(String))).to_sym

    allowed = VALID_STATE_TRANSITIONS.fetch(previous, T.let([], T::Array[Symbol]))
    unless allowed.include?(current)
      errors.add(:state, "cannot transition from #{previous} to #{current}")
    end
  end
end
