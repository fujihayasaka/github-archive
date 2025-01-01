# typed: true
# frozen_string_literal: true

require "enterprise/crypto"
require "rubygems/package"
require "rbnacl"

module GitHub
  module Connect
    class Authenticator
      class AuthenticationError < StandardError
      end

      class ConnectionError < StandardError
      end

      class LicenseLoadingError < StandardError
      end

      LICENSE_KEY_PATH = "#{GitHub::AppEnvironment.root}/enterprise/license/gpg/pubring.gpg".freeze
      ENTERPRISE_LICENSE_KEY_PATH = "/data/enterprise/license.gpg".freeze
      CUSTOMER_KEY_PATH = "#{GitHub::AppEnvironment.root}/enterprise/customer/gpg/pubring.gpg".freeze
      ENTERPRISE_CUSTOMER_KEY_PATH = "/data/enterprise/customer.gpg".freeze
      OAUTH_SCOPES = %w[repo user]
      attr_accessor :license_file_path, :public_key, :private_key

      def self.license_key_data
        File.exist?(ENTERPRISE_LICENSE_KEY_PATH) ? File.read(ENTERPRISE_LICENSE_KEY_PATH) : File.read(LICENSE_KEY_PATH)
      end

      def self.license_vault
        @license_vault ||= begin
          vault = ::Enterprise::Crypto::LicenseVault.new(license_key_data)
          vault.load_vault
          vault
        end
      end

      def self.customer_key_data
        File.exist?(ENTERPRISE_CUSTOMER_KEY_PATH) ? File.read(ENTERPRISE_CUSTOMER_KEY_PATH) : File.read(CUSTOMER_KEY_PATH)
      end

      def self.customer_vault
        @customer_vault ||= begin
          vault = ::Enterprise::Crypto::CustomerVault.new(customer_key_data)
          vault.load_vault
          vault
        end
      end

      def self.load_vaults
        license_vault && customer_vault
      end

      def generate_keys
        self.private_key = OpenSSL::PKey::RSA.new(IntegrationKey::KEY_LENGTH)
        self.public_key = self.private_key.public_key.to_pem
        self.private_key.to_pem
      end

      #
      # This runs from the UpdateConnectInstallationInfo job that runs weekly
      #
      def updated_installation_info
        return nil unless GitHub.enterprise?

        connection = DotcomConnection.new
        {
          server_id: connection.server_id,
          license: Base64.encode64(File.read(self.license_file_path)),
          host_name: GitHub.host_name,
          http_only: !GitHub.ssl?,
          version: GitHub.version_number,
          public_key: self.public_key && Base64.encode64(self.public_key),
          features: connection.current_features,
          total_assigned_users: GitHub::Enterprise.license.seats_used,
          total_dormant_users: User.dormant_users.count,
          dormancy_threshold: GitHub.dormancy_threshold.inspect,
        }
      end

      #
      # We want to keep this method fast, as it's used for the initial
      # Connect handshake, so not backgrounded.
      #
      def authentication_request_info
        return nil unless GitHub.enterprise?
        connection = DotcomConnection.new
        generate_keys unless self.public_key.present?
        {
          server_id: connection.server_id,
          license: Base64.encode64(File.read(self.license_file_path)),
          host_name: GitHub.host_name,
          http_only: !GitHub.ssl?,
          version: GitHub.version_number,
          public_key: self.public_key && Base64.encode64(self.public_key),
          features: connection.current_features,
        }
      end

      def authentication_request_data
        return nil unless GitHub.enterprise?
        authentication_request_info.to_json
      end

      def request_authentication_token
        return nil unless GitHub.enterprise?

        response = enterprise_installation_api("/enterprise-installation", authentication_request_data)

        begin
          pbody = json_parse(response.body)
        rescue ConnectionError => e # wrap it with a descriptive exception
          raise AuthenticationError, "error parsing response body"
        end

        unless response.success?
          raise AuthenticationError, "unable to request an authentication token: #{response.status} #{pbody["message"]}"
        end

        pbody["token"]
      end

      def update_installation_info(token)
        return nil unless GitHub.enterprise?
        payload = updated_installation_info.to_json
        response = GitHub::Connect.github_app_authenticated do
          enterprise_installation_api("/enterprise-installation", payload, GitHub::Connect.auth_headers, :put)
        end
        json_parse(response.body)["token"]
      end

      # Public: POST metrics to the /enterprise-installation/usage-metrics dotcom endpoint.
      #
      # Metrics are buffered to the database (via GitHub::KV) first, then sent and
      # removed if dotcom returns a 204 accepting the metrics (i.e. metrics are succesfully sent).
      # If sending the metrics fails (transient network issue for example), the payload is kept locally
      # for retransmission next time UploadConnectMetricsJob runs.
      #
      # Returns a Hash with the metrics sent and the metrics that were not delivered.
      #
      # This method does nothing used outside GHES.
      def upload_connect_metrics
        return nil unless GitHub.enterprise?

        sent = []
        tstart = Time.now
        usage_metrics = GitHub::Connect::UsageMetrics.new
        metrics = usage_metrics.fetch
        usage_metrics.store(metrics)
        tend = Time.now
        Rails.logger.info "connect-usage-metrics: fetch took #{tend - tstart} seconds"

        metrics.delete_if do |m|
          response = GitHub::Connect.github_app_authenticated do
            enterprise_installation_api("/enterprise-installation/usage-metrics",
                                        m.to_json,
                                        GitHub::Connect.auth_headers, :post)
          end
          sent << m if response.status == 204
          response.status == 204
        end

        {
          sent: sent,
          failures: metrics,
        }
      ensure
        Rails.logger.error "connect-usage-metrics: error sending metrics" if metrics.size > 0
        T.must(usage_metrics).store(metrics)
      end

      def remove_enterprise_installation
        return nil unless GitHub.enterprise?
        response = GitHub::Connect.github_app_authenticated do
          enterprise_installation_api("/enterprise-installation", nil, GitHub::Connect.auth_headers, :delete)
        end
        GitHub::Connect.report_failure(ApiError.new("Error removing enterprise installation: '#{response.status} #{response.body}'"), "github-connect-connection") unless response.success?
        response.success?
      end

      def request_permissions(features)
        return nil unless GitHub.enterprise?
        response = GitHub::Connect.github_app_authenticated do
          enterprise_installation_api("/enterprise-installation/permissions", { features: features }.to_json, GitHub::Connect.auth_headers, :post)
        end
        GitHub::Connect.report_failure(ApiError.new("Error requesting permissions: '#{response.status} #{response.body}'"), "github-connect-connection") unless response.success?
        json_parse(response.body).merge("success" => response.success?)
      end

      def remove_all_contributions
        return nil unless GitHub.enterprise?
        response = GitHub::Connect.github_app_authenticated do
          enterprise_installation_api("/enterprise-installation/contributions", nil, GitHub::Connect.auth_headers, :delete)
        end
        GitHub::Connect.report_failure(ApiError.new("Error removing all contributions: '#{response.status} #{response.body}'"), "github-connect-connection") unless response.success?
        response.success?
      end

      def request_oauth_application
        return nil unless GitHub.enterprise?
        response = GitHub::Connect.github_app_authenticated do
          enterprise_installation_api("/enterprise-installation/application", nil, GitHub::Connect.auth_headers, :get)
        end

        body = json_parse(response.body)
        if response.status == 403 || response.status == 404 || (body["client_id"] && body["owner_type"].nil?)
          msg = "#{response.status} #{body["message"]}"
          raise GitHub::Connect.report_failure(AuthenticationError.new("unable to obtain oauth app token: #{msg}"), "github-connect-connection")
        end
        body
      end

      def request_oauth_token(code, oauth, client_secret)
        return nil unless GitHub.enterprise?
        if client_secret
          oauth["client_secret"] = client_secret
        end
        body = oauth.merge(code: code, accept: :json).to_json
        response = dotcom_request("/login/oauth/access_token", body)

        Rack::Utils.parse_nested_query(response.body)["access_token"]
      rescue Rack::QueryParser::InvalidParameterError
        GitHub::Connect.report_failure(ApiError.new("Parser Error: '#{response.body}'"), "github-connect-connection", "parser")
        # An invalid JSON from dotcom shoud be treated as a connection error
        # (it is often a proxy server error message or something to that effect)
        raise ConnectionError
      end

      def revoke_oauth_token(token, oauth, client_secret)
        if client_secret
          oauth["client_secret"] = client_secret
        end
        return nil unless GitHub.enterprise?
        response = enterprise_installation_api("/applications/#{oauth["client_id"]}/token", { access_token: token }.to_json, {}, :delete, [oauth["client_id"], oauth["client_secret"]])
        GitHub::Connect.report_failure(ApiError.new("Error revoking oauth token: '#{response.status} #{response.body}'"), "github-connect-connection") if response.status != 204
        response.status == 204
      end

      def request_oauth_user_info(token)
        response = enterprise_installation_api("/user", nil, { "Authorization" => "token #{token}" }, :get)
        data = json_parse(response.body)
      end

      def upload_license_usage(business_id, data)
        return nil unless GitHub.enterprise?
        response = GitHub::Connect.github_app_authenticated do
          enterprise_installation_api("/businesses/#{business_id}/user-accounts-uploads?name=users.json", data, GitHub::Connect.auth_headers, :post, nil, GitHub.dotcom_upload_host_name)
        end
        GitHub::Connect.report_failure(ApiError.new("Error uploading license usage: '#{response.status} #{response.body}'"), "github-connect-connection") unless [200, 201].include?(response.status)
        json_parse(response.body)
      end

      def complete_license_info_upload(business_id, upload_id)
        return nil unless GitHub.enterprise?
        response = GitHub::Connect.github_app_authenticated do
          enterprise_installation_api("/businesses/#{business_id}/user-accounts-uploads/#{upload_id}/sync", nil, GitHub::Connect.auth_headers, :patch)
        end
        GitHub::Connect.report_failure(ApiError.new("Error completing license info upload: '#{response.status} #{response.body}'"), "github-connect-connection") if response.status != 202
        json_parse(response.body)
      end

      def license_usage_upload_info(business_id, upload_id)
        return nil unless GitHub.enterprise?
        response = GitHub::Connect.github_app_authenticated do
          enterprise_installation_api("/businesses/#{business_id}/user-accounts-uploads/#{upload_id}", nil, GitHub::Connect.auth_headers, :get)
        end
        GitHub::Connect.report_failure(ApiError.new("Error uploading license info: '#{response.status} #{response.body}'"), "github-connect-connection") unless [200, 201].include?(response.status)
        json_parse(response.body)
      end

      def load_license(data)
        @license ||= begin
          license_vault = self.class.license_vault
          customer_vault = self.class.customer_vault

          ctx = GPGME::Ctx.new(license_vault.default_context_options)
          verified = ctx.verify(GPGME::Data.new(data))
          signatures = ctx.verify_result.signatures

          if signatures.all? { |sig| sig.valid? }
            license = T.let(::Enterprise::Crypto::License.new(:customer, :metadata, :files), T.untyped)
            public_data = T.let(nil, T.untyped)
            secret_data = T.let(nil, T.untyped)

            Gem::Package::TarReader.new StringIO.new(verified.to_s) do |tar|
              tar.each do |file|
                case file.full_name
                when "metadata.json"
                  T.unsafe(license).metadata = JSON.parse(file.read)
                when "gpg/pubring.gpg"
                  public_data = file.read
                when "gpg/secring.gpg"
                  secret_data = file.read
                end
              end
            end

            unless secret_data && public_data && license.metadata
              missing = []
              missing << "metadata.json" unless license.metadata
              missing << "gpg/pubring.gpg" unless public_data
              missing << "gpg/secring.gpg" unless secret_data
              error = LicenseLoadingError.new "License data is missing #{missing.join(", ")}"
              Failbot.report error
              return nil
            end

            fingerprint = customer_vault.import_key(secret_data)
            public_key = ctx.get_key(customer_vault.import_key(public_data), false)
            customer_public_key = ctx.get_key(customer_vault.fingerprint, false)

            ::Enterprise::Crypto::Vault.verify_key_fingerprint!(public_key, fingerprint)
            ::Enterprise::Crypto::Vault.verify_key_signature!(public_key, customer_public_key)

            key = ctx.get_key(fingerprint, true)
            license.customer = ::Enterprise::Crypto::Customer.new(key.name, key.email, key.comment, secret_data, public_data)
            license
          end
        rescue ::Enterprise::Crypto::Error, GPGME::Error::NoData, GPGME::Error::DecryptFailed => error
          Failbot.report error
          nil
        rescue GPGME::Error => error
          Failbot.report error
          gpg_debug_dump(error)
          nil
        ensure
          ctx.release if ctx
        end
      end

      def valid_license?(data)
        license = load_license(data)
        license && (license.perpetual? || license.expire_at > DateTime.now)
      end

      def gpg_debug_dump(exception)
        return if !Rails.env.test?
        debug_commands = ["pstree", "ps aux", "lsof -p #{$$}"]
        data = debug_commands.map do |c|
          output = `#{c} 2>&1`
          [
            "---------------------------------",
            "#{c} (#{output.lines.count})",
            output,
            "---------------------------------"
          ].join("\n")
        end
        data.unshift(Thread.list.map { |t| t.inspect }.join("\n"))
        data.unshift("---------------------------------")
        data.unshift(Thread.current.inspect)
        data.unshift("---------------------------------")
        data.unshift(Process.last_status)
        data.unshift([:NOFILE, :NPROC].map { |p| [p, Process.getrlimit(p)].inspect }.join("\n"))
        data.unshift("---------------------------------")
        data.unshift(exception.backtrace.join("\n"))
        data.unshift(GPGME::Engine.info.inspect)
        data.unshift([exception.code, exception.source, exception.message].inspect)
        data.unshift(exception.inspect)
        logfile = "/tmp/#{ENV["JOB_NAME"]}-artifacts/gpg-#{ENV["TEST_QUEUE_WORKER_ID"] || 0}.log"
        File.open(logfile, "w") { |f| f.puts(data.join("\n")) } if File.exist?(logfile)
      end

      def encrypt_message(message, key = GitHub.enterprise_user_license_list_public_key)
        box = RbNaCl::Boxes::Sealed.from_public_key(Base64.decode64(key))
        Base64.encode64 box.box(message)
      end

      def decrypt_message(message, keys = GitHub.enterprise_user_license_list_private_keys)
        keys.each_with_index do |key, i|
          begin
            box = RbNaCl::Boxes::Sealed.from_private_key(Base64.decode64(key))
            decrypted_message = box.open Base64.decode64(message)

            GitHub.dogstats.increment("licensing.connect.decrypt_message", tags: ["key:primary"]) if i == 0
            GitHub.dogstats.increment("licensing.connect.decrypt_message", tags: ["key:outdated-#{i}"]) if i != 0
            return decrypted_message
          rescue RbNaCl::CryptoError => error
            next if i < keys.size - 1
            # None of our keys worked, so we'll report the error
            Failbot.report(error)
          end
        end
      end

      def dotcom_request(path, body, headers = {}, method = :post)
        hostname = GitHub.dotcom_host_name
        if hostname.ends_with?(".review-lab.github.com")
          # Review labs don't accept non-API dotcom requests without the
          # staffonly cookie, so we'll route these through dotcom
          hostname = "github.com"
          Rails.logger.warn "#{method} #{path} called via #{hostname} instead of #{GitHub.dotcom_host_name}"
        end
        conn = GitHub::Connect.faraday_connection(hostname)
        conn.send(method) do |req|
          GitHub::Connect.github_connect_request(req, path, headers, body, api: false)
        end
      end

      def enterprise_installation_api(path, body, headers = {}, method = :post, basic_auth = nil, host = nil)
        conn = host ? GitHub::Connect.faraday_connection(host) : GitHub::Connect.faraday_connection
        conn.basic_auth(basic_auth[0], basic_auth[1]) if basic_auth
        response = conn.send(method) do |req|
          GitHub::Connect.github_connect_request(req, path, headers, body, github_connect_accept_type: true)
        end
        if response.status == 403
          GitHub::Connect.report_failure(ApiError.new("Error: '#{response.status} #{response.body}'"), "github-connect-connection")
          raise AuthenticationError
        end
        response
      rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout => e
        GitHub::Connect.report_failure(TimeoutError.new(e.message), "github-connect-connection", "timeout")
        raise ConnectionError
      rescue Faraday::Error, Errno::EPIPE, Faraday::ConnectionFailed
        GitHub::Connect.report_failure(ServiceUnavailableError.new("API Inaccessible"), "github-connect-connection")
        raise ConnectionError
      end

      private

      def json_parse(json, options = nil)
        GitHub::JSON.parse(json, options)
      rescue Yajl::ParseError
        GitHub::Connect.report_failure(ApiError.new("Parser Error: '#{json}'"), "github-connect-connection", "parser")
        # An invalid JSON from dotcom shoud be treated as a connection error
        # (it is often a proxy server error message or something to that effect)
        raise ConnectionError
      end
    end
  end
end
