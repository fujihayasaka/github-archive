# frozen_string_literal: true

class SetForwardedHeaders
  def initialize(app)
    @app = app
  end

  # The Okta Network Gateway sets the ONG-External-URL header to the
  # customer-facing host, including scheme and port. We want Rails to always
  # use this customer-facing information when building URLs and redirects,
  # rather than ever falling back to ONG's internal host.
  #
  # Borrowed from: https://github.com/github/bones/pull/607
  def call(env)
    ong_external_url = env["HTTP_X_ONG_EXTERNAL_URL"]

    if ong_external_url
      ong_external_uri = URI(ong_external_url)

      env["HTTP_X_FORWARDED_HOST"] = ong_external_uri.host
      env["HTTP_X_FORWARDED_PORT"] = ong_external_uri.port&.to_s
      env["HTTP_X_FORWARDED_PROTO"] = ong_external_uri.scheme
      env["HTTP_X_FORWARDED_SSL"] = "on"
    end

    @app.call(env)
  end
end
