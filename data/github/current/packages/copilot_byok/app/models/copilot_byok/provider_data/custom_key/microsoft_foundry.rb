# typed: true
# frozen_string_literal: true

module CopilotByok
  module ProviderData
    module CustomKey
      class MicrosoftFoundry < T::Struct
        prop :deployment_url, String

        sig { params(deployment_url: String).void }
        def initialize(deployment_url:)
          self.class.validate_deployment_url!(deployment_url)
          super
        end

        sig { params(data_hash: T::Hash[String, T.untyped]).returns(MicrosoftFoundry) }
        def self.build!(data_hash)
          deployment_url = data_hash["deployment_url"]
          raise Error.new("deployment_url is required") if deployment_url.nil?

          new(deployment_url: deployment_url)
        end

        sig { params(url: String).void }
        def self.validate_deployment_url!(url)
          uri = URI.parse(url) rescue nil
          if uri.nil?
            raise Error.new("deployment_url is not a valid URL")
          end

          hostname = uri.hostname&.downcase
          valid_hostnames = CopilotByok::CustomKey::VALID_MSFOUNDRY_HOSTNAMES

          unless valid_hostnames.any? { |h| hostname == h || hostname&.end_with?(".#{h}") }
            raise Error.new("deployment_url must be a valid Microsoft Foundry endpoint")
          end
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def to_twirp_details
          { "deployment_url" => deployment_url }
        end
      end
    end
  end
end
