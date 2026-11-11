# typed: strict
# frozen_string_literal: true

class Sponsors::Profile::FeaturedUserComponent < ApplicationComponent
  sig { params(user: T.nilable(User), description: T.nilable(String)).void }
  def initialize(user:, description: nil)
    @user = user
    @description = description
  end

  private

  sig { returns(T.nilable(String)) }
  attr_reader :description

  sig { returns(T::Boolean) }
  def render?
    @user.present? && GitHub.sponsors_enabled?
  end

  sig { returns(User) }
  def user
    T.must(@user)
  end
end
