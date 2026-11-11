# typed: true
# frozen_string_literal: true

class ProgrammaticAccessBot < User
  include Botable

  LOGIN_SUFFIX = "[api]"
  LOGIN_REGEX = %r{
    \A                               # Beginning of String
    ([a-zA-Z0-9]+(?:-[a-zA-Z0-9]+)*) # [1] slug
    #{ Regexp.quote LOGIN_SUFFIX }   # string literal "[bot]"
    \z                               # End of String
  }x                                 # x: ignore whitespace
  MAX_SLUG_LENGTH = User::LOGIN_MAX_LENGTH - LOGIN_SUFFIX.length

  has_one :user_programmatic_access

  validate :validate_login

  after_create :preemptively_safelist

  # Public: Returns the ProgrammaticAccessGrant representing the bot's
  # current grant context.
  def grant
    ability_delegate
  end

  def grant=(grant)
    self.ability_delegate = grant
  end

  attribute :login, :string

  # Internal: the slug for this Bot, based on the un-suffixed part of the login
  #
  # Returns a String
  def slug
    LOGIN_REGEX.match(login) && $1
  end

  # Internal: sets the Bot's login, as slug with suffix
  # This is to namespace Bot logins (so they don't use up available logins for humans).
  #
  # Returns the slug String
  def slug=(value)
    self.login = value + LOGIN_SUFFIX
    value
  end

  # Public: load the granular actor for a given resource.
  #
  # Mirrors Bot#async_load_granular_actor_for, which considers installations on
  # the owner of a resource. This method doesn't make that distinction because
  # PATv2 actors can't have multiple grants, yet.
  def async_load_granular_actor_for(resource)
    Promise.resolve(ability_delegate.present?)
  end

end
