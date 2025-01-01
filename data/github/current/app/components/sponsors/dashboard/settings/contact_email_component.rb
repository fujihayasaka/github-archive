# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::ContactEmailComponent < ApplicationComponent
  def initialize(sponsorable:)
    @sponsorable = sponsorable
  end

  private

  memoize def possible_emails
    @sponsorable.emails.user_entered_emails.pluck(:email, :id)
  end

  def contact_email
    return unless @sponsorable.user?

    @contact_email ||= @sponsorable.sponsors_contact_email
  end

  def billing_email
    return unless @sponsorable.organization?

    @billing_email ||= @sponsorable.billing_email
  end
end
