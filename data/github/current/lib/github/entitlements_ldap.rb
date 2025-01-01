# typed: true
# frozen_string_literal: true

# An LDAP client authenticated to talk with github/entitlements' LDAP entries.
# Heavily inspired by the github-chatops-extensions gem:
# https://github.com/github/github-chatops-extensions/blob/51ad7fea9ab6f59c6c35fc21654a6ca65dc61879/lib/github_chatops_extensions/service/ldap.rb
module GitHub
  class EntitlementsLdap
    class LDAPConnectionError < StandardError; end
    class LDAPWTFError < StandardError; end

    SSL_CA_FILE = "/etc/ssl/certs/ca-certificates.crt"

    attr_reader :client

    def initialize(uri:, username:, password:)
      @client = create_client(uri, username, password)
      verify_connection!
      self
    end

    private

    def create_client(uri, username, password)
      return nil unless [uri, username, password].all?(&:present?)

      ldap_uri = URI(uri)
      ldap_options = {
        host: ldap_uri.host,
        port: ldap_uri.port,
        auth: {
          method: :simple,
          username: username,
          password: password,
        },
        encryption: {
          method: :simple_tls,
          tls_options: {
            ca_file: SSL_CA_FILE,
            verify_mode: OpenSSL::SSL::VERIFY_PEER,
          }
        }
      }
      Net::LDAP.new(ldap_options)
    end

    def verify_connection!
      if client.nil?
        raise LDAPWTFError, "FATAL: can't create LDAP connection object"
      end

      client.bind
      operation_result = client.get_operation_result
      if operation_result["code"] != 0
        raise LDAPConnectionError, "FATAL: can't bind to LDAP: #{operation_result["message"]}"
      end

      self
    end
  end
end
