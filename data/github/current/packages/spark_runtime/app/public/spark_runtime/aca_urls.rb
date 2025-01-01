# typed: strict
# frozen_string_literal: true

# All URL creation for talking to ACA should go through this class and be
# carefully validated and vetted given that our use-case has those values coming
# from clients.
module SparkRuntime
  class AcaUrls
    class InvalidUrlError < StandardError; end

    sig { params(owner_login: String, database_name: String, is_segregated: T::Boolean).returns(String) }
    def self.kv_url(owner_login, database_name, is_segregated)
      validate_name!(owner_login)
      validate_name!(database_name)

      segregation_segment = "users." if is_segregated

      "https://#{database_name}--#{owner_login}.#{segregation_segment}data.github.app/keyValuePairs"
    end

    sig { params(owner_permanent_name: String, database_name: String).returns(String) }
    def self.kv_url_11(owner_permanent_name, database_name)
      validate_name!(owner_permanent_name)
      validate_name!(database_name)

      "https://#{database_name}--#{owner_permanent_name}.data.github.app/keyValuePairs"
    end

    sig { params(owner_login: String, app_name: String, revision_name: T.nilable(String), is_segregated: T::Boolean).returns(String) }
    def self.deployment_url(owner_login, app_name, revision_name, is_segregated)
      validate_name!(owner_login)
      validate_name!(app_name)
      validate_name!(revision_name) if revision_name

      segregation_segment = "users." if is_segregated

      revision_part = "#{revision_name}--" if revision_name.present?
      "https://#{revision_part}#{app_name}--#{owner_login}.#{segregation_segment}github.app/preview/upload"
    end

    sig { params(user_id: String).returns(String) }
    def self.management_user_url(user_id)
      validate_name!(user_id)
      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_user = EscapeUtils.escape_uri_component(user_id)
      "https://management.github.app/api/users/#{escaped_user}"
    end

    sig { params(owner_permanent_name: String).returns(String) }
    def self.management_user_url_11(owner_permanent_name)
      validate_name!(owner_permanent_name)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_owner = EscapeUtils.escape_uri_component(owner_permanent_name)
      "https://management.github.app/api/users/#{escaped_owner}#{api_version_11}"
    end

    sig { params(owner_login: String, app_name: String, revision_name: T.nilable(String)).returns(String) }
    def self.management_app_url(owner_login, app_name, revision_name = nil)
      validate_name!(owner_login)
      validate_name!(app_name)
      validate_name!(revision_name) if revision_name

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      revision_part = "/revisions/#{EscapeUtils.escape_uri_component(revision_name)}" if revision_name.present?
      escaped_owner = EscapeUtils.escape_uri_component(owner_login)
      escaped_app_name = EscapeUtils.escape_uri_component(app_name)
      "https://management.github.app/api/users/#{escaped_owner}/apps/#{escaped_app_name}#{revision_part}"
    end

    sig { params(owner_permanent_name: String, app_name: String, revision_name: T.nilable(String)).returns(String) }
    def self.management_app_url_11(owner_permanent_name, app_name, revision_name = nil)
      validate_name!(owner_permanent_name)
      validate_name!(app_name)
      validate_name!(revision_name) if revision_name

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      revision_part = "/revisions/#{EscapeUtils.escape_uri_component(revision_name)}" if revision_name.present?
      escaped_owner = EscapeUtils.escape_uri_component(owner_permanent_name)
      escaped_app_name = EscapeUtils.escape_uri_component(app_name)
      "https://management.github.app/api/users/#{escaped_owner}/apps/#{escaped_app_name}#{revision_part}#{api_version_11}"
    end

    sig { params(owner_login: String, app_name: String, revision_name: String).returns(String) }
    def self.management_app_deploys_url(owner_login, app_name, revision_name)
      validate_name!(owner_login)
      validate_name!(app_name)
      validate_name!(revision_name)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_owner = EscapeUtils.escape_uri_component(owner_login)
      escaped_app_name = EscapeUtils.escape_uri_component(app_name)
      escaped_revision = EscapeUtils.escape_uri_component(revision_name)
      "https://management.github.app/api/users/#{escaped_owner}/apps/#{escaped_app_name}/revisions/#{escaped_revision}/upload"
    end

    sig { params(owner_permanent_name: String, app_name: String, revision_name: String).returns(String) }
    def self.management_app_deploys_url_11(owner_permanent_name, app_name, revision_name)
      validate_name!(owner_permanent_name)
      validate_name!(app_name)
      validate_name!(revision_name)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_owner = EscapeUtils.escape_uri_component(owner_permanent_name)
      escaped_app_name = EscapeUtils.escape_uri_component(app_name)
      escaped_revision = EscapeUtils.escape_uri_component(revision_name)
      "https://management.github.app/api/users/#{escaped_owner}/apps/#{escaped_app_name}/revisions/#{escaped_revision}/upload#{api_version_11}"
    end

    sig { params(owner_login: String, database_name: String).returns(String) }
    def self.management_kv_url(owner_login, database_name)
      validate_name!(owner_login)
      validate_name!(database_name)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_owner = EscapeUtils.escape_uri_component(owner_login)
      escaped_database_name = EscapeUtils.escape_uri_component(database_name)
      "https://management.github.app/api/users/#{escaped_owner}/databases/#{escaped_database_name}"
    end

    sig { params(owner_permanent_name: String, database_name: String).returns(String) }
    def self.management_kv_url_11(owner_permanent_name, database_name)
      validate_name!(owner_permanent_name)
      validate_name!(database_name)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_owner = EscapeUtils.escape_uri_component(owner_permanent_name)
      escaped_database_name = EscapeUtils.escape_uri_component(database_name)
      "https://management.github.app/api/users/#{escaped_owner}/databases/#{escaped_database_name}#{api_version_11}"
    end

    sig { params(name: String).void }
    def self.validate_name!(name)
      raise InvalidUrlError unless name.match(/\A[a-zA-Z0-9-]{1,20}\z/)

      raise InvalidUrlError if name.start_with?("-") ||
        name.end_with?("-") ||
        name.include?("--")
    end

    sig { returns(String) }
    def self.api_version_11
      "?api-version=1.1"
    end
  end
end
