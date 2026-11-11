# typed: true
# frozen_string_literal: true

# https://sorbet.org/docs/error-reference#5037
# Sorbet must be able to statically resolve a method to create an alias to it.

class Codespaces::Environment
  def friendly_name; end
  def created; end
  def updated; end
  def last_used; end
  def create_from_prebuild; end
end

class Stafftools::Sponsors::Invoiced::SponsorshipFormInputs
  def is_recurring; end
  def is_public; end
  def email_opt_in; end
end
