# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::LimitedUserComponent < ApplicationComponent

  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { returns(T.nilable(Copilot::LimitedUser)) }
  attr_reader :limited_user

  # Adding these individually makes the function signature too long but we do whatever we can to appease the linter
  sig do
    params(
      copilot_user: Copilot::User,
      limited_user: T.nilable(Copilot::LimitedUser),
    ).void
  end
  def initialize(copilot_user, limited_user)
    @copilot_user = copilot_user
    @limited_user = limited_user
  end

  sig { returns(T::Boolean) }
  def render?
    limited_user.present?
  end

end
