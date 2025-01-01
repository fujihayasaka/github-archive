# typed: false
# frozen_string_literal: true

class AttributionInvitation < ApplicationRecord::Collab
  validate :source_and_target_both_in_owner_org

  include Workflow

  belongs_to :source, class_name: "Mannequin"
  belongs_to :target, class_name: "User"
  belongs_to :creator, class_name: "User"
  belongs_to :owner, class_name: "Organization"

  scope :present_mannequins_and_users, -> do
    all_present_invitation_ids = Set.new

    organization_ids = pluck(:owner_id).uniq
    organizations = Organization.where(id: organization_ids)

    organizations.each do |organization|
      invitations_for_org = where(owner: organization)

      invitation_source_ids = invitations_for_org.pluck(:source_id).uniq
      present_source_ids = organization.mannequins.where(id: invitation_source_ids).ids

      invitation_creator_ids = invitations_for_org.pluck(:creator_id).uniq
      present_creator_ids = organization.members.where(id: invitation_creator_ids).ids

      present_invitations = invitations_for_org.where(
        source_id: present_source_ids,
        creator_id: present_creator_ids
      )

      all_present_invitation_ids.merge(present_invitations.ids)
    end

    where(id: all_present_invitation_ids)
  end

  workflow :state do
    state :invited, 0 do
      event :accept, transitions_to: :accepted
      event :reject, transitions_to: :rejected
      event :cancel, transitions_to: :canceled
    end

    state :accepted, 1 do
      event :complete, transitions_to: :completed
    end
    state :rejected, 2

    state :completed, 3
    state :canceled, 4
  end

  after_create_commit :send_invitation_email, unless: :bypass_email

  def accept(*args, **kwargs)
    RewriteMannequinAssociationsJob.perform_later(source, target, self)
  end

  def display_state
    current_state.to_s.titleize
  end

  def cannot_accept_reason
    case current_state.name
    when :accepted, :completed
      "That attribution invitation has already been accepted"
    when :rejected
      "That attribution invitation could not be accepted "\
        "because it was already rejected"
    when :canceled
      "That attribution invitation could not be accepted "\
        "because it has been canceled."
    end
  end

  def cannot_reject_reason
    case current_state.name
    when :rejected
      "That attribution invitation has already been rejected"
    when :accepted, :completed
      "That attribution invitation could not be rejected "\
        "because it was already accepted"
    when :canceled
      "That attribution invitation could not be rejected "\
        "because it has been canceled"
    end
  end

  private

  def send_invitation_email
    AccountMailer.attribution_invitation_notification(self).deliver_later
  end

  def source_and_target_both_in_owner_org
    %i(source target).each do |e|
      unless self.public_send(e).organizations.include?(owner)
        errors.add(e, "must be a member of the #{owner.display_login} organization")
      end
    end
  end
end
