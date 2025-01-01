# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::BlocksComponent < ApplicationComponent
  extend T::Sig

  sig do
    params(
      user: Copilot::User,
    ).void
  end
  def initialize(user:)
    @copilot_user = T.let(user, Copilot::User)
  end

  sig { returns(T::Boolean) }
  def render?
    blocks.any?
  end

  sig { returns(ActiveRecord::Relation) }
  memoize def blocks
    Copilot::AdministrativeBlock.where(blockable: @copilot_user).order("created_at DESC")
  end
end
