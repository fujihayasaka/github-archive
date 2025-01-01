# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::WaitlistsComponent < ApplicationComponent
  extend T::Sig

  sig { returns(T.any(User, Organization, Business)) }
  attr_reader :member

  sig { params(member: T.any(User, Organization, Business)).void }
  def initialize(member)
    @member = member
  end

  # a seat can only be uncancelled if it has been cancelled (the seat assignment has a pending cancellation)
  sig { returns(T::Boolean) }
  def render?
    early_access_memberships.any?
  end

  sig { returns(ActiveRecord::Relation) }
  def early_access_memberships
    EarlyAccessMembership.where(
      member_type: member.is_a?(Business) ? "Business" : "User",
      can_onboard: true,
      member_id: member.id,
      feature_slug: copilot_betas.map(&:feature_slug)
    )
  end

  sig { returns(T::Array[T.untyped]) }
  def copilot_betas
    Stafftools::BetaSignupController::BETAS.filter do |k, _v|
      k.start_with?("copilot-")
    end.values.map(&:new)
  end
end
