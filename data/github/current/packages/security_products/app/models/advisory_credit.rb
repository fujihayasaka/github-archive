# typed: true
# frozen_string_literal: true

class AdvisoryCredit < ApplicationRecord::Collab
  UnauthorizedActorError = Class.new(StandardError)

  include AdvisoryCredit::NewsiesAdapter
  include GitHub::RateLimitedCreation
  include Instrumentation::Model
  include AdvisoryDB::ScopedVulnerabilityHelper

  # Note: When a credit type is modified, make sure to update the REST API enums as well in
  # app/api/description/components/schemas/repository-advisory-credit-types.yaml
  enum :credit_type, {
    analyst: 0,
    finder: 1,
    reporter: 2,
    coordinator: 3,
    remediation_developer: 4,
    remediation_reviewer: 5,
    remediation_verifier: 6,
    tool: 7,
    sponsor: 8,
    other: 9
  }

  belongs_to :repository_advisory, optional: true
  belongs_to :vulnerability, optional: true
  belongs_to :scoped_vulnerability,
   ->(ac) { T.let(ac, AdvisoryCredit).retrieve_with_vulnerability_scope },
    foreign_key: :vulnerability_id,
    optional: true,
    inverse_of: :credits
  belongs_to :recipient, class_name: "User"
  belongs_to :creator, class_name: "User", optional: true

  def user
    creator
  end

  before_validation :set_ghsa_id, if: proc { T.bind(self, AdvisoryCredit); self.ghsa_id.nil? }
  validates :ghsa_id, :recipient_id, :creator_id, presence: true

  validate :repository_advisory_or_vulnerability_present
  validate :ensure_creator_is_not_blocked_by_recipient, on: :create

  before_create :auto_accept, if: :can_auto_accept?
  after_create_commit :instrument_create
  after_create_commit :instrument_accept, if: :accepted?
  after_create_commit :deliver_notifications
  after_create_commit :create_assigned_event
  after_destroy_commit :instrument_destroy
  after_destroy_commit :create_unassigned_event
  after_commit :touch_vulnerability
  after_commit :create_change_event, on: :update

  attr_readonly :ghsa_id, :recipient_id, :creator_id

  scope :pending, -> { where(accepted_at: nil, declined_at: nil) }
  scope :accepted, -> { where.not(accepted_at: nil) }

  scope :on_public_repository_advisories, -> {
    repository_ids = joins(:repository_advisory).merge(RepositoryAdvisory.published).pluck(:repository_id)
    public_repository_ids = Repository.active.public_scope.where(id: repository_ids).ids

    joins(:repository_advisory).where(repository_advisories: { repository_id: public_repository_ids })
  }

  def target_for_conditional_access
    advisory = repository_advisory
    return advisory.target_for_conditional_access if advisory
    vulnerability&.target_for_conditional_access
  end

  def async_target_for_conditional_access
    async_repository_advisory.then do |repository_advisory|
      next repository_advisory.async_target_for_conditional_access if repository_advisory

      async_vulnerability.then do |vulnerability|
        vulnerability&.async_target_for_conditional_access
      end
    end
  end

  def async_readable_by?(actor)
    # A credit is always readable by the credited user (even if they are spammy).
    # Whether the credit can be _accepted_ yet is a different question and depends
    # on the credited user's ability to read the credit's repository advisory
    return Promise.resolve(true) if actor.is_a?(User) && actor.id == recipient_id

    # If the creator or recipient is spammy, only those users with write access to the
    # advisory credit are allowed to see the credit.
    Promise.all([async_recipient, async_creator]).then do |recipient, creator|
      next async_writable_by?(actor) if recipient&.spammy? || creator&.spammy?

      # Whether or not the credit has been accepted, we'll need to know more about
      # its repository advisory, so first we load that if it exists.
      async_repository_advisory.then do |repository_advisory|
        if accepted?
          # If the credit is accepted, the viewer only needs to be able to read
          # either the associated repository advisory or security advisory
          # (vulnerability) in order to read the credit.
          repository_advisory&.async_readable_by?(actor).then do |repository_advisory_is_readable|
            # The repository_advisory_is_readable value is:
            # - true if a repository advisory exists and is readable
            # - false if a repository advisory exists but is not readable
            # - nil if no associated repository advisory exists
            next true if repository_advisory_is_readable

            # If there is no repository advisory or there is and it isn't
            # readable by the viewer, we check the vulnerability. The
            # vulnerability must exist and be readable by the viewer.
            async_vulnerability.then do |vulnerability|
              vulnerability&.async_readable_by?(actor) || false
            end
          end
        else
          # If the credit is *not* accepted, only those users with write access to
          # the advisory credit are allowed to see the pending or declined credit.
          async_writable_by?(actor)
        end
      end
    end
  end

  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  def async_writable_by?(actor)
    # A credit is always writable by the credited user.
    return Promise.resolve(true) if actor.is_a?(User) && actor.id == recipient_id

    # A credit is writable by any user that has write access to the underlying
    # repository advisory, if present.
    async_repository_advisory.then do |repository_advisory|
      repository_advisory&.async_writable_by?(actor) || false
    end
  end

  def writable_by?(actor)
    async_writable_by?(actor).sync
  end

  def pending?
    !accepted? && !declined?
  end

  def notified?
    notified_at?
  end

  def accepted?
    accepted_at?
  end

  def declined?
    declined_at?
  end

  def accept(actor:)
    raise UnauthorizedActorError unless actor == recipient

    already_accepted = T.let(false, T::Boolean)

    with_lock do
      already_accepted = accepted?
      next if already_accepted

      update!(accepted_at: Time.current, declined_at: nil)

      advisory = repository_advisory
      if advisory
        advisory.events.create!(
          actor: recipient,
          subject: recipient,
          event: "credit_accepted",
          changed_attribute: "credit",
          created_at: accepted_at,
        )
      end
    end

    instrument_accept unless already_accepted
  end

  def decline(actor:)
    raise UnauthorizedActorError unless actor == recipient

    already_declined = T.let(false, T::Boolean)

    with_lock do
      already_declined = declined?
      next if already_declined

      update!(accepted_at: nil, declined_at: Time.current)

      advisory = repository_advisory
      if advisory
        advisory.events.create!(
          actor: recipient,
          subject: recipient,
          event: "credit_declined",
          changed_attribute: "credit",
          created_at: declined_at,
        )
      end
    end

    instrument_decline unless already_declined
  end

  def state
    if accepted?
      :accepted
    elsif declined?
      :declined
    else
      :pending
    end
  end

  def given_to_self?
    recipient_id.present? && (recipient_id == creator_id)
  end

  def create_assigned_event
    advisory = repository_advisory
    if advisory
      advisory.events.create!(
        actor: creator,
        subject: recipient,
        event: "credit_assigned",
        changed_attribute: "credit",
        created_at: created_at,
        value_is: credit_type,
      )
    end
  end

  def create_change_event
    advisory = repository_advisory
    if advisory && credit_type_previously_changed?
      advisory.events.create!(
        actor: creator,
        subject: recipient,
        changed_attribute: "credit",
        created_at: updated_at,
        event: "credit_type_changed",
        value_is: credit_type,
        value_was: credit_type_previously_was,
      )
    end
  end

  def create_unassigned_event
    advisory = repository_advisory
    if advisory
      advisory.events.create!(
        actor: creator,
        subject: recipient,
        event: "credit_unassigned",
        changed_attribute: "credit",
        created_at: Time.now,
        value_is: credit_type,
      )
    end
  end

  private

  def ensure_creator_is_not_blocked_by_recipient
    if T.must(creator).blocked_by?(recipient)
      # In vast majority of cases creator will not see this message,
      # as they just don't get the recipient in the auto-complete text box.
      # We still need database level check to make sure they didn't craft
      # malicious payload or got blocked between adding row and saving.
      # We are trying to not disclose the reason similar to
      # discussion comment ensure_author_is_not_blocked
      errors.add :creator, "cannot give credit at this time"
    end
  end

  def repository_advisory_or_vulnerability_present
    errors.add(:base, "either repository_advisory or vulnerability should be present") unless repository_advisory_id.present? || vulnerability_id.present?
  end

  def instrument_create
    instrument_event(:create)
  end

  def instrument_destroy
    instrument_event(:destroy)
  end

  def auto_accept
    self.accepted_at = Time.current
  end

  # We don't need the recipient to accept credit if they are also the creator
  # of the credit, UNLESS the advisory is a Private Vulnerability Disclosure and
  # the recipient is the PVD author since we auto create a credit for them on
  # creation of the PVD advisory.
  def can_auto_accept?
    given_to_self? && !recipient_is_pvd_author?
  end

  def recipient_is_pvd_author?
    advisory = repository_advisory
    return false unless recipient_id.present? &&
      advisory.present? &&
      advisory.external? &&
      advisory.author_id.present?

    recipient_id == advisory.author_id
  end

  def instrument_accept
    instrument_event(:accept)
  end

  def instrument_decline
    instrument_event(:decline)
  end

  def event_payload
    repository = repository_advisory&.repository
    actor_id = GitHub.context[:actor_id]
    actor = actor_id && User.find_by(id: actor_id)

    payload = {
      advisory_credit: self,
      ghsa_id: ghsa_id,
      repository_advisory: repository_advisory,
      repo: repository,
      vulnerability: vulnerability,
      recipient: recipient,
      creator: creator,
      actor: actor,
    }

    if repository&.in_organization?
      payload[:org] = repository.organization
    end

    payload
  end

  def instrument_event(event)
    instrument(event)

    full_event = "advisory_credit.#{event}"
    GlobalInstrumenter.instrument(full_event, event_payload)
    GitHub.dogstats.increment(full_event)
  end

  def touch_vulnerability
    vulnerability&.touch
  end

  def set_ghsa_id
    self.ghsa_id = T.must(repository_advisory&.ghsa_id || vulnerability&.ghsa_id || scoped_vulnerability&.ghsa_id)
  end
end
