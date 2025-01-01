# typed: true
# frozen_string_literal: true

class Api::Internal::EmailBounce < Api::Internal

  def login_from_api_auth; end

  @@ignore_reasons = Regexp.new([
    # qq hard-bouncing rate limited mail
    "Connection frequency limited",
    # gmail hard-bouncing rate limited mail
    "The user you are trying to contact is receiving mail at a rate",
    # spamhaus being a PITA again
    "spamhaus",
  ].join("|"), Regexp::IGNORECASE)

  def should_ignore?(status, reason)
    @@ignore_reasons =~ reason
  end

  use Rack::Auth::Basic, "Protected Area" do |_username, password|
    !ENV["INTERNAL_API_EMAIL_BOUNCE_PASSWORD"].blank? &&
    SecurityUtils.secure_compare(password, ENV["INTERNAL_API_EMAIL_BOUNCE_PASSWORD"])
  end

  # Internal API endpoint for handling email bounces, called by the sendgrid
  # log intaker and the smtp log processor.

  post "/internal/email_bounce", operation_id: :internal do
    @route_owner = Platform::NoOwnerBecause::UNAUDITED
    params = receive_json(request.body.read, type: Hash)
    %w[email source status reason].each do |param|
      deliver_error!(400, message: "Parameter #{param} is required") unless params.include?(param)
    end
    email = UserEmail.find_by(email: params["email"])
    if !email
      GitHub.dogstats.increment "email.bounce_notfound"
      deliver_error!(404, message: "No user with that email was found")
    end

    if self.should_ignore?(params["status"], params["reason"])
      GitHub::Logger::log({ "app" => "email", "action" => "bounce", "email" => email.email, "processed" => false })
      GitHub.dogstats.increment "email.bounce_ignored"
    else
      if email.bouncing?
        GitHub.dogstats.increment "email.bounce_already_bouncing"
      else
        if !email.verified?
          GitHub.dogstats.increment "email.bounce_unverified"
        else
          GitHub.dogstats.increment "email.bounce_verified"
        end
        email.mark_as_bouncing!(source: params["source"], status: params["status"], reason: params["reason"])
        GitHub::Logger::log({ "app" => "email", "action" => "bounce", "email" => email.email, "processed" => true })
        GitHub.dogstats.increment "email.bounce_processed"
      end
    end

    deliver_empty status: 202
  end
end
