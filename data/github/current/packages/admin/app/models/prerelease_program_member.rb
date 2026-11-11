# typed: true
# frozen_string_literal: true

class PrereleaseProgramMember < ApplicationRecord::Domain::Users
  include GitHub::Relay::GlobalIdentification

  VALID_MEMBER_TYPES = %w[User Business]

  belongs_to :member, polymorphic: true, foreign_key: "member_id"
  validates_presence_of :member
  validates :member_type, presence: true, inclusion: { in: VALID_MEMBER_TYPES }

  belongs_to :actor, class_name: "User"
  validates_presence_of :actor
  validate :actor_is_a_user

  # Public: Is the user/org/business a member of the pre-release program?
  #
  # member - A User (user or org) or Business to check for membership
  #
  # Returns true if member is in the pre-release program, otherwise false.
  def self.member?(member)
    if member.is_a?(User)
      exists?(member_id: member.id, member_type: "User")
    elsif member.is_a?(Business)
      exists?(member_id: member.id, member_type: "Business")
    end
  end

  private

  def actor_is_a_user
    return unless actor
    errors.add(:actor, "must be a user") unless T.must(actor).user?
  end
end
