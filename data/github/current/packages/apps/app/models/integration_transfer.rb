# typed: true
# frozen_string_literal: true

# Public: A pending action changing the ownership of an Integration
class IntegrationTransfer < ApplicationRecord::Domain::Integrations
  validates_presence_of   :integration_id
  validates_presence_of   :requester_id
  validates_presence_of   :target_id
  validates_uniqueness_of :integration_id

  validate :requester_and_target_are_different
  validate :requester_is_not_blocked_by_target
  validate :requester_is_not_spammy

  validates_presence_of :responder_id,  on: :update
  validate :responder_can_admin_target, on: :update

  after_validation :surface_integration_validation_errors

  # Public: The Integration being transferred.
  belongs_to :integration
  validates_associated :integration

  # Public: The User who started this transfer.
  belongs_to :requester, class_name: "User"

  # Public: The User who finished this transfer.
  belongs_to :responder, class_name: "User"

  # Public: The User or Organization who ends up with owning the integration.
  belongs_to :target, class_name: "User"

  # Public: Request an ownership change for integration. Sends an email to the
  # target's owners asking them to respond to this transfer request.
  #
  # integration     - An Integration
  # target          - The User or Organization who will own the app after transfer
  # requester       - The User responsible for this request
  #
  # Returns a new IntegrationTransfer instance.
  # Raises ActiveRecord::RecordInvalid for bad integration/target/requester combos.
  def self.start(integration:, target:, requester:)
    xfer = create! do |x|
      x.integration = integration
      x.requester   = requester
      x.target      = target
    end

    unless target.adminable_by?(requester)
      AccountMailer.integration_transfer_request(xfer).deliver_later
    end

    xfer
  end

  # Public: Approve the ownership change request for an integration. This
  # record will be deleted at the end of the transfer process.
  #
  # responder - The User who approved to the request
  #
  # Returns self.
  def finish(responder, entry_point:)
    self.responder = responder
    save!

    transfer(entry_point: entry_point)

    self
  end

  # Public: Indicates if the given user can cancel this transfer.
  #
  # Returns a Boolean.
  def cancelable_by?(user)
    return true if requester == user || T.must(target).adminable_by?(user)

    # Allow app managers to cancel transfer requests. This also includes any org admin.
    ::Permissions::Enforcer.authorize(actor: user, action: :manage_all_apps, subject: T.must(integration).owner).allow? ||
      ::Permissions::Enforcer.authorize(actor: user, action: :manage_app, subject: integration).allow?
  end

  # Internal: Actually perform the integration transfer.
  def transfer(entry_point:)
    T.must(integration).transfer_ownership_to(target, requester: requester, responder: responder, entry_point: entry_point)
  end

  protected

  def requester_and_target_are_different
    return true if T.must(integration).owner != target
    errors.add :requester, "can't also be the target"
  end

  def responder_can_admin_target
    return true unless T.must(target).organization? && !T.must(target).adminable_by?(responder)
    errors.add :responder, "can't administer the destination organization"
  end

  def requester_is_not_blocked_by_target
    return true if T.must(target).organization?
    return true unless T.must(requester).blocked_by?(target)
    errors.add :responder, "can't transfer at this time"
  end

  def requester_is_not_spammy
    return true if T.must(target).organization?
    return true unless T.must(requester).spammy?
    errors.add :responder, "can't transfer at this time"
  end

  def surface_integration_validation_errors
    errors.delete(:integration) # Clear out the 'Invalid' error

    T.must(integration).errors.messages.each_pair do |key, validation_errors|
      validation_errors.each { |error| errors.add(key, error) }
    end
  end
end
