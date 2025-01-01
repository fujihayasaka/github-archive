# typed: true
# frozen_string_literal: true

module User::EmailUnlinkDependency
  include Instrumentation::Model
  # Public: Instrument the initiation of an email unlink request.
  #
  # actor - The user initiating email unlink, either staff or the email owning user
  # reason - scenario which initiated email unlink - currently either staff intiated or through the account recovery flow
  # email - the specific email that the request is being triggered for if it's not a bulk unlink request
  #
  # Returns nothing.
  def instrument_email_unlink_initiate(actor: nil, reason: nil, email: nil)
    payload = {
      user: self,
      actor: actor || self,
      bulk_request: email.nil?,
    }

    payload[:reason] = reason if reason
    payload[:email] = email if email

    # instrument :initiate_email_unlink, payload
    GitHub.instrument "user.initiate_email_unlink", payload

    tags = ["bulk_request:#{email.nil?}"]
    tags << "reason:#{reason}" if reason
    GitHub.dogstats.increment("email_unlink", tags: tags)
  end
end
