# typed: true
# frozen_string_literal: true

module User::SignInAnalysisDependency
  extend T::Helpers
  requires_ancestor { User }

  def has_authenticated_events_from_ip?(ip)
    ActiveRecord::Base.connected_to(role: :reading) do
      authentication_records.authenticated_events.exists?(ip_address: ip)
    end
  end

  def verified_device_events_from_ip?(ip)
    ActiveRecord::Base.connected_to(role: :reading) do
      authenticated_devices.
        verified.
        joins(:authentication_records).
        where(authentication_records: { ip_address: ip, user: self }). # add the user: self to ensure we hit the index
        exists?
    end
  end

  def known_octolytics_id?(octolytics_id)
    ActiveRecord::Base.connected_to(role: :reading) do
      authentication_records.authenticated_events.where(octolytics_id: octolytics_id).exists?
    end
  end

  # A collection of reasons/heuristics that allow a user to bypass a device
  # verification challenge. We stat the result as a side effect for
  # to see when a particular method is no longer necessary.
  #
  # returns a symbol describing the verification method or `nil` if the device
  #  cannot be associated with previous activity
  def sign_in_verification_method(authenticated_device, ip_address, octolytics_id)
    if authenticated_device.verified?
      :verified_device
    elsif two_factor_authentication_enabled?
      :two_factor_user
    elsif verified_device_events_from_ip?(ip_address)
      :verified_ip
    else
      nil # the user will need to solve a challenge before sign in is allowed
    end
  end

  # Returns a sampling of account_related_emails where the primary email is the
  # first in the list.
  def masked_primary_and_account_related_emails(related_email_count = 4)
    other_account_related_emails = account_related_emails.map(&:to_s) - [email.to_s]
    ([email] + other_account_related_emails.sample(related_email_count)).map { |email| mask_email(email) }
  end

  # Prints out the first letter of the name part and fills the remaining slots
  # with asterisks. Returns the whole domain part.
  def mask_email(email)
    user, domain = email.split("@")
    [user[0] + ("*" * (user.length - 1)), domain].join("@")
  end
end
