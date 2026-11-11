# typed: strict
# frozen_string_literal: true

# All URL creation for talking to ACA should go through this class and be
# carefully validated and vetted given that our use-case has those values coming
# from clients.
module SparkRuntime
  class AcaUrls
    class InvalidUrlError < StandardError; end

    sig { params(owner_login: String, database_name: String, is_segregated: T::Boolean, is_beta: T::Boolean).returns(String) }
    def self.kv_url(owner_login, database_name, is_segregated, is_beta)
      validate_name!(owner_login)
      validate_name!(database_name)

      segment_segregation = "users." if is_segregated
      core = core_url(is_beta)

      "https://#{database_name}--#{owner_login}.#{segment_segregation}data.#{core}/keyValuePairs"
    end

    sig { params(owner_permanent_name: String, database_name: String, is_beta: T::Boolean).returns(String) }
    def self.kv_url_11(owner_permanent_name, database_name, is_beta)
      validate_name!(owner_permanent_name)
      validate_name!(database_name)

      core = core_url(is_beta)

      "https://#{database_name}--#{owner_permanent_name}.data.#{core}/keyValuePairs"
    end

    sig { params(owner_login: String, app_name: String, revision_name: T.nilable(String), is_segregated: T::Boolean, is_beta: T::Boolean).returns(String) }
    def self.deployment_url(owner_login, app_name, revision_name, is_segregated, is_beta)
      validate_name!(owner_login)
      validate_name!(app_name)
      validate_name!(revision_name) if revision_name

      segment_segregation = "users." if is_segregated
      core = core_url(is_beta)

      revision_part = "#{revision_name}--" if revision_name.present?
      "https://#{revision_part}#{app_name}--#{owner_login}.#{segment_segregation}#{core}/preview/upload"
    end

    sig { params(user_id: String, is_beta: T::Boolean).returns(String) }
    def self.management_user_url(user_id, is_beta)
      validate_name!(user_id)

      core = core_url(is_beta)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_user = EscapeUtils.escape_uri_component(user_id)
      "https://management.#{core}/api/users/#{escaped_user}"
    end

    sig { params(owner_permanent_name: String, is_beta: T::Boolean).returns(String) }
    def self.management_user_url_11(owner_permanent_name, is_beta)
      validate_name!(owner_permanent_name)

      core = core_url(is_beta)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_owner = EscapeUtils.escape_uri_component(owner_permanent_name)
      "https://management.#{core}/api/users/#{escaped_owner}#{api_version_11}"
    end

    sig { params(owner_login: String, app_name: String, revision_name: T.nilable(String), is_beta: T::Boolean).returns(String) }
    def self.management_app_url(owner_login, app_name, revision_name, is_beta)
      validate_name!(owner_login)
      validate_name!(app_name)
      validate_name!(revision_name) if revision_name

      core = core_url(is_beta)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      revision_part = "/revisions/#{EscapeUtils.escape_uri_component(revision_name)}" if revision_name.present?
      escaped_owner = EscapeUtils.escape_uri_component(owner_login)
      escaped_app_name = EscapeUtils.escape_uri_component(app_name)
      "https://management.#{core}/api/users/#{escaped_owner}/apps/#{escaped_app_name}#{revision_part}"
    end

    sig { params(owner_permanent_name: String, app_name: String, revision_name: T.nilable(String), is_beta: T::Boolean).returns(String) }
    def self.management_app_url_11(owner_permanent_name, app_name, revision_name, is_beta)
      validate_name!(owner_permanent_name)
      validate_name!(app_name)
      validate_name!(revision_name) if revision_name

      core = core_url(is_beta)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      revision_part = "/revisions/#{EscapeUtils.escape_uri_component(revision_name)}" if revision_name.present?
      escaped_owner = EscapeUtils.escape_uri_component(owner_permanent_name)
      escaped_app_name = EscapeUtils.escape_uri_component(app_name)
      "https://management.#{core}/api/users/#{escaped_owner}/apps/#{escaped_app_name}#{revision_part}#{api_version_11}"
    end

    sig { params(owner_login: String, app_name: String, revision_name: String, is_beta: T::Boolean).returns(String) }
    def self.management_app_deploys_url(owner_login, app_name, revision_name, is_beta)
      validate_name!(owner_login)
      validate_name!(app_name)
      validate_name!(revision_name)

      core = core_url(is_beta)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_owner = EscapeUtils.escape_uri_component(owner_login)
      escaped_app_name = EscapeUtils.escape_uri_component(app_name)
      escaped_revision = EscapeUtils.escape_uri_component(revision_name)
      "https://management.#{core}/api/users/#{escaped_owner}/apps/#{escaped_app_name}/revisions/#{escaped_revision}/upload"
    end

    sig { params(owner_permanent_name: String, app_name: String, revision_name: String, is_beta: T::Boolean).returns(String) }
    def self.management_app_deploys_url_11(owner_permanent_name, app_name, revision_name, is_beta)
      validate_name!(owner_permanent_name)
      validate_name!(app_name)
      validate_name!(revision_name)

      core = core_url(is_beta)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_owner = EscapeUtils.escape_uri_component(owner_permanent_name)
      escaped_app_name = EscapeUtils.escape_uri_component(app_name)
      escaped_revision = EscapeUtils.escape_uri_component(revision_name)
      "https://management.#{core}/api/users/#{escaped_owner}/apps/#{escaped_app_name}/revisions/#{escaped_revision}/upload#{api_version_11}"
    end

    sig { params(owner_login: String, database_name: String, is_beta: T::Boolean).returns(String) }
    def self.management_kv_url(owner_login, database_name, is_beta)
      validate_name!(owner_login)
      validate_name!(database_name)

      core = core_url(is_beta)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_owner = EscapeUtils.escape_uri_component(owner_login)
      escaped_database_name = EscapeUtils.escape_uri_component(database_name)
      "https://management.#{core}/api/users/#{escaped_owner}/databases/#{escaped_database_name}"
    end

    sig { params(owner_permanent_name: String, database_name: String, is_beta: T::Boolean).returns(String) }
    def self.management_kv_url_11(owner_permanent_name, database_name, is_beta)
      validate_name!(owner_permanent_name)
      validate_name!(database_name)

      core = core_url(is_beta)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      escaped_owner = EscapeUtils.escape_uri_component(owner_permanent_name)
      escaped_database_name = EscapeUtils.escape_uri_component(database_name)
      "https://management.#{core}/api/users/#{escaped_owner}/databases/#{escaped_database_name}#{api_version_11}"
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

    sig { params(is_beta: T::Boolean).returns(String) }
    def self.core_url(is_beta)
      if is_beta
        "beta.github.app"
      else
        "github.app"
      end
    end
  end
end
