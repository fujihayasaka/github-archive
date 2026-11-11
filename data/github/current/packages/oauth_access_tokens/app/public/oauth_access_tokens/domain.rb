# typed: strict
# frozen_string_literal: true

require "scientist"

module OauthAccessTokens
  class Domain < GH::Domain::Base
    include Scientist

    accessor OauthApplications

    class CreateResult
      include Scientist

      sig { returns(IOauthAccess) }
      attr_reader :token_record

      sig { returns(String) }
      attr_reader :token_value

      # initialize the CreateResult
      sig { params(token_record: IOauthAccess, token_value: String).void }
      def initialize(token_record, token_value)
        @token_record = T.let(token_record, IOauthAccess)
        @token_value = T.let(token_value, String)
      end

      # Ruby calls to_ary automatically when using multiple assignment (a, b = obj)
      # this lets us do: record, token = result.value if result.is_a?(GH::Result::Ok) (result.value would otherwise return the CreateResult instance)
      # and lets us avoid separate result.value.token_record & result.value.token_value assignment
      sig { returns(T::Array[T.untyped]) }
      def to_ary
        [token_record, token_value]
      end
    end

    class PaginatedListResult
      sig { returns(T::Array[IOauthAccess]) }
      attr_reader :items

      sig { returns(Integer) }
      attr_reader :page

      sig { returns(Integer) }
      attr_reader :per_page

      # nil means "not computed"
      sig { returns(T.nilable(Integer)) }
      attr_reader :total_entries

      # Builds a container for paginated authorization results.
      sig do
        params(
          items: T::Array[IOauthAccess],
          page: Integer,
          per_page: Integer,
          total_entries: T.nilable(Integer)
        ).void
      end
      def initialize(items:, page:, per_page:, total_entries:)
        @items = T.let(items, T::Array[IOauthAccess])
        @page = T.let(page, Integer)
        @per_page = T.let(per_page, Integer)
        @total_entries = T.let(total_entries, T.nilable(Integer))
      end
    end

    class StatelessTokenResult
      # Public: The stateless token string, starts with "ghu_". Can be exchanged with authnd for an IET.
      sig { returns(String) }
      attr_reader :token

      # Public: A unique identifier for the stateless token, the JTI.
      sig { returns(String) }
      attr_reader :token_id

      # Public: An integer representation of token_id.
      sig { returns(Integer) }
      attr_reader :credential_id

      # Public: Builds a container for a stateless token and its identifier.
      sig { params(token: String, token_id: String, credential_id: Integer).void }
      def initialize(token, token_id:, credential_id:)
        @token = token
        @token_id = token_id
        @credential_id = credential_id
      end
    end

    # Any access looked up using `code` should be considered expired after 10
    # minutes.
    CODE_EXPIRY = T.let(10.minutes, ActiveSupport::Duration)

    # Require token to be a 40 hex character string
    TOKEN_LEGACY_PATTERN = /\A[a-f0-9]{40}\z/

    # Returns the throttling configuration value for access token operations from the OauthAccess model
    sig { returns(Integer) }
    def self.access_throttling
      OauthAccess::ACCESS_THROTTLING
    end

    # Returns the cutoff date for access token validity from the OauthAccess model
    sig { returns(Time) }
    def self.access_cutoff_date
      OauthAccess::ACCESS_CUTOFF_DATE
    end

    # Returns the default installation token expiry value from the OauthAccess model
    sig { returns(ActiveSupport::Duration) }
    def self.default_installation_token_expiry
      OauthAccess::DEFAULT_INSTALLATION_TOKEN_EXPIRY
    end

    # Need to use a class method for the OauthAccess constants to be available
    sig { returns(Regexp).checked(:always).on_failure(:raise) }
    def self.token_regex
      %r{
        \A                                            # start
        (#{OauthAccess::OAUTH_PREFIX}|
         #{OauthAccess::PAT_PREFIX}|
         #{OauthAccess::USER_TO_SERVER_PREFIX})       # the possible token format prefixes
        [a-zA-Z0-9]{#{OauthAccess::TOKEN_LENGTH}}     # the random portion and checksum
        \z                                            # end
      }xi
    end

    # Normalizes the given scopes using the OauthAccess module.
    #
    # @param scopes [Array<String>] or String - The scopes to be normalized.
    # @param options [Hash, nil] - Optional parameters for normalization.
    # @return [Array<String>] - The normalized scopes.
    sig { params(scopes: T.untyped, options: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T::Array[String]).checked(:always).on_failure(:raise) }
    def self.normalize_scopes(scopes, options = nil)
      OauthAccess.normalize_scopes(scopes, options)
    end

    # Public: Determine if a given OAuth access should be enforced by a SAML check.
    #
    # is_personal_access_token - Boolean indicating whether or not the OAuth access in question is for a personal access token
    # application - the relevant application for the OAuth access
    sig do
      params(
        is_personal_access_token: T.nilable(T::Boolean),
        application: T.nilable(T.any(Integration, OauthApplication))
      ).returns(T::Boolean)
    end
    def self.saml_enforceable?(is_personal_access_token:, application:)
      OauthAccess.saml_enforceable?(is_personal_access_token: is_personal_access_token, application: application)
    end

    # Public: Determine what type of programmatic access token an OAuth access represents.
    #
    # is_personal_access_token - Boolean indicating whether or not the OAuth access in question is for a personal access token
    sig { params(is_personal_access_token: T.nilable(T::Boolean)).returns(T.nilable(ProgrammaticAccessTokenType)) }
    def self.programmatic_access_token_type(is_personal_access_token:)
      OauthAccess.programmatic_access_token_type(is_personal_access_token: is_personal_access_token)
    end

    # Public: Determine if a personal access token is eligible for account recovery.
    #
    # created_by                - Date by which the token must be created
    # expires_at_timestamp      - Unix timestamp of when the token expires (nil = never)
    # created_at                - When the token was created
    # is_personal_access_token  - Whether this is a personal access token
    # scopes                    - The scopes granted to this token
    sig do
      params(
        created_by: T.any(Date, Time, ActiveSupport::TimeWithZone),
        expires_at_timestamp: T.nilable(Integer),
        created_at: T.any(Date, Time, ActiveSupport::TimeWithZone),
        is_personal_access_token: T::Boolean,
        scopes: T.nilable(T::Array[String])
      ).returns(T::Boolean)
    end
    def self.personal_access_token_eligible_for_account_recovery?(created_by:, expires_at_timestamp:, created_at:, is_personal_access_token:, scopes:)
      OauthAccess.personal_access_token_eligible_for_account_recovery?(
        created_by: created_by,
        expires_at_timestamp: expires_at_timestamp,
        created_at: created_at,
        is_personal_access_token: is_personal_access_token,
        scopes: scopes,
      )
    end

    # Public: Filter scopes to only those recognized as valid access levels.
    #
    # scopes - Array of scope strings
    #
    # Returns an Array of String access levels.
    sig { params(scopes: T.nilable(T::Array[T.untyped])).returns(T::Array[String]) }
    def self.access_level_from(scopes)
      OauthAccess.access_level_from(scopes)
    end

    # Public: Build a fallback Integration instance for a given application ID.
    #
    # application_id - The Integer ID of the integration application
    #
    # Returns an Integration.
    sig { params(application_id: T.nilable(Integer)).returns(Integration) }
    def self.fallback_integration(application_id:)
      OauthAccess.fallback_integration(application_id: application_id)
    end

    # Public: Build a fallback OauthApplication with a description and note URL.
    #
    # description - The String description for the fallback application
    # note_url    - The String note URL for the fallback application
    #
    # Returns an OauthApplication.
    sig { params(description: T.nilable(String), note_url: T.nilable(String)).returns(OauthApplication) }
    def self.fallback_oauth_application(description:, note_url:)
      OauthAccess.fallback_oauth_application(description: description, note_url: note_url)
    end

    # Filter an array of scopes to only those that are public
    # on the OAuth authorization form.
    #
    # Returns an Array of String scopes
    sig { params(scopes: T.untyped).returns(T::Array[String]).checked(:always).on_failure(:raise) }
    def self.filter_public_scopes(scopes)
      OauthAccess.filter_public_scopes(scopes)
    end

    # Public: Returns the scopes that are invalid for the given application
    sig { params(scopes: T.untyped).returns(T::Array[String]).checked(:always).on_failure(:raise) }
    def self.invalid_scopes(scopes)
      OauthAccess.invalid_scopes(scopes)
    end

    # Public: Returns the scopes that are valid for the given application
    sig { returns(T.untyped).checked(:always).on_failure(:raise) }
    def self.valid_hidden_scopes
      OauthAccess.valid_hidden_scopes(nil)
    end

    # Public: Checks if the given key is a client ID for any of the registered classes
    # If the application_klass is provided, it will only check that class
    sig { params(key: String, application_klass: T.nilable(OauthAccess::ClientId::ClassInterface)).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def self.client_id?(key, application_klass: nil)
      OauthAccess::ClientId.client_id?(key, application_klass: application_klass)
    end

    # Public: Checks if the given token matches an OAuth Access pattern
    #
    # token - The string to check
    #
    # Returns true if token follows an OAuth Access pattern,
    #   false if it doesn't
    sig { params(token: T.untyped).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def self.matches_pattern?(token)
      token_regex.match?(token) || TOKEN_LEGACY_PATTERN.match?(token)
    end

    # Public: Returns true if the token is a stateless U2S JWT (ghu_ prefix + JWT structure).
    #
    # Example of stateless U2S token format: "ghu_eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature"
    #
    # token - String: the raw token value.
    #
    # Returns a Boolean.
    sig { params(token: T.nilable(String)).returns(T::Boolean) }
    def self.stateless_u2s_token?(token)
      return false if token.blank?

      token.start_with?(OauthAccess::USER_TO_SERVER_PREFIX) &&
        token.count(".") == 2
    end

    # Public: Token hashing method
    #
    # token - The string to check
    #
    # Returns hashed token for server side persistence.
    sig { params(token: T.nilable(String)).returns(String).checked(:always).on_failure(:raise) }
    def self.hash_token(token)
      OauthAccess.hash_token(token)
    end

    # Validate token checksum
    #
    # token - The string to check
    #
    # Returns true if the token checksum is valid, false otherwise.
    sig { params(token: T.nilable(String)).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def self.valid_checksum?(token)
      # Legacy tokens don't have a checksum
      return false if TOKEN_LEGACY_PATTERN.match?(token)
      OauthAccess.validate_token_checksum(token)
    end

    # Public: Instrumentation for email verification required
    sig { params(user: Users::IUser, application_id: Integer).void.checked(:always).on_failure(:raise) }
    def self.instrument_email_verification_required(user:, application_id:)
      GitHub.dogstats.increment "oauth_access", tags: ["action:email-verification", "valid:false", "user_signup_timeframe:#{T.cast(user, User).signup_timeframe}"]
      GitHub.logger.info(
        "gh.oauth_application.id" => application_id,
        "enduser.id" => user.login,
        "code.function" => "owner_meets_email_verification_requirements",
        "http.status_code" => "email_verification_required"
      )
    end

    # creates temporary unsaved OauthAccess record
    sig { params(user_id: Integer, description: T.nilable(String), default_expiration: T.nilable(String), scopes: T::Array[String], application: T.nilable(OauthApplication)).returns(IOauthAccess).checked(:always).on_failure(:raise) }
    def self.build(user_id, description, default_expiration, scopes, application: nil)
      access = OauthAccess.new(
        user_id: user_id,
        description: description,
        scopes: scopes,
      )
      access.application = application if application.present?
      access.default_expires_at = default_expiration if default_expiration.present?
      access
    end

    # Finds an OauthAccess by its id
    sig { params(id: T.nilable(Integer), strict: T::Boolean).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise) }
    def by_id(id, strict: false)
      if FeatureFlag.vexi.enabled?(:oauth_access_read_replica, default: false)
        access = ActiveRecord::Base.connected_to(role: :reading) { strict ? OauthAccess.find(T.must(id)) : OauthAccess.find_by(id: id) }
        if access.nil?
          access = ActiveRecord::Base.connected_to(role: :writing) do
            strict ? OauthAccess.find(T.must(id)) : OauthAccess.find_by(id: id)
          end
          GitHub.dogstats.increment("oauth_access.fallback_to_primary", tags: ["found_on_primary:#{!access.nil?}", "method:by_id"])
        end
        access
      else
        strict ? OauthAccess.find(T.must(id)) : OauthAccess.find_by(id: id)
      end
    end

    # Finds OauthAccesses by ids
    sig { params(ids: T::Array[T.nilable(Integer)], entry_point: T.nilable(Symbol)).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def by_ids(ids, entry_point: nil)
      if FeatureFlag.vexi.enabled?(:oauth_access_read_replica, default: false)
        accesses = ActiveRecord::Base.connected_to(role: :reading) { OauthAccess.where(id: ids).to_a }

        if accesses.empty?
          accesses = ActiveRecord::Base.connected_to(role: :writing) do
            OauthAccess.where(id: ids).to_a
          end
          GitHub.dogstats.increment("oauth_access.fallback_to_primary", tags: ["found_on_primary:#{!accesses.empty?}", "method:by_ids"])
        end
        accesses
      else
        OauthAccess.where(id: ids).to_a
      end
    end

    # Finds OauthAccesses by user and ids
    sig { params(user_id: Integer, ids: T::Array[T.nilable(Integer)]).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def by_user_and_ids(user_id, ids)
      OauthAccess.where(user_id: user_id, id: ids).to_a
    end

    # Finds OauthAccesses by user
    #
    # @param user_id [Integer] The ID of the user whose tokens to find
    # @return [Array<IOauthAccess>] Array of OAuth accesses for the user
    sig { params(user_id: Integer).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def by_user(user_id)
      OauthAccess.where(user_id: user_id).to_a
    end

    # Finds all OauthAccesses for a given authorization
    #
    # @param authorization_id [Integer] The ID of the authorization whose accesses to find
    # @return [Array<IOauthAccess>] Array of OAuth accesses for the authorization
    sig { params(authorization_id: Integer).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def by_authorization_id(authorization_id)
      OauthAccess.where(authorization_id: authorization_id).to_a
    end

    # Finds paginated OauthAccesses for a given authorization
    #
    # @param authorization_id [Integer] The ID of the authorization whose accesses to find
    # @param page [Integer, nil] Current page number (defaults to 1)
    # @param per_page [Integer, nil] Number of records per page (defaults to 10)
    # @return [Array<IOauthAccess>] Array of paginated OAuth accesses for the authorization
    sig { params(authorization_id: Integer, page: T.nilable(Integer), per_page: T.nilable(Integer)).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def by_authorization_id_paginated(authorization_id, page: nil, per_page: nil)
      page ||= 1
      per_page ||= 10
      OauthAccess.where(authorization_id: authorization_id)
                 .limit(per_page)
                 .page(page)
                 .to_a
    end

    # Lists OAuth accesses for a user with optional app filtering and paginated metadata.
    #
    # @param user_id [Integer] The user id owning the accesses
    # @param page [Integer] Current page number
    # @param per_page [Integer] Number of records per page
    # @param client_id [String, nil] Optional OAuth app or integration client id
    # @param total_entries_cap [Integer, nil] Optional cap for count query
    # @param skip_total_entries_count [Boolean] Whether to skip total entries counting
    # @return [PaginatedListResult] The paginated items and optional total entries
    sig do
      params(
        user_id: Integer,
        page: Integer,
        per_page: Integer,
        client_id: T.nilable(String),
        total_entries_cap: T.nilable(Integer), # mirrors pagination_opts[:total_entries]
        skip_total_entries_count: T::Boolean
      ).returns(PaginatedListResult)
    end
    def list_authorizations_for_user(
      user_id:,
      page:,
      per_page:,
      client_id: nil,
      total_entries_cap: nil,
      skip_total_entries_count: false
    )
      # Build the base relation (note: we’re intentionally not returning it)
      rel = OauthAccess.where(user_id: user_id)
                       .preload(:application, :authorization)

      if client_id.present?
        # Apply client_id filtering within the user-scoped relation.
        # We resolve the application IDs in Ruby first, then filter by them in SQL
        # so that the user_id scope is preserved (avoids a cross-user join).
        if client_id == OauthApplication::PERSONAL_TOKENS_CLIENT_ID
          rel = rel.where(application_id: OauthApplication::PERSONAL_TOKENS_APPLICATION_ID)
        elsif Integration.client_id?(client_id)
          app_ids = Integration.where(key: client_id).pluck(:id)
          rel = rel.where(application_type: Integration.name, application_id: app_ids)
        else
          app_ids = OauthApplication.where(key: client_id).pluck(:id)
          rel = rel.where(application_type: OauthApplication.name, application_id: app_ids)
        end
      end

      items = rel.limit(per_page).page(page).to_a

      total_entries = nil
      if total_entries_cap && !skip_total_entries_count
        # Mirror paginate_rel’s capped count strategy:
        # - unscope order/select
        # - limit to total_entries_cap
        # - count rows via subquery selecting constant
        count_rel = rel.unscope(:order, :select).select("1 as one").limit(total_entries_cap)
        total_entries = OauthAccess.unscoped.from(count_rel, :oauth_accesses_count).count
      end

      PaginatedListResult.new(
        items: items,
        page: page,
        per_page: per_page,
        total_entries: total_entries
      )
    end

    # Finds an OauthAccess by hash
    sig { params(hash: String).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise)  }
    def by_hash(hash)
      OauthAccess.find_by(hashed_token: hash)
    end

    # Finds an OauthAccess given a hashed or unhashed token string
    sig { params(token: T.untyped, hashed: T::Boolean).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise) }
    def active(token, hashed: false)
      OauthAccess.with_active_token(token, hashed: hashed)
    end

    # Finds an OauthAccess given a token string, scoped to a specific application.
    # ALWAYS filters by both application_id AND application_type to avoid ID collisions
    # across polymorphic types (OauthApplication vs Integration).
    sig do
      params(
        token: T.untyped,
        application_id: Integer,
        application_type: String,
        hashed: T::Boolean
      ).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise)
    end
    def active_for_application(token, application_id:, application_type:, hashed: false)
      return nil if !token.is_a?(String) || token.blank?

      hashed_token = hashed ? token : OauthAccess.hash_token(token)
      access = OauthAccess.where(
        application_id: application_id,
        application_type: application_type
      ).find_by(hashed_token: hashed_token)

      return nil if access.nil?
      return nil if access.expired?

      access
    end

    # Finds personal OauthAccess ids by user
    sig { params(actor_id: Integer).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def personal_token_ids(actor_id)
      OauthAccess.where(user_id: actor_id).personal_tokens.ids
    end

    # Finds third-party OAuth access ids for a user.
    sig { params(actor_id: Integer).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def third_party_token_ids(actor_id)
      excluded_oauth_app_ids = oauth_applications.trusted_app_ids + [OauthApplication::PERSONAL_TOKENS_APPLICATION_ID]

      oauth_app_ids = OauthAccess.where(user_id: actor_id, application_type: OauthApplication.name)
        .where.not(application_id: excluded_oauth_app_ids)
        .pluck(:id)

      excluded_integration_ids = Integration.first_party.ids
      integration_ids = OauthAccess.github_apps.where(user_id: actor_id)
        .where.not(application_id: excluded_integration_ids)
        .pluck(:id)

      oauth_app_ids + integration_ids
    end

    # Finds personal token count for a user
    sig { params(actor_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def personal_tokens_count(actor_id)
      OauthAccess.where(user_id: actor_id).personal_tokens.size
    end

    # Returns true if the user has at least one personal token
    sig { params(actor_id: Integer).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def any_personal_tokens?(actor_id)
      OauthAccess.where(user_id: actor_id).personal_tokens.exists?
    end

    # Returns true if the user has at least one third-party token
    sig { params(actor_id: Integer).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def any_third_party_tokens?(actor_id)
      third_party_token_ids(actor_id).any?
    end

    # Finds personal tokens for a user
    sig { params(actor_id: Integer).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def personal_tokens(actor_id)
      OauthAccess.where(user_id: actor_id).personal_tokens.to_a
    end

    # Finds personal tokens with pagination support.
    sig do
      params(
        page: Integer,
        per_page: Integer,
        total_entries_cap: T.nilable(Integer),
        skip_total_entries_count: T::Boolean
      ).returns(PaginatedListResult)
    end
    def list_personal_tokens(
      page:,
      per_page:,
      total_entries_cap: nil,
      skip_total_entries_count: false
    )
      rel = OauthAccess.personal_tokens.order(:accessed_at)
                       .preload(:application, :authorization, :user)

      items = rel.limit(per_page).page(page).to_a

      total_entries = nil
      if total_entries_cap && !skip_total_entries_count
        count_rel = rel.unscope(:order, :select).select("1 as one").limit(total_entries_cap)
        total_entries = OauthAccess.unscoped.from(count_rel, :personal_tokens_count).count
      end

      PaginatedListResult.new(
        items: items,
        page: page,
        per_page: per_page,
        total_entries: total_entries
      )
    end

    # Public: Find personal tokens expiring between two Unix timestamps, supporting
    # cursor-based pagination via after_id and a record limit.
    #
    # start_time - Integer representing a time as the number of seconds past the Unix epoch
    # end_time - Integer representing a time as the number of seconds past the Unix epoch
    sig do
      params(
        start_time: Integer,
        end_time: Integer,
        after_id: Integer,
        limit: Integer,
      ).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise)
    end
    def personal_tokens_expiring_between(start_time:, end_time:, after_id:, limit:)
      ActiveRecord::Base.connected_to(role: :reading_slow) do
        OauthAccess.throttle do
          OauthAccess
            .personal_tokens
            .where("expires_at_timestamp > ? AND expires_at_timestamp < ?", start_time, end_time)
            .where("id > ?", after_id)
            .order(:id)
            .limit(limit)
            .to_a
        end
      end
    end

    # Finds third party token count for a user
    sig { params(actor_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def third_party_tokens_count(actor_id)
      third_party_token_ids(actor_id).size
    end

    # Finds third party tokens for a user
    sig { params(actor_id: Integer).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def third_party_tokens(actor_id)
      access_ids = third_party_token_ids(actor_id)
      by_user_and_ids(actor_id, access_ids)
    end

    # Finds github app tokens for a user
    sig { params(actor_id: Integer).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def github_app_tokens(actor_id)
      OauthAccess.where(user_id: actor_id).github_apps.to_a
    end

    # Filters installation_ids by those with OauthAccess records
    sig { params(installation_ids: T::Array[Integer], actor_type: String).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def installation_ids_with_accesses(installation_ids, actor_type)
      OauthAccess.where(installation_id: installation_ids, installation_type: actor_type).pluck(:installation_id)
    end

    # Finds a user's OauthAccess by id
    sig { params(user_id: Integer, id: Integer, strict: T::Boolean).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise)  }
    def by_user_and_id(user_id, id, strict: false)
      access = OauthAccess.find_by(user_id: user_id, id: id)
      raise ActiveRecord::RecordNotFound if strict && access.nil?

      access
    end

    # Finds oauthAccesses by users and application
    sig { params(user_ids: T::Array[Integer], application_id: Integer, application_type: String).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise)  }
    def by_users_and_application(user_ids, application_id, application_type)
      accesses = OauthAccess.where(
        user_id: user_ids, application_id: application_id, application_type: application_type
      )

      accesses.to_a
    end

    # Finds a user's OauthAccess by application id and type
    sig { params(user_id: Integer, application_id: Integer, application_type: String).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise) }
    def by_user_and_application_id(user_id, application_id, application_type)
      OauthAccess.find_by(user_id: user_id, application_id: application_id, application_type: application_type)
    end

    # Counts a user's OauthAccesses matching any of the given application ids and type
    sig { params(user_id: Integer, application_ids: T::Array[T.nilable(Integer)], application_type: String).returns(Integer).checked(:always).on_failure(:raise) }
    def count_by_user_and_application_ids(user_id, application_ids, application_type)
      OauthAccess.where(user_id: user_id, application_id: application_ids, application_type: application_type).count
    end

    # Finds a user's OauthAccess by application & fingerprint
    sig { params(user_id: Integer, application_id: Integer, application_type: String, fingerprint: T.nilable(String)).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise) }
    def by_user_app_and_fingerprint(user_id, application_id, application_type, fingerprint)
      OauthAccess.find_by(user_id: user_id, application_id: application_id, application_type: application_type, fingerprint: fingerprint)
    end

    # Finds an OauthAccess by user & hash
    sig { params(user_id: Integer, hash: String).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise) }
    def by_user_and_hash(user_id, hash)
      OauthAccess.find_by(user_id: user_id, hashed_token: hash)
    end

    # Finds a user's personal OauthAccess token by id
    sig { params(user_id: Integer, id: Integer).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise) }
    def personal_token_by_user_and_id(user_id, id)
      OauthAccess.where(user_id: user_id).personal_tokens.find_by(id: id)
    end

    # Finds a user's personal OauthAccess token by id and fingerprint
    sig { params(user_id: Integer, id: Integer, fingerprint: T.nilable(String)).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise) }
    def personal_token_by_user_id_and_fingerprint(user_id, id, fingerprint)
      OauthAccess.where(user_id: user_id).personal_tokens.find_by(id: id, fingerprint: fingerprint)
    end

    # Finds OAuth access tokens by their hashed token values and indexes them by hashed token
    #
    # @param hashed_tokens [Array<String>] Array of hashed tokens to look up
    # @param batch_size [Integer] Number of tokens to process in a batch
    # @return [Hash<String, IOauthAccess>] Hash mapping hashed tokens to their OauthAccess records
    sig { params(hashed_tokens: T::Array[String]).returns(T::Hash[String, IOauthAccess]).checked(:always).on_failure(:raise) }
    def by_hashed_tokens_indexed(hashed_tokens)
      OauthAccess.where(hashed_token: hashed_tokens).index_by(&:hashed_token)
    end

    # Finds OauthAccess records matching any of the given hashed token values.
    #
    # @param hashed_tokens [Array<String>] Array of hashed tokens to look up
    # @return [Array<IOauthAccess>] Array of matching OauthAccess records
    sig { params(hashed_tokens: T::Array[String]).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def by_hashes(hashed_tokens)
      OauthAccess.where(hashed_token: hashed_tokens).to_a
    end

    # Returns the non-unique authorization_ids for accesses matching the given hashed tokens.
    #
    # @param hashed_tokens [Array<String>] Array of hashed tokens to look up
    # @return [Array<Integer>] authorization_ids (may contain duplicates when multiple accesses share an authorization)
    sig { params(hashed_tokens: T::Array[String]).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def authorization_ids_by_hashes(hashed_tokens)
      OauthAccess.where(hashed_token: hashed_tokens).where.not(authorization_id: nil).pluck(:authorization_id)
    end

    # Invalidates all tokens for the given authorizations so `with_active_token` rejects them.
    #
    # @param authorization_ids [Array<Integer>] The authorization IDs whose tokens to invalidate
    # @return [Integer] Number of rows updated
    sig { params(authorization_ids: T::Array[Integer]).returns(Integer).checked(:always).on_failure(:raise) }
    def invalidate_by_authorization_ids(authorization_ids)
      return 0 if authorization_ids.empty?

      OauthAccess.with_write do
        OauthAccess.throttle do
          OauthAccess.where(authorization_id: authorization_ids).where.not(hashed_token: nil).update_all(hashed_token: nil)
        end
      end
    end

    # Returns the non-unique authorization_ids for accesses whose refresh tokens match the given hashes.
    #
    # RefreshToken lives in the IntegrationsCollab DB while OauthAccess lives in the Integrations DB,
    # so this performs a 2-step lookup: refresh token hashes → OauthAccess IDs → authorization IDs.
    #
    # @param hashed_refresh_tokens [Array<String>] Array of hashed refresh token strings
    # @return [Array<Integer>] authorization_ids (may contain duplicates)
    sig { params(hashed_refresh_tokens: T::Array[String]).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def authorization_ids_by_refresh_token_hashes(hashed_refresh_tokens)
      access_ids = RefreshToken.where(hashed_token: hashed_refresh_tokens, refreshable_type: "OauthAccess").pluck(:refreshable_id)
      return [] if access_ids.empty?

      OauthAccess.where(id: access_ids).where.not(authorization_id: nil).pluck(:authorization_id)
    end

    # Finds expired OAuth access tokens that need to be removed
    #
    # @param limit [Integer] The maximum number of expired tokens to return
    # @param days_ago [Integer] Number of days in the past to consider tokens as expired
    # @return [Array<IOauthAccess>] An array of expired OAuth access tokens
    sig { params(start_time: Integer, end_time: Integer).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def expired_by_time_window(start_time, end_time)
      OauthAccess.where("expires_at_timestamp >= ? AND expires_at_timestamp <= ?", start_time, end_time).to_a
    end

    # Find stale OAuth access tokens for cleanup - this is used by the RemoveStaleOauthJob, which doesn't want to delete PATs
    #
    # @param after_duration [ActiveSupport::Duration] Duration after which tokens are considered stale
    # @param batch_size [Integer] Number of tokens to process in a batch
    # @return [Array<Integer>] IDs of stale OAuth access tokens
    sig { params(after_duration: ActiveSupport::Duration, batch_size: Integer).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def stale_application_token_ids(after_duration:, batch_size:)
      # Filter out PATs, only include application tokens
      OauthAccess.where("(accessed_at IS NULL AND created_at < :after) or (accessed_at < :after)", {
        after: after_duration.ago,
      }).where("is_application = 1").limit(batch_size).pluck(:id)
    end

    # extend an access_token accessed_at by its id
    sig { params(token_id: Integer, time: Time).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def bump_accessed!(token_id, time)
      if FeatureFlag.vexi.enabled?(:use_oauth_helper_methods, default: false)
        access = T.cast(by_id(token_id), T.nilable(OauthAccess))
      else
        access = OauthAccess.find_by(id: token_id)
      end

      return GH::Result::Error::NotFound.new unless access
      access.bump!(time)
      GH::Result::Ok.new(true)
    end

    # Expire OAuth access tokens by their IDs
    #
    # @param refreshable_ids [Array<Integer>] The IDs of the tokens to expire
    # @param entry_point [Symbol] The entry point triggering the expiration
    # @return [Array<IOauthAccess>] An array of expired OAuth access tokens
    sig { params(refreshable_ids: T::Array[Integer], entry_point: T.nilable(Symbol)).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def expire_by_ids(refreshable_ids, entry_point:)
      if FeatureFlag.vexi.enabled?(:use_oauth_helper_methods, default: false)
        accesses = T.cast(by_ids(refreshable_ids), T::Array[OauthAccess])
      else
        accesses = OauthAccess.where(id: refreshable_ids).to_a
      end

      OauthAccess.with_write do
        OauthAccess.throttle do
          accesses.map do |access|
            access.expire(entry_point: entry_point)
          end
        end
      end

      accesses
    end

    # Create a new OAuth access token
    #
    # @param user_id [Integer] The ID of the user who owns the token
    # @param application [OauthApplication] The OauthApplication that the token is for
    # @param data [Hash] A hash of parameters to create the token from
    # @option data ["scopes"] [Array<String>] The scopes to assign to the token
    # @option data ["note"] [String] The description/note for the token
    # @option data ["note_url"] [String] The URL for the note
    # @option data ["fingerprint"] [String] The fingerprint for the token
    # @return [GH::Result[CreateResult]] A result containing the created token or an error
    # @return [GH::Result::Error] if the token is invalid or cannot be saved
    sig { params(user_id: Integer, application: T.untyped, data: T::Hash[String, T.untyped]).returns(GH::Result[CreateResult]).checked(:always).on_failure(:raise) }
    def create(user_id, application, data)
      access = OauthAccess.new(
        user_id: user_id,
        application: application,
        scopes: Array(data["scopes"]),
        note: data["note"],
        note_url: data["note_url"],
        fingerprint: data["fingerprint"],
      )
      token = access.set_random_token_pair
      # Build instance before saving it so we track the GTID properly
      # of the save operation.
      last_operations = DatabaseSelector::LastOperations.from_token(token)

      begin
        if !(access.valid? && access.save)
          GH::Result::Error::Unprocessable.new([access.errors])
        else
          # After saving the new token we want to set the last write gtids/timestamps in
          # the cache, so the api DatabaseSelection can use the write DB for newly
          # created tokens and avoid issues due to replication lag.
          last_operations.store_latest_writes
          GH::Result::Ok.new(CreateResult.new(access, token))
        end
      rescue ActiveRecord::RecordNotUnique
        GH::Result::Error.new("An authorization already exists with the given data." \
            " Please provide a unique fingerprint and note and try again.")
      end
    end

    # Public: Creates an OauthAccess for the given user via the OAuth
    # authorization code flow. The access is created with a temporary
    # code (not a token) — call domain.redeem to exchange the code
    # for a token.
    #
    # @param user [User] The user being granted access
    # @param application [Integration, OauthApplication] The app granting access
    # @param scope [String, Array<String>, nil] Granted scopes — comma-separated string or array of strings
    # @param requested_scope [String, Array<String>, nil] Requested scopes — comma-separated string or array of strings
    # @param integration_version_number [String, nil] Integration version number
    # @param user_session [UserSession, nil] User session for CredentialAuthorization grants
    # @param redirect_uri [String, nil] Redirect URI for code exchange verification
    # @param entry_point [Symbol, nil] Entry point for Permission Cluster Activity logging
    # @param code_challenge [String, nil] PKCE code challenge
    # @return [GH::Result[CreateResult]] access record + authorization code on success
    # @return [GH::Result::Error] on validation failure or uniqueness violation
    sig do
      params(
        user: User,
        application: T.any(Integration, OauthApplication),
        scope: T.nilable(T.any(String, T::Array[String])),
        requested_scope: T.nilable(T.any(String, T::Array[String])),
        integration_version_number: T.nilable(String),
        user_session: T.untyped, # UserSession, but typed as untyped to avoid Packwerk dependency on packages/authentication
        redirect_uri: T.nilable(String),
        entry_point: T.nilable(Symbol),
        code_challenge: T.nilable(String),
      ).returns(GH::Result[CreateResult]).checked(:always).on_failure(:raise)
    end
    def grant(user:, application:, scope: nil, requested_scope: nil, integration_version_number: nil, user_session: nil, redirect_uri: nil, entry_point: nil, code_challenge: nil)
      if FeatureFlag.vexi.enabled?(:oauth_domain_grant_orchestration, user, default: false)
        # New path: create OauthAccess with callback bypass active.
        # The orchestrator handles Steps 1-5 (authorization creation, version
        # reconciliation, permission updates, stale-access pruning) explicitly.
        access = application.accesses.build(user: user)
        access.delegate_to_domain_interface!
        access.grant(scope, requested_scope, integration_version_number, redirect_uri, entry_point, code_challenge)
        GH::Result::Ok.new(CreateResult.new(access, access.code))
      else
        # Existing path: Provider#grant handles everything including callbacks
        options = {
          scope: scope,
          requested_scope: requested_scope,
          integration_version_number: integration_version_number,
          user_session: user_session,
          redirect_uri: redirect_uri,
          entry_point: entry_point,
          code_challenge: code_challenge,
        }.compact

        access = application.grant(user, options)
        GH::Result::Ok.new(CreateResult.new(access, access.code))
      end
    rescue ActiveRecord::RecordInvalid => e
      GH::Result::Error::Unprocessable.new([e.record], message: e.message)
    rescue ActiveRecord::RecordNotUnique
      GH::Result::Error.new("An access already exists for this user and application.")
    end

    # Public: Exchanges an authorization code for an access token.
    # Wraps OauthAccess#redeem which generates the actual token (and optionally
    # a refresh token for refreshable apps like Integrations).
    #
    # @param access_id [Integer] The ID of the OauthAccess to redeem
    # @param extended_expiry [Boolean] Whether to use extended token expiry
    # @return [GH::Result[T.untyped]] token string (non-refreshable) or
    #   [token, refresh_token] array (refreshable) on success
    # @return [GH::Result::Error::NotFound] if access_id not found
    sig do
      params(
        access_id: Integer,
        extended_expiry: T::Boolean,
      ).returns(GH::Result[T.untyped]).checked(:always).on_failure(:raise)
    end
    def redeem(access_id:, extended_expiry: false)
      access = OauthAccess.find_by(id: access_id)
      return GH::Result::Error::NotFound.new if access.nil?

      begin
        result = access.redeem(extended_expiry: extended_expiry)
        GH::Result::Ok.new(result)
      rescue ActiveRecord::RecordInvalid => e
        GH::Result::Error::Unprocessable.new([e.record], message: e.message)
      rescue ActiveRecord::RecordNotUnique
        GH::Result::Error.new("Token collision during redeem. Please retry.")
      end
    end

    # Public: Pre-resolve integration version metadata for the domain.grant
    # orchestrator. Constructs a VersionContext hash containing current, target,
    # and latest version value objects that can be passed to version
    # reconciliation (Step 3) and permission updates (Step 4) without
    # cross-domain queries inside the authorization transaction.
    #
    # Returns an empty hash for OauthApplication-type applications (which
    # don't have integration versions).
    #
    # @param user [User] The user granting access
    # @param application [T.any(Integration, OauthApplication)] The application
    # @param target_version_number [Integer, nil] The requested version number (Integer, nil if unset)
    # @return [Hash] A hash with :current_version, :target_version, :latest_version
    #   keys, each containing an OauthAuthorization::VersionContext, or empty hash
    sig do
      params(
        user: User,
        application: T.any(Integration, OauthApplication),
        target_version_number: T.nilable(Integer),
      ).returns(T::Hash[Symbol, OauthAuthorization::VersionContext]).checked(:always).on_failure(:raise)
    end
    def build_integration_version_context(user:, application:, target_version_number: nil)
      return {} unless application.is_a?(Integration)

      latest = application.latest_version
      return {} if latest.nil?

      target = application.versions.find_by(number: target_version_number) || latest

      current_oauth_authorization = user.oauth_authorizations.where(
        application_id: application.id,
        application_type: application.class.base_class.name,
      ).first

      current =
        if current_oauth_authorization.present?
          application.versions.find_by(number: current_oauth_authorization.integration_version_number) || latest
        else
          target
        end

      {
        current_version: OauthAuthorization::VersionContext.new(
          default_content_references: current.default_content_references,
          default_events: current.default_events,
          default_permissions: current.default_permissions,
          number: current.number,
          single_file_paths: current.single_file_paths,
          user_permissions: current.user_permissions,
        ),
        target_version: OauthAuthorization::VersionContext.new(
          default_content_references: target.default_content_references,
          default_events: target.default_events,
          default_permissions: target.default_permissions,
          number: target.number,
          single_file_paths: target.single_file_paths,
          user_permissions: target.user_permissions,
        ),
        latest_version: OauthAuthorization::VersionContext.new(
          default_content_references: latest.default_content_references,
          default_events: latest.default_events,
          default_permissions: latest.default_permissions,
          number: latest.number,
          single_file_paths: latest.single_file_paths,
          user_permissions: latest.user_permissions,
        ),
      }
    end

    # Create a new OAuth access token by application_id and application_type.
    # Use this when you don't have a reference to the OauthApplication object directly
    # (e.g. callers in lib/ that cannot reference OauthApplication due to packwerk).
    #
    # @param user_id [Integer] The ID of the user who owns the token
    # @param application_id [Integer] The ID of the application
    # @param data [Hash] A hash of parameters to create the token from
    # @option data ["scopes"] [Array<String>] The scopes to assign to the token
    # @return [GH::Result[CreateResult]] A result containing the created token or an error
    # @return [GH::Result::Error] if the token is invalid or cannot be saved
    sig do
      params(
        user_id: Integer,
        application_id: Integer,
        data: T::Hash[String, T.untyped]
      ).returns(GH::Result[CreateResult]).checked(:always).on_failure(:raise)
    end
    def create_for_application_id(user_id, application_id, data)
      application = OauthApplication.find(application_id)
      create(user_id, application, data)
    end

    # Create a new personal OAuth access token
    sig { params(user_id: Integer, description: T.nilable(String), scopes: T.untyped, default_expires: T.nilable(String), custom_expires: T.nilable(String), allow_custom_default_expires_at: T.untyped).returns(GH::Result[CreateResult]).checked(:always).on_failure(:raise) }
    def create_personal(user_id, description, scopes, default_expires, custom_expires, allow_custom_default_expires_at)
      access = OauthAccess.new(
        user_id: user_id,
        application_id: OauthApplication::PERSONAL_TOKENS_APPLICATION_ID,
        application_type: OauthApplication::PERSONAL_TOKENS_APPLICATION_TYPE,
        description: description,
        scopes: scopes,
      )

      access.set_expiration(
        default_expires,
        custom_expires,
        allow_custom_default_expires_at: allow_custom_default_expires_at
      )
      return GH::Result::Error::Unprocessable.new([access], message: access.errors.full_messages.to_sentence) if access.errors.any?

      token = access.set_random_token_pair
      # Build instance before saving it so we track the GTID properly
      # of the save operation.
      last_operations = DatabaseSelector::LastOperations.from_token(token)

      if !(access.valid? && access.save)
        GH::Result::Error::Unprocessable.new([access], message: access.errors.full_messages.to_sentence)
      else
        # After saving the new token we want to set the last write gtids/timestamps in
        # the cache, so the api DatabaseSelection can use the write DB for newly
        # created tokens and avoid issues due to replication lag.
        last_operations.store_latest_writes
        GH::Result::Ok.new(CreateResult.new(access, token))
      end
    end

    # Update an OAuth access token's properties
    #
    # @param token_id [Integer] The ID of the token to update
    # @param user_id [Integer] The user ID who owns the token
    # @param data [Hash] A hash of parameters to update from the API request
    # @option data ["scopes"] [Array<String>, nil] Replace scopes with these values, if nil does nothing, if empty clears all scopes
    # @option data ["add_scopes"] [Array<String>, nil] Add these scopes to existing ones
    # @option data ["remove_scopes"] [Array<String>, nil] Remove these scopes from existing ones
    # @option data ["note_url"] [String, nil] Update the note URL
    # @option data ["note"] [String, nil] Update the description/note
    # @option data ["fingerprint"] [String, nil] Update the fingerprint
    # @return [GH::Result[IOauthAccess]] A result containing the updated token or an error
    sig { params(token_id: Integer, user_id: Integer, data: T::Hash[String, T.untyped]).returns(GH::Result[IOauthAccess]).checked(:always).on_failure(:raise) }
    def update(token_id, user_id, data)
      access = OauthAccess.find_by(id: token_id, user_id: user_id)
      return GH::Result::Error::NotFound.new unless access

      if data.key?("scopes") && data["scopes"].is_a?(Array)
        access.scopes = data["scopes"]
      elsif (scopes = Array(data["scopes"])).present?
        access.scopes = scopes
      elsif (scopes = Array(data["add_scopes"])).present?
        access.scopes |= scopes
      elsif (scopes = Array(data["remove_scopes"])).present?
        access.scopes -= scopes
      end

      # Update other fields if they are present in the data
      access.code = nil # Older tokens will have a code set that is not needed
      access.note_url = data["note_url"] if data.key?("note_url")
      access.description = data["note"] if data.key?("note")
      access.fingerprint = data["fingerprint"] if data.key?("fingerprint")

      if access.save
        GH::Result::Ok.new(access)
      else
        GH::Result::Error.new(access.errors.full_messages.join(", "))
      end
    end

    # Set scopes for an access_token by its id
    sig { params(token_id: Integer, scopes: T::Array[String]).returns(GH::Result[CreateResult]).checked(:always).on_failure(:raise) }
    def set_scopes(token_id, scopes)
      if FeatureFlag.vexi.enabled?(:use_oauth_helper_methods, default: false)
        access = T.cast(by_id(token_id), T.nilable(OauthAccess))
      else
        access = OauthAccess.find_by(id: token_id)
      end

      return GH::Result::Error::NotFound.new unless access
      access.set_scopes(scopes)
      GH::Result::Ok.new(CreateResult.new(access, access.reset_token))
    end

    # delete an access_token by user and app id
    sig { params(user_id: Integer, application_id: Integer, application_type: String).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def delete_by_user_and_application(user_id, application_id, application_type)
      access = OauthAccess.find_by(user_id: user_id, application_id: application_id, application_type: application_type)
      return GH::Result::Error::NotFound.new unless access
      access.delete
      GH::Result::Ok.new(true)
    end

    # destroy an access_token without explaination
    sig { params(user_id: Integer).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def destroy_existing_codeql_action_token(user_id)
      application_id = OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
      application_type = OauthApplication::PERSONAL_TOKENS_APPLICATION_TYPE
      description = "CodeQL Action Repository Seeding"

      access = OauthAccess.where(user_id: user_id, application_id: application_id, application_type: application_type, description: description).first
      return GH::Result::Error::NotFound.new unless access
      access.destroy
      GH::Result::Ok.new(true)
    end

    # destroy an access_token by its id
    sig { params(token_id: Integer, reason: Symbol, entry_point: T.nilable(Symbol), skip_destroy_authorization: T::Boolean).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def destroy(token_id, reason, entry_point:, skip_destroy_authorization: false)
      if FeatureFlag.vexi.enabled?(:use_oauth_helper_methods, default: false)
        access = T.cast(by_id(token_id), T.nilable(OauthAccess))
      else
        access = OauthAccess.find_by(id: token_id)
      end

      return GH::Result::Error::NotFound.new unless access
      access.destroy_with_explanation(reason, entry_point: entry_point)
      GH::Result::Ok.new(true)
    end

    # destroy access_tokens by list of ids
    sig { params(token_ids: T::Array[Integer], reason: Symbol, entry_point: T.nilable(Symbol), skip_destroy_authorization: T::Boolean).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def destroy_by_ids(token_ids, reason, entry_point:, skip_destroy_authorization: false)
      # We want to destroy each one individually so that we get
      # the proper audit logging for security.
      if FeatureFlag.vexi.enabled?(:use_oauth_helper_methods, default: false)
        accesses = T.cast(by_ids(token_ids), T::Array[OauthAccess])
      else
        accesses = OauthAccess.where(id: token_ids)
      end
      OauthAccess.with_write do
        OauthAccess.throttle_with_retry(max_retry_count: 8) do
          accesses.map do |access|
            access.destroy_with_explanation(reason, entry_point: entry_point, skip_destroy_authorization: skip_destroy_authorization)
          end
        end
      end
      GH::Result::Ok.new(true)
    end

    # Destroy all OAuth access tokens for a user.
    # Each token is destroyed individually so that the proper audit logging is preserved.
    #
    # @param user_id [Integer] The ID of the user whose tokens to destroy
    # @param reason [Symbol] The reason for destruction
    # @param entry_point [Symbol, nil] The entry point triggering the destruction
    # @return [GH::Result<Boolean>] A result indicating success
    sig { params(user_id: Integer, reason: Symbol, entry_point: T.nilable(Symbol)).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def destroy_all_for_user(user_id, reason, entry_point:)
      destroy_for_user = T.let(-> do
        OauthAccess.where(user_id: user_id).find_each do |access|
          access.destroy_with_explanation(reason, entry_point: entry_point)
        end
      end, T.proc.void)

      OauthAccess.with_write do
        if open_transactions_for_throttling?
          destroy_for_user.call
        else
          OauthAccess.throttle_with_retry(max_retry_count: 8, &destroy_for_user)
        end
      end
      GH::Result::Ok.new(true)
    end

    # Batch-updates last_issued_at for OauthAccess records with the given IDs,
    # only where last_issued_at is currently nil.
    sig { params(ids: T::Array[Integer], time: Time).void.checked(:always).on_failure(:raise) }
    def update_last_issued_at(ids, time)
      OauthAccess.with_write do
        OauthAccess.where(id: ids, last_issued_at: nil).update_all(last_issued_at: time)
      end
    end

    # Set the expiration date for an OAuth access token
    sig { params(token_id: Integer, expires_at: Time).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def set_expiration(token_id, expires_at)
      if FeatureFlag.vexi.enabled?(:use_oauth_helper_methods, default: false)
        access = T.cast(by_id(token_id), T.nilable(OauthAccess))
      else
        access = OauthAccess.find_by(id: token_id)
      end

      return GH::Result::Error::NotFound.new unless access
      access.expires_at = expires_at
      access.save!
      GH::Result::Ok.new(true)
    end

    # Revoking a list of tokens by their hashes
    # Destroying tokens deletes the tokens from the db and removes them from the UI
    # Revoking tokens sets the expired_at timestamp to now, but you are still able to see them in the UI
    sig { params(token_hashes: T::Array[String], reason: Symbol).returns(T::Array[GH::Result[IOauthAccess]]).checked(:always).on_failure(:raise) }
    def revoke_by_hashes(token_hashes, reason)
      # We want to revoke each one individually so that we get
      # the proper audit logging for security.
      accesses = OauthAccess.where(hashed_token: token_hashes)
      return [GH::Result::Error::NotFound.new] if accesses.empty?

      result = []
      OauthAccess.with_write do
        OauthAccess.throttle_with_retry(max_retry_count: 8) do
          accesses.each do |access|
            if GitHub.multi_tenant_enterprise? && access.user.nil?
              result << GH::Result::Error::Validation.new(access, message: "token_does_not_belong_in_tenant")
              next
            elsif access.expired?
              result << GH::Result::Error::Validation.new(access, message: "token_already_expired")
              next
            end
            access.revoke_personal_access_token!(reason: reason)
            result << GH::Result::Ok.new(access)
          end
        end
      end
      result
    end

    # Regenerate an OAuth access token with expiration settings
    #
    # @param token_id [Integer] The ID of the token to regenerate
    # @param default_expires_at [String, nil] The default expiration setting (e.g., "none", "custom")
    # @param custom_expires_at [String, nil] The custom expiration date if using custom expiration
    # @param allow_custom_default_expires_at [Boolean] Whether to allow custom default expiration
    # @return [GH::Result<[IOauthAccess, String]>] A result containing the updated token record and the new token value, or an error
    sig { params(token_id: Integer, default_expires_at: T.nilable(String), custom_expires_at: T.nilable(String), allow_custom_default_expires_at: T.untyped).returns(GH::Result[T::Array[T.untyped]]).checked(:always).on_failure(:raise) }
    def regenerate_with_expiry(token_id, default_expires_at, custom_expires_at, allow_custom_default_expires_at)
      if FeatureFlag.vexi.enabled?(:use_oauth_helper_methods, default: false)
        access = T.cast(by_id(token_id), T.nilable(OauthAccess))
      else
        access = OauthAccess.find_by(id: token_id)
      end

      return GH::Result::Error::NotFound.new unless access

      # Clear code as we're regenerating the token
      access.code = nil

      # Set expiration based on parameters
      access.set_expiration(
        default_expires_at,
        custom_expires_at,
        allow_custom_default_expires_at: allow_custom_default_expires_at
      )

      return GH::Result::Error::Unprocessable.new([access], message: access.errors.full_messages.to_sentence) if access.errors.any?

      begin
        token = access.reset_with_expiry(expires_at: access.expires_at)
        GH::Result::Ok.new([access, token])
      rescue ActiveRecord::RecordInvalid => e
        # Context:
        #   - https://github.com/github/ecosystem-apps/issues/988
        #   - https://github.com/github/ecosystem-apps/issues/2469
        raise e unless user_facing_error?(access)
        message = if access.errors.any?
          access.errors.full_messages.to_sentence
        else
          e.message
        end

        GH::Result::Error::Unprocessable.new([access], message: message)
      end
    end

    # Find a user's tokens created before a specific date
    #
    # @param user_id [Integer] The ID of the user whose tokens to find
    # @param date [Time] The date before which tokens were created
    # @param batch_size [Integer] Size of batches to return
    # @return [ActiveRecord::Batches::BatchEnumerator] An enumerable of batches of tokens
    sig { params(user_id: Integer, date: Time, batch_size: Integer).returns(T.untyped).checked(:always).on_failure(:raise) }
    def tokens_created_before(user_id, date, batch_size: 100)
      OauthAccess.where(user_id: user_id).where("created_at < ?", date).find_in_batches(batch_size: batch_size).to_a
    end

    # Finds valid installation IDs associated with a user and installation type
    # that haven't expired (expires_at_timestamp > current time)
    #
    # @param user [Users::IUser] The user to find installations for
    # @param installation_type [String] The type of installation to find
    # @return [Array<Integer>] Array of valid installation IDs
    sig { params(user_id: Integer, installation_type: String).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def valid_installation_ids_by_user_and_type(user_id, installation_type)
      OauthAccess
        .where(user: user_id, installation_type: installation_type)
        .where("expires_at_timestamp > ?", Time.now.to_i)
        .distinct
        .pluck(:installation_id)
    end

    # Executes the given block in a write database context.
    # Use this when performing write operations on OauthAccess records
    # or related records that must target the primary database.
    sig do
      type_parameters(:U)
        .params(blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def with_write(&blk)
      OauthAccess.with_write(&blk)
    end

    # Authenticates a oauth access token with the token_result format needed for the GitHub::Authentication::Attempt try_auth -> try_access_token_auth flow
    sig { params(token: String, auth_options: T.untyped).returns(GitHub::Authentication::Result).checked(:always).on_failure(:raise) }
    def token_authenticate(token, auth_options)
      enable_experiment = !auth_options&.delete(:disable_experiments)
      if enable_experiment && FeatureFlag.vexi.enabled?(:authnd_experiment_access_token, default: false)
        try_oauth_access_token_auth_experiment(token, auth_options)
      else
        GitHub.auth.access_token_authenticate(token, **auth_options)
      end
    end

    # Public: Issues a stateless user-to-server token via authnd.
    #
    # actor_id                - The Integer user ID (uid claim).
    # authorization_id        - The Integer OauthAuthorization ID for the user+app pair.
    # scoped_installation_id  - The Integer ScopedIntegrationInstallation ID passed to authnd as
    #                           authorization context.
    # integration             - The Integration instance (GitHub App). Its ID is used as the aid claim.
    # expires_at              - The Time at which the token should expire.
    #
    # Returns a GH::Result that wraps a StatelessTokenResult on success or wraps an error message on failure.
    sig do
      params(
        actor_id: Integer,
        authorization_id: Integer,
        scoped_installation_id: Integer,
        integration: Integration,
        expires_at: Time,
      ).returns(GH::Result[StatelessTokenResult])
    end
    def create_stateless_u2s_token(actor_id:, authorization_id:, scoped_installation_id:, integration:, expires_at:)
      GitHub.tracer.in_span("OauthAccessTokens::Domain#u2s_stateless_token_authnd_creation",
        kind: :internal,
      ) do |span|
        span.add_attributes({
          "gh.oauth_access.id" => authorization_id.to_s,
          "gh.integration.id" => integration.id.to_s,
          "gh.user.id" => actor_id.to_s,
        })

        authorization_context = T.unsafe(Authnd::Proto::AuthorizationContext).new(
          scoped_installation: T.unsafe(Authnd::Proto::AuthorizationContext::ScopedInstallation).new(id: scoped_installation_id),
        )

        response = credential_manager.issue_stateless_app_token(
          :TOKEN_TYPE_U2S,
          {
            "actor.id" => actor_id,
            "actor.type" => "user",
            "application.id" => integration.id,
            "application.type" => "integration",
            "authorization.id" => authorization_id,
          },
          authorization_context: authorization_context,
          expires_at: expires_at,
        )

        if response.success?
          stateless_token_result = StatelessTokenResult.new(response.token, token_id: response.token_id,
            credential_id: response.credential_id)
          next GH::Result::Ok.new(stateless_token_result)
        end

        GH::Result::Error.new(response.error)
      end
    rescue ::Authnd::Proto::Error, Faraday::Error => err
      Failbot.report!(err)
      GH::Result::Error.new(err.message)
    end

    # Public: Revokes a stateless user-to-server token via authnd.
    #
    # Reuses the RevokeStatelessAppToken RPC already in production for stateless S2S tokens — the endpoint accepts any
    # stateless app token regardless of token type. See https://github.com/github/authentication/issues/6308.
    #
    # token  - The stateless U2S token String to revoke.
    # reason - String reason for the revocation, recorded by authnd.
    #
    # Returns a GH::Result wrapping true on success, or an error message on failure.
    sig { params(token: String, reason: String).returns(GH::Result[T::Boolean]) }
    def revoke_stateless_u2s_token(token, reason:)
      GitHub.tracer.in_span("OauthAccessTokens::Domain#u2s_stateless_token_authnd_revocation", kind: :internal) do
        response = credential_manager.revoke_stateless_app_token(token, reason: reason)
        next GH::Result::Ok.new(true) if response.success?

        GH::Result::Error.new(response.message)
      end
    rescue ::Authnd::Proto::Error, Faraday::Error => err
      Failbot.report!(err)
      GH::Result::Error.new(err.message)
    end

    # Returns whether stateless user-to-server token issuance is enabled for the given repository.
    sig do
      params(
        actors: T.any(Vexi::Actor, String, T::Array[T.nilable(T.any(Vexi::Actor, String))])
      ).returns(T::Boolean)
    end
    def stateless_u2s_tokens_enabled?(*actors)
      T.unsafe(FeatureFlag).vexi.enabled?(:user_to_server_authnd_stateless_tokens, *actors.flatten.compact,
        default: false)
    end

    private

    sig { params(calling_service: String).returns(::Authnd::Client::CredentialManager) }
    def credential_manager(calling_service: "github/oauth")
      ::GitHub::Authnd.credential_manager(calling_service)
    end

    sig { params(token: String, access_token_auth_options: T.untyped).returns(GitHub::Authentication::Result) }
    def try_oauth_access_token_auth_experiment(token, access_token_auth_options)
      e = GitHub::Authnd::Experiment::new "authnd.attempt.try_access_token_auth"

      e.use { GitHub.auth.access_token_authenticate(token, **access_token_auth_options) }
      e.try { GitHub.auth.access_token_authenticate_authnd(token, **access_token_auth_options) }

      e.compare do |control, candidate|
        e.compare_oauth_access_token_experiment_result(control, candidate)
      end

      e.clean do |value|
        e.clean_oauth_access_token_experiment_result(value)
      end

      e.ignore do |control, candidate|
        e.ignore_oauth_access_token_experiment(token, control, candidate)
      end

      e.run
    end

    # Helper method to determine if errors are user-facing
    sig { params(access: OauthAccess).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def user_facing_error?(access)
      has_error?(access, :note, [:github_token_prefix, :taken]) || has_error?(access, :base, [:invalid_expiration])
    end

    # Throttling while a transaction is open is ineffective and can significantly
    # increase transaction duration.
    sig { returns(T::Boolean) }
    def open_transactions_for_throttling?
      OauthAccess.connection.open_transactions.positive?
    end

    # Helper method to check for specific errors
    sig { params(access: OauthAccess, field: Symbol, errors: T::Array[Symbol]).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def has_error?(access, field, errors = [])
      access.errors.details[field].any? { |e| errors.include?(e[:error]) }
    end
  end
end
