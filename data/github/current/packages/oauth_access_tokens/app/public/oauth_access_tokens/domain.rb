# typed: strict
# frozen_string_literal: true

module OauthAccessTokens
  class Domain < GH::Domain::Base
    class CreateResult
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
      strict ? OauthAccess.find(T.must(id)) : OauthAccess.find_by(id: id)
    end

    # Finds OauthAccesses by ids
    sig { params(ids: T::Array[T.nilable(Integer)]).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def by_ids(ids)
      OauthAccess.where(id: ids).to_a
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

    # Finds personal OauthAccess ids by user
    sig { params(actor_id: Integer).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def personal_token_ids(actor_id)
      OauthAccess.where(user_id: actor_id).personal_tokens.ids
    end

    # Finds personal token count for a user
    sig { params(actor_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def personal_tokens_count(actor_id)
      OauthAccess.where(user_id: actor_id).personal_tokens.size
    end

    # Finds personal tokens for a user
    sig { params(actor_id: Integer).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def personal_tokens(actor_id)
      OauthAccess.where(user_id: actor_id).personal_tokens.to_a
    end

    # Finds third party token count for a user
    sig { params(actor_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def third_party_tokens_count(actor_id)
      OauthAccess.where(user_id: actor_id).third_party.size
    end

    # Finds third party tokens for a user
    sig { params(actor_id: Integer).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def third_party_tokens(actor_id)
      OauthAccess.where(user_id: actor_id).third_party.to_a
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
      access = OauthAccess.find_by(id: token_id)
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
      accesses = OauthAccess.where(id: refreshable_ids).to_a

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
      access = OauthAccess.find_by(id: token_id)
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
      access = OauthAccess.find_by(id: token_id)
      return GH::Result::Error::NotFound.new unless access
      access.destroy_with_explanation(reason, entry_point: entry_point)
      GH::Result::Ok.new(true)
    end

    # destroy access_tokens by list of ids
    sig { params(token_ids: T::Array[Integer], reason: Symbol, entry_point: T.nilable(Symbol), skip_destroy_authorization: T::Boolean).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def destroy_by_ids(token_ids, reason, entry_point:, skip_destroy_authorization: false)
      # We want to destroy each one individually so that we get
      # the proper audit logging for security.
      accesses = OauthAccess.where(id: token_ids)
      OauthAccess.with_write do
        OauthAccess.throttle_with_retry(max_retry_count: 8) do
          accesses.map do |access|
            access.destroy_with_explanation(reason, entry_point: entry_point, skip_destroy_authorization: skip_destroy_authorization)
          end
        end
      end
      GH::Result::Ok.new(true)
    end

    # Set the expiration date for an OAuth access token
    sig { params(token_id: Integer, expires_at: Time).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def set_expiration(token_id, expires_at)
      access = OauthAccess.find_by(id: token_id)
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
      access = OauthAccess.find_by(id: token_id)
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

    # Authenticates a oauth access token with the token_result format needed for the GitHub::Authentication::Attempt try_auth -> try_access_token_auth flow
    sig { params(token: String, auth_options: T.untyped).returns(GitHub::Authentication::Result).checked(:always).on_failure(:raise) }
    def token_authenticate(token, auth_options)
      enable_experiment = !auth_options&.delete(:disable_experiments)
      if enable_experiment && GitHub.flipper[:authnd_experiment_access_token].enabled?
        try_oauth_access_token_auth_experiment(token, auth_options)
      else
        GitHub.auth.access_token_authenticate(token, **auth_options)
      end
    end

    private

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

    # Helper method to check for specific errors
    sig { params(access: OauthAccess, field: Symbol, errors: T::Array[Symbol]).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def has_error?(access, field, errors = [])
      access.errors.details[field].any? { |e| errors.include?(e[:error]) }
    end
  end
end
