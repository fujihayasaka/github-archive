# typed: true
# frozen_string_literal: true

module GitHub
  module Qintel
    autoload :Catalog, "github/qintel/catalog"
    autoload :Client, "github/qintel/client"
    autoload :CredentialFile, "github/qintel/credential_file"
    autoload :S3, "github/qintel/s3"

    Error              = Class.new(StandardError)
    ConnectError       = Class.new(Error) # Connection failed
    TimeoutError       = Class.new(Error) # Request timeout
    RequestFailed      = Class.new(Error) # Other failure with no response
    BadResponseError   = Class.new(Error) # 1XX, 3XX response
    ClientError        = Class.new(Error) # 4XX response
    ServerError        = Class.new(Error) # 5XX response
    BadDataError       = Class.new(Error) # Malformed response

    # API client.
    #
    # Returns a Qintel::Client instance.
    def self.client
      @client ||= Client.new(
        secret: GitHub.qintel_api_secret,
        key: GitHub.qintel_api_key,
        proxy: GitHub.qintel_api_proxy,
      )
    end
  end
end
