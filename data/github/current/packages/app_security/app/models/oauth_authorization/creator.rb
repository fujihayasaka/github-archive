# typed: true
# frozen_string_literal: true

class OauthAuthorization
  class Creator
    class Error < StandardError; end

    def self.perform(user:, **options)
      new(user, options).perform
    end

    class Result
      def self.success(authorization) new(:success, authorization: authorization) end
      def self.failed(error) new(:failed, error: error) end

      attr_reader :error, :authorization

      def initialize(status, authorization: nil, error: nil)
        @status        = status
        @authorization = authorization
        @error         = error
      end

      def success?
        @status == :success
      end

      def failed?
        @status == :failed
      end
    end

    attr_reader :entry_point

    def initialize(user, options = {})
      @user = user

      @scopes                         = options[:scopes]
      @application                    = options[:application]
      @description                    = options[:description]
      @is_personal_access_token       = options[:is_personal_access_token]
      @entry_point                    = options[:entry_point]
      @integration_version_context    = options[:integration_version_context]
      @reconcile_integration_version  = options[:reconcile_integration_version] || false
    end

    def perform
      # Every personal access token gets its own authorization
      authorization = if @is_personal_access_token
        @user.oauth_authorizations.new(
          application_id:    OauthApplication::PERSONAL_TOKENS_APPLICATION_ID,
          application_type: "OauthApplication",
          description:      @description,
        )
      else
        @user.oauth_authorizations.where(
          application_id: @application.id,
          application_type: "#{@application.class}",
        ).first_or_initialize
      end

      authorization.add_scopes(@scopes)

      authorization.transaction do
        authorization.save!

        record_marketplace_installations
      end

      if authorization.persisted?
        Result.success(authorization)
      else
        Result.failed(authorization.errors.full_sentence)
      end
    end

    private

    def record_marketplace_installations
      return if @is_personal_access_token || GitHub.enterprise?

      MarketplaceOauthAppInstallJob.perform_later(user: @user, application: @application)
    end
  end
end
