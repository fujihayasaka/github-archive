# typed: true
# frozen_string_literal: true

# A transfer of an organization from one enterprise to another.
class BusinessOrganizationTransfer < ApplicationRecord::Domain::Users
  include GitHub::Relay::GlobalIdentification
  include ActionView::Helpers::TextHelper

  belongs_to :organization, class_name: "Organization"
  belongs_to :from_business, class_name: "Business"
  belongs_to :to_business, class_name: "Business"
  belongs_to :actor, class_name: "User"

  validates_presence_of :organization, :from_business, :to_business, :actor
  validate :ensure_organization_belongs_to_from_business, on: :create
  validate :ensure_from_business_and_to_business_are_different
  validate :ensure_org_can_be_transferred
  validate :ensure_from_business_can_transfer_orgs
  validate :ensure_to_business_can_receive_orgs
  validate :ensure_to_business_has_sufficient_seats
  validate :ensure_actor_can_perform_transfer

  scope :in_progress, -> { where("completed_at IS NULL AND failed_at IS NULL") }
  scope :not_complete, -> { where("completed_at IS NULL") }
  scope :failed, -> { where("failed_at IS NOT NULL") }
  scope :completed, -> { where("completed_at IS NOT NULL") }

  after_save :update_business_license_usage
  after_destroy :update_business_license_usage

  # Public: Perform the transfer.
  #
  # Returns Business::OrganizationMembership or nil.
  def perform!
    unless valid?
      fail! reason: errors.full_messages.to_sentence
      return nil
    end

    new_org_membership = nil
    begin
      new_org_membership = T.must(from_business).transfer_organization organization, to_business, actor: actor

      if new_org_membership.valid?
        complete!
      else
        fail! reason: new_org_membership.errors.full_messages.to_sentence
      end
    rescue ArgumentError,
      Business::CannotRemoveOrganizationError,
      Business::OrganizationIsNotMemberError,
      Business::OrganizationHasNoAdminsError => e

      fail! reason: e.message
    end

    new_org_membership
  end

  # Public: Is the transfer in progress?
  #
  # Returns Boolean
  def in_progress?
    !completed? && !failed?
  end

  # Public: Did the transfer complete successfully?
  #
  # Returns Boolean
  def completed?
    completed_at.present?
  end

  # Public: Did the transfer fail?
  #
  # Returns Boolean
  def failed?
    failed_at.present?
  end

  # Public: Should the transfer actor details be shown?
  #
  # Returns Boolean
  def show_actor?
    !!actor && !site_admin_transfer?
  end

  # Public: Mark the transfer as failed.
  #
  # reason - Optional String representing the reason the transfer failed.
  #
  # Returns nothing
  def fail!(reason: nil)
    update_column :failed_reason, reason
    touch :failed_at
    instrument_fail
    BusinessMailer.organization_transfer_failed(self).deliver_later
  end

  def business_org_has_marketplace_subscriptions?
    organization_belongs_to_from_business? &&
      from_business&.plan_subscription&.active_marketplace_listing_subscription_items&.where(organization_id: T.must(organization).id)&.any?
  end

  private

  def complete!
    touch :completed_at
    instrument_complete
    BusinessMailer.organization_transfer_completed(self).deliver_later
  end

  def instrument_complete
    # The `org.transfer_outgoing` event is logged with `business` and `business_id`
    # of the `from_business` to ensure it appears in the audit log of `from_business`.
    GitHub.instrument \
      "org.transfer_outgoing",
      org: T.must(organization).display_login,
      org_id: T.must(organization).id,
      business: T.must(from_business).slug,
      business_id: T.must(from_business).id,
      actor: actor,
      from_business: T.must(from_business).slug,
      from_business_id: T.must(from_business).id,
      to_business: T.must(to_business).slug,
      to_business_id: T.must(to_business).id,
      transfer: self

    # The `org.transfer` event is logged with `business` and `business_id`
    # of the `to_business` to ensure it appears in the audit log of `to_business`.
    T.must(organization).instrument \
      :transfer,
      actor: actor,
      from_business: T.must(from_business).slug,
      from_business_id: T.must(from_business).id,
      to_business: T.must(to_business).slug,
      to_business_id: T.must(to_business).id,
      transfer: self

    GlobalInstrumenter.instrument \
      "enterprise_account.organization_transfer",
      organization_id: organization_id,
      source_enterprise_id: from_business_id,
      destination_enterprise_id: to_business_id,
      actor_id: actor_id,
      completed_at: completed_at,
      site_admin_transfer: site_admin_transfer
  end

  def instrument_fail
    GlobalInstrumenter.instrument \
      "enterprise_account.organization_transfer",
      organization_id: organization_id,
      source_enterprise_id: from_business_id,
      destination_enterprise_id: to_business_id,
      actor_id: actor_id,
      failed_at: failed_at,
      failed_reason: failed_reason,
      site_admin_transfer: site_admin_transfer
  end

  def organization_belongs_to_from_business?
    Business.from_org_id(T.must(organization).id) == from_business
  end

  def actor_can_perform_transfer?
    site_admin_transfer || (T.must(from_business).owner?(actor) && T.must(to_business).owner?(actor))
  end

  def ensure_organization_belongs_to_from_business
    return if organization.blank? || from_business.blank?

    unless organization_belongs_to_from_business?
      errors.add(:base, "The organization to transfer must belong to the source enterprise.")
    end
  end

  def ensure_from_business_and_to_business_are_different
    return if from_business.blank? || to_business.blank?

    if from_business == to_business
      errors.add(:base, "The source enterprise cannot be the destination enterprise.")
    end
  end

  def ensure_org_can_be_transferred
    return if organization.blank?

    if T.must(organization).admins.empty?
      errors.add(:base, "The organization to transfer must have owners.")
    end

    if business_org_has_marketplace_subscriptions?
      errors.add(:base, "The organization to transfer must not have Marketplace App subscriptions.")
    end
  end

  def ensure_actor_can_perform_transfer
    return if actor.blank? || to_business.blank? || from_business.blank?

    unless actor_can_perform_transfer?
      errors.add(:base, "You must be an owner of both enterprises to perform this transfer.")
    end
  end

  def ensure_from_business_can_transfer_orgs
    ensure_business_eligible_for_action(from_business, "source", "transfer")
  end

  def ensure_to_business_can_receive_orgs
    ensure_business_eligible_for_action(to_business, "destination", "receive")
  end

  def ensure_business_eligible_for_action(business, description, action)
    return if business.blank? || actor.blank?

    if business.spammy?
      errors.add(:base, "The #{description} enterprise has been flagged and cannot #{action} organizations.")
    elsif !business.default_managed?
      errors.add(:base, "The #{description} enterprise is externally managed and cannot #{action} organizations.")
    elsif business.trial? && !site_admin_transfer
      errors.add(:base, "The #{description} enterprise is a trial and cannot #{action} organizations.")
    end
  end

  def ensure_to_business_has_sufficient_seats
    return if organization.blank? || to_business.blank?
    # bypass seat check validate for metered plan, can add unlimited seats
    return if T.must(to_business).metered_plan?

    unless T.must(to_business).has_sufficient_licenses_for_organization?(T.must(organization))
      seats_needed = T.must(to_business).additional_licenses_required_for_organization(T.must(organization))
      errors.add :base,
        "The destination enterprise needs #{pluralize(seats_needed, "additional seat")} to transfer #{organization}."
    end
  end

  def update_business_license_usage
    T.must(from_business).update_license_usage
    T.must(to_business).update_license_usage
  end
end
