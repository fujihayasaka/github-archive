# typed: true
# frozen_string_literal: true

# Public: A pending action changing the ownership of an OauthApplication.
class OauthApplicationTransfer < ApplicationRecord::Domain::Integrations

  validates_presence_of  :application_id
  validates_presence_of  :requester_id
  validates_presence_of  :target_id
  validates_uniqueness_of :application_id

  validate :requester_can_admin_application
  validate :requester_and_target_are_different
  validate :requester_is_not_blocked_by_target
  validate :requester_is_not_spammy

  validates_presence_of  :responder_id, on: :update
  validate :responder_can_admin_target, on: :update

  # Public: The OauthApplication being transferred.
  belongs_to :application, class_name: "OauthApplication"

  # Public: The User who started this transfer.
  belongs_to :requester, class_name: "User"

  # Public: The User who finished this transfer.
  belongs_to :responder, class_name: "User"

  # Public: The User or Organization who ends up with owning the application.
  belongs_to :target, class_name: "User"

  # Public: Request an ownership change for application. Sends an email to the
  # target's owners asking them to respond to this transfer request.
  #
  # application     - An OauthApplication
  # target          - The User or Organization who will own the app after transfer
  # requester       - The User responsible for this request
  #
  # Returns a new OauthApplicationTransfer instance.
  # Raises ActiveRecord::RecordInvalid for bad application/target/requester combos.
  def self.start(application:, target:, requester:)
    xfer = create! do |x|
      x.application = application
      x.requester   = requester
      x.target      = target
    end

    unless target.adminable_by?(requester)
      AccountMailer.application_transfer_request(xfer).deliver_later
    end

    xfer
  end

  # Public: Approve the ownership change request for an application. This
  # record will be deleted at the end of the transfer process.
  #
  # responder - The User who approved to the request
  #
  # Returns self.
  def finish(responder)
    self.responder = responder
    save!

    transfer

    self
  end

  # Public: Indicates if the given user can cancel this transfer.
  #
  # Returns a Boolean.
  def cancelable_by?(user)
    requester == user || target&.adminable_by?(user)
  end

  # Internal: Actually perform the application transfer.
  def transfer
    application&.transfer_ownership_to target, requester: requester, responder: responder
  end

  protected

  def requester_can_admin_application
    return unless application.present?
    app = T.must(application)

    if app.owner.organization?
      unless app.owner.adminable_by?(requester)
        errors.add :requester, "can't administer this application"
      end
    elsif !app.owned_by?(requester)
      errors.add :requester, "doesn't own this application"
    end
  end

  def requester_and_target_are_different
    if application&.owner == target
      errors.add :requester, "can't also be the target"
    end
  end

  def responder_can_admin_target
    if target&.organization? && !target&.adminable_by?(responder)
      errors.add :responder, "can't administer the destination organization"
    end
  end

  def requester_is_not_blocked_by_target
    return true if target&.organization?
    if requester&.blocked_by?(target)
      errors.add :responder, "can't transfer at this time"
    end
  end

  def requester_is_not_spammy
    return true if target&.organization?
    if requester&.spammy?
      errors.add :responder, "can't transfer at this time"
    end
  end
end
