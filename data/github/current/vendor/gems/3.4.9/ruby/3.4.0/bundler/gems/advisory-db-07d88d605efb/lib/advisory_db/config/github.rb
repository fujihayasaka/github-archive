# frozen_string_literal: true

module AdvisoryDB
  module Config
    module GitHub
      # This is how long our JWT will be valid and how long before our access
      # token expires when we try to renew it.
      AUTH_WINDOW = 60 # seconds

      def github_advisories_repo
        dev_safe_env_access("GITHUB_ADVISORIES_REPO", "github/advisory-database")
      end

      def github_app_email
        ENV.fetch("GITHUB_APP_EMAIL")
      end

      def github_app_id
        dev_safe_env_access("GITHUB_APP_ID", "12345")
      end

      def github_app_name
        ENV.fetch("GITHUB_APP_NAME")
      end

      def github_app_private_key
        # This is a non production private key returned if we are in dev.
        dev_safe_env_access("GITHUB_APP_PRIVATE_KEY", "-----BEGIN RSA PRIVATE KEY-----
MIIEoQIBAAKCAQBmHBTQmEjuD5DoGvOY55yBlW14t9GKPrFIB7HycQ70Gqo7aBPF
CPiai3eGOsRCxnJRV4QLnRzEqVkWYQCumpQzvv9Hps4HbfTKeU/UY2RtG9CdlbWJ
WkF65I9aiZHVwZnUqKPSgpssJ15TmHl2LnsHFo0eYpwKfsFt/1f8Zix4WqkUN1x/
2vPsODjaoA9rFTVU4Y80ICKY8mTy6Gq8gzhN5Wix/2gFjuCS8Go5HjDPykGFELEE
55fyH54r6Uju9WmWlJFAhTRcmjPPDv/Y3q8c0v54kTnymK/1Cdeer1SozxT1tZFD
TOzyLr8HOh6gjot37ML7xlpW/5Dsf93F8RspAgMBAAECggEAOF5aM0lOQXWAZlGy
ln+Ny4+FLnYzi+DOF1iAKLm3KpSp0z/CYixwqUhCxGweuko5A6SPdaXXIs3mK0+D
g+A73lEbNh/kbv+Jelj78+CmqQEI6mWiIOAdc81HQhDd3CYTWO17+pM1PGvDS9zJ
eK9yJViSsOp4/+Y3vBSRKvnwpMOaUT2CWdqRfmspjXqDkpCjnGHF7dz301m2cAEp
R2pXAi50rum5X/8kOPuhU1DAfPjTn0CsCtOEtGZPt4reM7+UOQsflNPa3S4hYTxZ
R0NilXCjbFOfHORYiGWjaKTSwAoWLUzmld/kKeMTu3Sngxi/hYcGKs5KNCadXiug
+WDu8QKBgQDBvWqvQ+FMbzy42OOS7m8Q1+rWh4n2UcM+bUD0Dk/Tlltml3X5madL
hfp9NM7R/fwp0o528rsNsmdEl8YOfp76PgxT+k7mrrFljVFbWgxTuA7+s03AYrwf
vi9BwVZX3xi5eZ/GdyFO9Ky1dBbc+fs5dfaDexhVr/thWieBaLSthQKBgQCG7G92
GJiczbw/nk4LeglWtoJykYWcRDrOWAgKenbaMeSLsUW/f9y2SQ67W71aWXoGvikh
ue0WIF3XRPfOG+xhkljeYRyZSQ5laQHNJGwKSJLUVrkduhg0DVhh9CFla7BFQaic
hcaSl68Dwvt/Pcd1XwcZFrF6bZiy5TRNBDbmVQKBgBnjKn8yzcb90hpM+NOoQnT4
tOtnfvrH4BPWW2iBBQ+btqjVsjDg5CbGRzs1tDEBBBG+jcS9GFtzLDNRKGjFaI69
fb424xYV36RXJrjTJnSFUpOb99auGr8PFZdusw/Ywp/97WiCgJPhQ7aXRXrPeE8s
QP0+lHjWo/tVJZQ4HnRVAoGATLCpbkPuwvoB7VtK2yUjl8Enhn2Gp1r03gKVl3ci
hUVkta4uifngd1AxandruqYvQRPnhz8KLtB45npSLDoc8xzfHI+wVMR8xVGZb4Qr
UPENXFpq4CW9yiBnw02jieVbDRKUB1vWkc5b8VRr5Vg1PlakTzNh78fJyq2TO8+Q
cP0CgYAnsRoOzX0tKyO+LilJeFQ9kOBlytYiOuVZp9bXac3O5MMFUe2/EzoRTr61
HvJ3NTut0hRWyNp0DJos5Pv+DA76C048naz9rcehJV2CRD96yuumOJ/hiDbm7Sj7
eufREK8SwrqUXWbN+gAdaDt58zlH5KbqpiIGoXSpYuwWR7N9mA==
-----END RSA PRIVATE KEY-----")
      end

      def github_app_installation_id
        dev_safe_env_access("GITHUB_APP_INSTALLATION_ID", "456789")
      end

      def github_cvelist_repo
        ENV.fetch("GITHUB_CVELIST_REPO")
      end

      def github_webhook_secret
        ENV.fetch("GITHUB_WEBHOOK_SECRET")
      end

      def github_throttle_open?
        !!ENV["GITHUB_THROTTLE_OPEN"]
      end

      def nvd_api_key
        ENV.fetch("NVD_API_KEY", nil)
      end

      def advisory_inbox_hmac_secret
        ENV.fetch("HMAC_SECRET_ADVISORY_INBOX_GITHUBAPP_COM", nil)
      end

      def verify_advisory_inbox_hmac_secret?
        Rails.env.production?
      end

      # This returns a GitHub client, specifically an Octokit::Client. This
      # client can be used to make all sorts of GitHub API requests.
      def github
        # Clear the memoized client if the access token will expire soon.
        Thread.current[:github] = nil if Thread.current[:github_expires_at]&.past?

        # Return the memoized client if it's still available.
        return Thread.current[:github] if Thread.current[:github]

        # Go get an access token for the only installation of our GitHub App.
        access_token, client_expires_at = generate_access_token

        client = Octokit::Client.new(
          access_token: access_token,
        )

        Thread.current[:github_expires_at] = client_expires_at
        Thread.current[:github] = client
      end

      private

      # We have a pattern of some settings which aren't *really* necessary for local development
      # being left to be filled in because they need to be filled for end to end interaction with dotcom.
      # This method provides a single warning to logs the first time we use the wrong value and returns the submitted default value.
      def dev_safe_env_access(env_var_name, default_value)
        if Rails.env.development? && !ENV.key?(env_var_name)
          already_warned = instance_variable_get(:"@already_warned_#{env_var_name}")
          unless already_warned
            # Warn just once whenever an env var is accessed that we are using defaulting behavior for. Mostly so devs can figure out why a default is used.
            instance_variable_set(:"@already_warned_#{env_var_name}", true)
            ::GitHub::Telemetry::Logs.logger.warn("#{env_var_name} was looked up in a development environment. A dev-time value is being used, if you are running with dotcom sideloaded you may need to update this value to be something functional.")
          end

          return default_value
        end

        ENV.fetch(env_var_name)
      end

      # This creates a new access token for the GitHub App installation
      # specified by github_app_installation_id. First, we authenticate as the
      # GitHub App itself with a JWT (JSON Web Token). Next, we use that
      # application-authenticated client to create a new access token for the
      # app's specific installation. This access token expires in 1 hour, but
      # we set the expiration to be one minute earlier to account for latency
      # and clock differences.
      def generate_access_token
        access_token_creation = Octokit::Client.new(
          bearer_token: generate_bearer_token,
        ).create_app_installation_access_token(github_app_installation_id)

        [
          access_token_creation.token,
          access_token_creation.expires_at - AUTH_WINDOW,
        ]
      end

      # This produces a JWT (JSON Web Token) using the GitHub App's ID and
      # private key. The JWT is only valid for one minute before it can no
      # longer be used to generate an access token. This is fine for our
      # purposes because the application-authenticated client is only used for
      # one request and then discarded, superceded by a client authenticated as
      # the app's specific installation.
      def generate_bearer_token
        now = Time.now.to_i
        payload = { iat: now, exp: now + AUTH_WINDOW, iss: github_app_id }
        private_key = OpenSSL::PKey::RSA.new(github_app_private_key)
        JWT.encode(payload, private_key, "RS256")
      end
    end

    include GitHub
  end
end
