# typed: true
# frozen_string_literal: true

module Botable
  extend T::Helpers

  requires_ancestor { Kernel }

  BotTypes = T.type_alias { T.any(Bot, ProgrammaticAccessBot) }

  def self.included(klass)
    klass.extend(ClassMethods)
  end

  # Internal: Participates in abilities on behalf of this model.
  attr_accessor :ability_delegate

  # Be sure to implement the following when implementing a Botable
  # actor.
  #
  # LOGIN_SUFFIX = "[YOUR_SUFFIX_HERE]"
  # LOGIN_REGEX = %r{
  #   \A                               # Beginning of String
  #   ([a-zA-Z0-9]+(?:-[a-zA-Z0-9]+)*) # [1] slug
  #   #{ Regexp.quote LOGIN_SUFFIX }   # string literal "[bot]"
  #   \z                               # End of String
  # }x                                 # x: ignore whitepace
  # MAX_SLUG_LENGTH = User::LOGIN_MAX_LENGTH - LOGIN_SUFFIX.length
  #
  # validate :validate_login
  # after_create :preemptively_safelist
  #
  # Internal: the slug for this Bot, based on the unsuffixed part of the login
  #
  # Returns a String
  def slug
    raise NotImplementedError, "#slug has not been implemented yet"
  end

  # Internal: sets the Bot's login, as slug with suffix
  # This is to namespace Bot logins (so they don't use up available logins for humans).
  #
  # Returns the slug String
  def slug=(value)
    raise NotImplementedError, "#slug= has not been implemented yet"
  end

  # Bots don't currently handle display_login in the same way as other Users
  # This override is to make clear that Bot#display_login will always return the Bot's login
  # This will showup as <slug>[bot] in the UI
  def display_login
    T.bind(self, BotTypes)
    login # rubocop:disable GitHub/DoNotAllowLogin
  end

  # See User#display_login_legacy for more details
  # This override is to make clear that Bot#display_login_legacy will always return the Bot's slug
  # This will showup without [bot] in the UI
  def display_login_legacy
    slug
  end

  def to_s
    slug
  end

  def name
    slug
  end

  def github_owned?
    false
  end

  # This overrides User#instrument_user_signup so that Bots don't
  # publish user.signup hydro events.
  #
  # Returns nothing.
  def instrument_user_signup
    # no=op
  end

  # This overrides User#instrument_deletion so that Bots don't
  # publish user deleted events
  #
  # Returns nothing.
  def instrument_deletion(payload = {})
    # no-op
  end

  # Don't instrument the async delete to the audit log.
  def instrument_async_delete?
    false
  end

  def password_validation_required?
    false
  end

  def email_address_required?
    false
  end

  def user?
    false
  end

  def organization?
    false
  end

  def bot?
    true
  end

  def mannequin?
    false
  end

  def restricts_oauth_applications?
    false
  end

  def billable?
    false
  end

  def can_authenticate_via_oauth?
    false
  end

  def can_authenticate_via_basic_auth?
    true
  end

  def can_authenticate_via_username_password_basic_auth?
    false
  end

  def can_have_granular_permissions?
    ability_delegate&.can_have_granular_permissions?
  end

  # Public: A Bot can never authenticate via password.
  #
  # Returns false.
  def authenticated_by_password?(password = nil)
    false
  end

  def assignable_to_issues?
    false
  end

  # Internal: can the bot be subscribed to notifications
  #
  # Returns false
  def newsies_enabled?
    false
  end

  def can_own_repositories?
    false
  end

  # Public: Does the bot receive an email when the bot's account is destroyed?
  #
  # Returns false.
  def receives_confirmation_when_destroyed?
    false
  end

  # Public: We do not add bots to the users search index.
  #
  # Returns false.
  def searchable?
    false
  end

  # Don't require email verification for bots.
  def require_email_verification?
    false
  end

  # Public: Return the list of repository IDs for the repositories that this bot
  # has been granted access to via the bot's current ability_delegate context.
  #
  # Arguments:
  #
  # min_action:    - See docs for User#associated_repository_ids.
  # including:     - See docs for User#associated_repository_ids.
  # include_oauth_restriction: - See docs for User#associated_repository_ids.
  # include_indirect_forks: - See docs for User#associated_repository_ids.
  # include_oopfs: - See docs for User#associated_repository_ids.
  # resource:      - An optional String to represent a child association, to
  #                  limit results to repositories where the bot has permissions
  #                  on that specific resource.
  # repository_ids: - An optional list of candidate repository ids. Only
  #                   repositories that are in this list and are accessible by
  #                   the integration will be returned.
  # organization:  - An optional Organization to limit results to.

  #
  # Examples:
  #
  #   associated_repository_ids(resource: "statuses")
  #   associated_repository_ids(resource: "issues")
  #
  # Returns an Array of Integer repository IDs.
  def associated_repository_ids(min_action: nil, including: nil, include_oauth_restriction: true, include_indirect_forks: true, include_oopfs: true, resource: nil, repository_ids: nil, organization: nil)
    return [] unless ability_delegate.present?

    ability_delegate.repository_ids(min_action: min_action, resource: resource, repository_ids: repository_ids, organization: organization)
  end

  # Internal: Don't apply the standard user login formatting validation to Bots.
  def validates_login_format?
    false
  end

  # Internal: Preemptively safelist bots on bot creation.
  #
  # See https://github.com/github/platform-integrations/issues/164 for more details.
  def preemptively_safelist
    T.bind(self, BotTypes)
    mark_as_hammy(actor: self) if GitHub.spamminess_check_enabled?
  end

  def validate_login
    T.bind(self, BotTypes)
    if will_save_change_to_login? && !slug
      errors.add(:login, "is not in the correct format")
    end
  end

  module ClassMethods
    # Determines the target for for conditional access for multiple Bot instances
    #
    # bots - an enumerable of Bot
    #
    # returns Hash[Bot] => target for conditional access
    def multiple_target_for_conditional_access(bots)
      ConditionalAccess::Filter.ensure_with_class(bots, self)
      bots.each_with_object({}) { |bot, hash| hash[bot] = :no_target_for_conditional_access }
    end
  end

  mixes_in_class_methods ClassMethods
end
