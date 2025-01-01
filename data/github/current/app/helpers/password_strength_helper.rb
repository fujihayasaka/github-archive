# typed: true
# frozen_string_literal: true

module PasswordStrengthHelper
  extend T::Helpers
  requires_ancestor { ApplicationController } # rubocop:disable GitHub/PreventViewHelpersInControllers

  # Example sentence
  # Make sure it's at least 15 characters OR at least 8 characters including a number and a lowercase letter. Learn more.

  DOCUMENTATION_LINK = GitHub::HTMLSafeString.make %Q[<a class="Link--inTextBlock" href="#{GitHub.help_url}/articles/creating-a-strong-password" aria-label="Learn more about strong passwords">Learn more</a>.]
  LETTER_REQUIREMENT = "and a lowercase letter"
  MINIMUM_VALID_CHARACTERS = GitHub.password_minimum_length
  MAXIMUM_VALID_CHARACTERS = GitHub.password_maximum_length
  MORE_THAN_N_CHARACTERS = "at least #{User::PASSPHRASE_LENGTH} characters"
  NUMBER_REQUIREMENT = "including a number"

  def password_strength_sentence(include_documentation_link: true)
    message = ["Make sure it's"]

    message << tag.span(MORE_THAN_N_CHARACTERS, "data-more-than-n-chars": "")
    message << "OR"
    message << tag.span("at least #{PasswordStrengthHelper::MINIMUM_VALID_CHARACTERS} characters", "data-min-chars": "")
    message << tag.span(NUMBER_REQUIREMENT, "data-number-requirement": "")
    message << (tag.span(LETTER_REQUIREMENT, "data-letter-requirement": "") + ".")
    message << DOCUMENTATION_LINK if include_documentation_link

    safe_join(message, " ")
  end

  def weak_password_used_for_sign_in?
    !!session[::CompromisedPassword::WEAK_PASSWORD_KEY]
  end

  def weak_password_used_for_creation_or_change?
    !!flash[::CompromisedPassword::WEAK_PASSWORD_KEY]
  end
end
