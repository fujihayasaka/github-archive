# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::PatreonUserComponent < ApplicationComponent
  sig { params(user: User).void }
  def initialize(user:)
    @user = user
  end

  private

  sig { returns(String) }
  def patreon_username
    @user.sponsors_patreon_username || ""
  end

  sig { returns(T.nilable(String)) }
  def patreon_link
    @user.sponsors_patreon_link
  end

  sig { returns(T::Boolean) }
  def render?
    @user.sponsors_patreon_user.present?
  end

  sig { returns(User) }
  attr_reader :user

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def sponsorable_settings
    if user.sponsors_patreon_user&.enabled_as_sponsorable?
      {
        icon: :check,
        icon_color: :success,
        text_color: "color-fg-success",
        label: "Enabled as sponsorable",
      }
    else
      {
        icon: :x,
        icon_color: :danger,
        text_color: "color-fg-danger",
        label: "Disabled as sponsorable",
      }
    end
  end
end
