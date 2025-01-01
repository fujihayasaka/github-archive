# typed: true
# frozen_string_literal: true

module GitHub
  module ApplicationsCreationLimit
    include ActiveSupport::Concern

    extend T::Helpers

    requires_ancestor { Kernel }

    # The default max number of applications (per type of app) an application owner can create
    DEFAULT_MAX_APPLICATIONS_CREATION_LIMIT = 100

    # Public: Sets an applications creation limit scoped to the application owner and the
    # type of application
    #
    # application           - An instance of OauthApplication or Integration
    # limit                 - Integer, the custom creation limit for the application owner
    #
    # Returns nothing
    def set_custom_applications_limit(application, limit)
      limit = Integer(limit)
      raise ArgumentError.new("limit can't be negative") if limit < 0

      key = applications_limit_key_for(application)
      GitHub.kv.set(key, limit.to_s) # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    # Public: Determines the application owner's applications creation limit for the given type
    # of application
    #
    # Returns an integer
    def applications_creation_limit(application)
      key = applications_limit_key_for(application)
      (GitHub.kv.get(key).value! || DEFAULT_MAX_APPLICATIONS_CREATION_LIMIT).to_i # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    # Public: Determines if this user has reached the creation limit for the given
    # type of application
    #
    # Returns an boolean
    #
    # TODO: refactor all methods to follow this signature
    # https://github.com/github/github/pull/111065#discussion_r270522525
    def reached_applications_creation_limit?(application_type:)
      return false if GitHub.enterprise? || proxima_synced_apps_owner?

      application_type.created_by_count(self) >= self.applications_creation_limit(application_type.new)
    end

    private

    def applications_limit_key_for(application)
      T.bind(self, T.any(Business, Organization, User))
      "#{T.must(self.class.name).pluralize}.#{application.class.name.underscore}.creation_limit.#{self.id}"
    end

    def proxima_synced_apps_owner?
      T.bind(self, T.any(Business, Organization, User))
      return false unless self.feature_enabled?(:ignore_app_creation_limit) && GitHub.multi_tenant_enterprise? && self.is_a?(Organization)

      self.display_login == GitHub.proxima_third_party_apps_owner_login ||
        self.display_login == GitHub.first_party_apps_org_name
    end
  end
end
