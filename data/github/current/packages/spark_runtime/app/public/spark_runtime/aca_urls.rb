# typed: strict
# frozen_string_literal: true

# All URL creation for talking to ACA should go through this class and be
# carefully validated and vetted given that our use-case has those values coming
# from clients.
module SparkRuntime
  class AcaUrls
    class InvalidUrlError < StandardError; end

    sig { params(owner_login: String, database_name: String).returns(String) }
    def self.kv_url(owner_login, database_name)
      validate_name!(owner_login)
      validate_name!(database_name)

      "https://#{database_name}--#{owner_login}.data.github.app/keyValuePairs"
    end

    sig { params(owner_login: String, app_name: String, revision_name: T.nilable(String)).returns(String) }
    def self.deployment_url(owner_login, app_name, revision_name = nil)
      validate_name!(owner_login)
      validate_name!(app_name)
      validate_name!(revision_name) if revision_name

      revision_part = "#{revision_name}--" if revision_name.present?
      "https://#{revision_part}#{app_name}--#{owner_login}.github.app/preview/upload"
    end

    sig { params(owner_login: String, app_name: String, revision_name: T.nilable(String)).returns(String) }
    def self.management_app_url(owner_login, app_name, revision_name = nil)
      validate_name!(owner_login)
      validate_name!(app_name)
      validate_name!(revision_name) if revision_name

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      revision_part = "/revisions/#{EscapeUtils.escape_uri_component(revision_name)}" if revision_name.present?
      "https://management.github.app/api/users/#{EscapeUtils.escape_uri_component(owner_login)}/apps/#{EscapeUtils.escape_uri_component(app_name)}#{revision_part}"
    end

    sig { params(owner_login: String, database_name: String).returns(String) }
    def self.management_kv_url(owner_login, database_name)
      validate_name!(owner_login)
      validate_name!(database_name)

      # Escapes _should_ be irrelevant with prior checks, but get those belt and suspenders on folks!
      "https://management.github.app/api/users/#{EscapeUtils.escape_uri_component(owner_login)}/databases/#{EscapeUtils.escape_uri_component(database_name)}"
    end

    sig { params(name: String).void }
    def self.validate_name!(name)
      raise InvalidUrlError unless name.match(/\A[a-zA-Z0-9-]{1,20}\z/)

      raise InvalidUrlError if name.start_with?("-") ||
        name.end_with?("-") ||
        name.include?("--")
    end
  end
end
