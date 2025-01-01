# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::AdministrativeBlockComponent < ApplicationComponent
  extend T::Helpers

  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { params(copilot_user: Copilot::User).void }
  def initialize(copilot_user)
    @copilot_user = copilot_user
    @blocked      = T.let(copilot_user.administrative_blocked?, T::Boolean)
  end

  sig { returns(T::Boolean) }
  def blocked?
    @blocked
  end

  sig { returns(T::Boolean) }
  def user_is_trusted?
    TrustTiers::Tier.for_billable_owner(@copilot_user).tier <= TrustTiers::Tier::TRUSTED
  end
end
