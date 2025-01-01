# typed: true
# frozen_string_literal: true
class User
  # This class allows us to enable feature flags based on user email address suffix patterns.
  #
  # This can be useful when testing features called from user *_create callbacks,
  # where we don't have a chance to manually add individual actors to Flipper
  # before the feature is checked, and/or globally enabling the feature is not an option.
  #
  # This is a common use case for the New User Experience team, where we often need to test
  # features immediately upon account creation.
  #
  # Register this suffix-based actor on a feature in devtools by performing the following steps:
  #  1. Find your feature that you want to add future users to (:my_feature_name in this example)
  #  2. Choose Flipper ID as the actor type
  #  3. Enter User::EmailSuffixActor:mysuffix (do not include the SUFFIX_KEY here)
  #  4. Now, any users you create with an email address will be enrolled in the feature.
  #  5. Verify this by registering a new user with an email address of
  #       `strackoverflow+mysuffix.o2MeJz9dp@github.com`, and they will automatically receive any
  #       features that have that Flipper ID as an actor!
  #
  #  You can check if a feature is enabled for a user based on their login suffix
  #    by finding their Flipper actor, and then checking if it's enabled:
  #
  #  ```
  #    actor = User::EmailSuffixActor.from_user(current_user)
  #    GitHub.flipper[:my_feature_name].enabled?(actor)
  #  ```
  #
  #  !!! Use this sparingly and with caution. !!!
  #
  #  Careless use of email suffix actors could potentially lead to leaked features or unexpected
  #  experiences for users if they attempt to register with any of our allowed domains.
  #  Remove any suffix-based actors when you are finished testing a feature.

  class EmailSuffixActor
    # the suffix key is simply a random string of characters added to the end of a user's
    # email address (before the `@domain` part), which helps us obscure feature enrollment
    # and prevent accidental leaking of features/experiments to the public.
    SUFFIX_KEY = "o2MeJz9dp"

    # We will only enable features on users registered from these domains:
    ALLOWED_DOMAINS = %w(
      github.com
      microsoft.com
    ).freeze

    attr_reader :flipper_id

    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def self.from_user(user)
      self.from_email_address(user&.email)
    end

    def self.from_email_address(email_address)
      return nil if email_address.nil?
      # we don't need to follow the actual email regex as that has already been validated,
      # we just care about extracting our flipper actor ID
      domains = ALLOWED_DOMAINS.map { |d| Regexp.quote(d) }.join("|")
      suffix_pattern = /.*\+(?<actor_id>[a-zA-Z0-9]*)\.#{SUFFIX_KEY}@[#{domains}]/
      captures = email_address.match(suffix_pattern)&.named_captures

      new(captures["actor_id"]) if captures&.key?("actor_id")
    end

    def initialize(actor_id)
      @flipper_id = "#{self.class.name}:#{actor_id}"
    end

    def to_s
      flipper_id
    end
  end
end
