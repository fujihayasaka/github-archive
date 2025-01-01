# typed: true
# frozen_string_literal: true

module ApplicationController::AuthenticityTokenDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :real_csrf_token
    helper_method :authenticity_token_for
  end

  # We override this to access our custom CSRF token. Retrieve the CSRF token
  # value from the user session or, if the current request does not have an
  # authenticated session, from the session cookie. If there is no CSRF token
  # within the session cookie, create a new random token.
  #
  # Returns String CSRF token.
  def real_csrf_token(_session)
    encoded = if user_session
      user_session.csrf_token
    else
      request.session[:_csrf_token] ||= SecureRandom.base64(UserSession::CSRF_BYTES)
    end

    Base64.strict_decode64(encoded)
  end

  # We override this to disallow sending the CSRF token in a the X-CSRF-Token
  # header.
  def request_authenticity_tokens
    [form_authenticity_param, request.headers["HTTP_SCOPED_CSRF_TOKEN"]]
  end

  # We override this to check the SameSite session cookie in addition to the
  # `Origin` header.
  def valid_request_origin?
    super && same_site_cookie_request?
  end

  # Helper for generating per-form CSRF tokens.
  def authenticity_token_for(path, method: :post)
    form_authenticity_token(
      form_options: { method: method, action: path },
    )
  end

  # We override this to validate that all forms are generating per-form CSRF
  # tokens (i.e. `form_options` contains a `method` and `action`).
  def form_authenticity_token(form_options: {})
    verify_per_form_csrf_options(form_options)
    super
  end

  # We override this to collect stats on valid/invaid CSRF tokens.
  def valid_authenticity_token?(session, token)
    super.tap do |valid|
      GitHub.dogstats.increment("csrf", tags: ["valid:#{valid}"])
    end
  end

  #
  # The following methods let us track per-form csrf tokens. We're trying to
  # find requests that use the CSRF token intended for a different action.
  #

  # Special error class to track when a per-form CSRF token is being generated
  # and does not have the method/action context necessary to generate it
  # correctly.
  class InvalidPerFormAuthenticityTokenGeneration < StandardError; end

  # Private: Validate the form options used to generate CSRF tokens are per-
  # form CSRF compatible (i.e. `form_options` doesn't contain a `method` or
  # `action`). If invalid options are found, we raise an exception in
  # development and test environments. For all other environmentes we report
  # to Failbot.
  #
  # form_options - A Hash of form options that includes those used to generate
  # per-form CSRF tokens (method and action).
  #
  # Returns nothing.
  def verify_per_form_csrf_options(form_options)
    method = form_options[:method]
    action = form_options[:action]
    if method.blank? || action.blank?
      e = InvalidPerFormAuthenticityTokenGeneration.new(
        "CSRF token being generated without method or action context.",
      )
      e.set_backtrace(caller)

      if Rails.env.test? || Rails.env.development?
        raise e
      else
        Failbot.report!(e,
          csrf_token_method: method,
          csrf_token_action: action,
          controller_name: controller_name,
          action_name: action_name,
          rollup: Digest::SHA256.hexdigest(
            [e.class.name, controller_name, action_name].flatten.join("|"),
          ),
        )
      end
    end
    nil
  end
end
