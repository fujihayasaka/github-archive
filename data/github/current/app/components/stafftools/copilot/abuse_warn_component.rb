# typed: strict
# frozen_string_literal: true
class Stafftools::Copilot::AbuseWarnComponent < ApplicationComponent
  extend T::Helpers
  extend T::Sig

  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { params(copilot_user: Copilot::User).void }
  def initialize(copilot_user)
    @copilot_user = copilot_user
    @warned      = T.let(copilot_user.has_been_warned?, T::Boolean)
  end

  sig { returns(T::Boolean) }
  def warned?
    @warned
  end

  sig { returns(ActiveSupport::SafeBuffer) }
  def formatted_email
    ActiveSupport::SafeBuffer.new(Copilot.warn_email.gsub("\n\n", "<p>").gsub("\n", "<br>"))
  end
end
