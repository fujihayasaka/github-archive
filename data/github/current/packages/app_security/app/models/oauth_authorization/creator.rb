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

    attr_reader :integration_version_number, :entry_point

    def initialize(user, options = {})
      @user = user

      @scopes                     = options[:scopes]
      @application                = options[:application]
      @description                = options[:description]
      @is_personal_access_token   = options[:is_personal_access_token]
      @integration_version_number = options[:integration_version_number]
      @entry_point                = options[:entry_point]
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

        if authorization.integration_application_type?
          if authorization.outdated?
            update_integration_version_for(authorization)
          else
            set_integration_version_for(authorization)
          end
        end
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

    def set_integration_version_for(authorization)
      latest_version = latest_integration_version_for(authorization)

      add_user_permissions(authorization, permissions: latest_version.user_permissions)
      authorization.update!(integration_version_number: latest_version.number)
    end

    def update_integration_version_for(authorization)
      latest_version = latest_integration_version_for(authorization)

      diff = latest_version.diff(authorization.integration_version)

      add_user_permissions       authorization, permissions: diff.permissions_added      if diff.permissions_added?
      upgrade_user_permissions   authorization, permissions: diff.permissions_upgraded   if diff.permissions_upgraded?
      downgrade_user_permissions authorization, permissions: diff.permissions_downgraded if diff.permissions_downgraded?
      remove_user_permissions    authorization, permissions: diff.permissions_removed    if diff.permissions_removed?

      authorization.update!(integration_version_number: latest_version.number)
    end

    def latest_integration_version_for(authorization)
      # Prevent version downgrading:
      if authorization.integration_version && (integration_version_number.to_i < authorization.integration_version.number)
        authorization.application.latest_version
      else
        # Try to use the user-requested version number, or fallback to the
        # latest version for the App.
        authorization.application.versions.find_by(number: integration_version_number) || authorization.application.latest_version
      end
    end

    def add_user_permissions(authorization, permissions:)
      rows = []

      permissions.each_pair do |resource, action|
        next unless User::Resources.subject_types.include?(resource)
        subject = @user.resources.public_send(resource.to_s)

        rows << Permissions::Service.app_attributes(
          actor: authorization, subject: subject, action: action
        )
      end

      Permissions::Service.grant_permissions(rows, entry_point: entry_point)
    end

    def upgrade_user_permissions(authorization, permissions:)
      subject_types = User::Resources.all_prefixed_subject_types(permissions)
      return if subject_types.empty?

      Permissions::Service.update_action_for_permissions(
        actor_ids: [authorization.ability_id],
        actor_type: authorization.ability_type,
        subject_types: subject_types,
        action: :write,
        entry_point: entry_point
      )
    end

    def downgrade_user_permissions(authorization, permissions:)
      subject_types = User::Resources.all_prefixed_subject_types(permissions)
      return if subject_types.empty?

      Permissions::Service.update_action_for_permissions(
        actor_ids: [authorization.ability_id],
        actor_type: authorization.ability_type,
        subject_types: subject_types,
        action: :read,
        entry_point: entry_point
      )
    end

    def remove_user_permissions(authorization, permissions:)
      subject_types = User::Resources.all_prefixed_subject_types(permissions)
      return if subject_types.empty?

      Permissions::Service.revoke_permissions_granted_on_actor(
        actor_id: authorization.ability_id,
        actor_type: authorization.ability_type,
        subject_types: subject_types,
        entry_point: entry_point
      )
    end
  end
end
