# typed: strict
# frozen_string_literal: true

module OauthAccessTokens
  class Domain < GH::Domain::Base

    # Require token to be a 40 hex character string
    TOKEN_LEGACY_PATTERN = /\A[a-f0-9]{40}\z/

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

    # Finds an OauthAccess by its id
    sig { params(id: T.nilable(Integer), strict: T::Boolean).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise)  }
    def by_id(id, strict: false)
      strict ? OauthAccess.find(T.must(id)) : OauthAccess.find_by(id: id)
    end

    # Finds OauthAccesses by ids
    sig { params(ids: T::Array[T.nilable(Integer)]).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise)  }
    def by_ids(ids)
      OauthAccess.where(id: ids).to_a
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

    # Finds personal token count for a user
    sig { params(actor_id: Integer).returns(T::Array[IOauthAccess]).checked(:always).on_failure(:raise) }
    def personal_tokens(actor_id)
      OauthAccess.where(user_id: actor_id).personal_tokens.to_a
    end

    # Finds third party token count for a user
    sig { params(actor_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def third_party_tokens_count(actor_id)
      OauthAccess.where(user_id: actor_id).third_party.size
    end

    # Filters installation_ids by those with OauthAccess records
    sig { params(installation_ids: T::Array[Integer], actor_type: String).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def installation_ids_with_accesses(installation_ids, actor_type)
      OauthAccess.where(installation_id: installation_ids, installation_type: actor_type).pluck(:installation_id)
    end

    # Finds a user's OauthAccess by id
    sig { params(user_id: Integer, id: Integer, strict: T::Boolean).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise)  }
    def user_access_by_id(user_id, id, strict: false)
      access = OauthAccess.find_by(user_id: user_id, id: id)
      raise ActiveRecord::RecordNotFound if strict && access.nil?

      access
    end

    # Finds a user's by application & fingerprint
    sig { params(user_id: Integer, application_id: Integer, fingerprint: T.nilable(String)).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise)  }
    def user_access_by_app_and_fingerprint(user_id, application_id, fingerprint)
      OauthAccess.find_by(user_id: user_id, application_id: application_id, fingerprint: fingerprint)
    end

    # Finds a user's by user & hash
    sig { params(user_id: Integer, hash: String).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise)  }
    def user_access_by_hash(user_id, hash)
      OauthAccess.find_by(user_id: user_id, hashed_token: hash)
    end

    # Finds a user's personal OauthAccess token by id
    sig { params(user_id: Integer, id: Integer).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise)  }
    def personal_token_by_id(user_id, id)
      OauthAccess.where(user_id: user_id).personal_tokens.find_by(id: id)
    end

    # Finds a user's personal OauthAccess token by id and fingerprint
    sig { params(user_id: Integer, id: Integer, fingerprint: T.nilable(String)).returns(T.nilable(IOauthAccess)).checked(:always).on_failure(:raise)  }
    def personal_token_by_id_and_fingerprint(user_id, id, fingerprint)
      OauthAccess.where(user_id: user_id).personal_tokens.find_by(id: id, fingerprint: fingerprint)
    end
  end
end
