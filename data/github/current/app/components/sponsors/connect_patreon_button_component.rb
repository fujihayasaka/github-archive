# typed: strict
# frozen_string_literal: true

class Sponsors::ConnectPatreonButtonComponent < ApplicationComponent
  extend T::Sig

  SCOPES = T.let([:sponsor, :sponsorable].freeze, T::Array[Symbol])

  # user  - User or Organization to connect their Patreon account to
  # scope - Symbol representing scope permissions to be given to User or Organization that is connecting to Patreon.
  #   Must be :sponsor or :sponsorable
  # sponsorable_login - String representing the login of the User or Organization whose checkout page the connecting
  #                     user should return to after connecting their Patreon account. Defaults to nil.
  sig { params(user: T.nilable(T.any(User, Organization)), scope: Symbol, sponsorable_login: T.nilable(String)).void }
  def initialize(user:, scope: :sponsor, sponsorable_login: nil)
    @user = user
    @scope = T.let(fetch_or_fallback(SCOPES, scope, :sponsor), Symbol)
    @sponsorable_login = sponsorable_login
  end

  private

  sig { returns(T.nilable(T.any(User, Organization))) }
  attr_reader :user

  sig { returns(Symbol) }
  attr_reader :scope

  sig { returns(T.nilable(String)) }
  attr_reader :sponsorable_login

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.sponsors_enabled?
    user&.sponsors_patreon_user.nil?
  end

  sig { returns(T::Hash[Symbol, String]) }
  def params
    { scope => user&.display_login }
  end
end
