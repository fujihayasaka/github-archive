# typed: strict
# frozen_string_literal: true

module ServerToServerTokens
  class Domain < GH::Domain::Base
    class CreateResult
      sig { returns(IAuthenticationToken) }
      attr_reader :token_record

      sig { returns(String) }
      attr_reader :token_value

      # initialize the CreateResult
      sig { params(token_record: IAuthenticationToken, token_value: String).void }
      def initialize(token_record, token_value)
        @token_record = T.let(token_record, IAuthenticationToken)
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

    DESTROY_LOOKUP_BATCH_SIZE = 100
    MAX_THROTTLE_RETRIES = 5

    ACCESS_TOKEN_PREFIX = "ghs_"

    # Public: The Regexp describing the format of an AuthenticationToken's string
    # token value.
    TOKEN_PATTERN_GS1 = %r{
      \A                              # start
      #{ACCESS_TOKEN_PREFIX}     # the token format prefix
      [a-zA-Z0-9]{36}                 # the random portion and checksum
      \z                              # end
    }xi

    # legacy pattern
    TOKEN_PATTERN_V1 = %r{
      \A                 # start
      v1                 # the token format version
      \.                 # a period
      [a-f0-9]{40}       # the random portion of the token
      \z                 # end
    }xi

    # Checks if the given token matches the AuthenticationToken pattern
    #
    # token - The string to check
    #
    # Returns true if token follows the AuthenticationToken pattern,
    #   false if it doesn't
    sig { params(token: T.nilable(String)).returns(T::Boolean) }
    def self.matches_pattern?(token)
      !!(token =~ TOKEN_PATTERN_V1 ||
        token =~ TOKEN_PATTERN_GS1)
    end

    # Hash token for server side persistence.
    sig { params(token: T.nilable(String)).returns(String) }
    def self.hash_token(token)
      ::AuthenticationToken.hash_token(token)
    end

    # finds an Authentication Token by its unhashed token value while manually forcing a read-only connection
    sig { params(token: String).returns(T.nilable(IAuthenticationToken)).checked(:always).on_failure(:raise) }
    def by_unhashed_token_ro(token)
      ActiveRecord::Base.connected_to(role: :reading) do
        by_unhashed_token(token)
      end
    end

    # finds an Authentication Token by its unhashed token value
    sig { params(token: String).returns(T.nilable(IAuthenticationToken)).checked(:always).on_failure(:raise) }
    def by_unhashed_token(token)
      ::AuthenticationToken.active.with_unhashed_token(token).first
    end

    # finds an Authentication Token by its hashed token value
    sig { params(token: String).returns(T.nilable(IAuthenticationToken)).checked(:always).on_failure(:raise) }
    def by_hashed_token(token)
      ::AuthenticationToken.find_by(hashed_value: token)
    end

    # finds Authentication Tokens by their hashed token values
    sig { params(hashed_tokens: T::Array[String], batch_size: Integer).returns(T::Hash[String, IAuthenticationToken]).checked(:always).on_failure(:raise) }
    def by_hashed_values(hashed_tokens, batch_size)
      accesses = T.let({}, T::Hash[String, IAuthenticationToken])

      hashed_tokens.each_slice(batch_size) do |slice|
        slice_accesses = AuthenticationToken.where(hashed_value: slice)
          .in_batches(of: batch_size)
          .each_record
          .index_by(&:hashed_value)

        accesses.merge!(slice_accesses)
      end
      accesses
    end

    # finds an Authentication Token by its id
    sig { params(id: Integer).returns(T.nilable(IAuthenticationToken)).checked(:always).on_failure(:raise) }
    def by_id(id)
      ::AuthenticationToken.find_by(id: id)
    end

    # finds one authentication tokens by the owning authenticatable id
    sig { params(authenticatable_id: Integer).returns(T.nilable(IAuthenticationToken)).checked(:always).on_failure(:raise) }
    def first_by_authenticatable_id(authenticatable_id)
      AuthenticationToken.where(authenticatable_id: authenticatable_id).active.first
    end

    # finds authentication tokens by the owning authenticatable id
    sig { params(authenticatable_id: Integer).returns(T::Array[IAuthenticationToken]).checked(:always).on_failure(:raise) }
    def by_authenticatable_id(authenticatable_id)
      AuthenticationToken.where(authenticatable_id: authenticatable_id).active.to_a
    end

    # counts the number of authentication tokens by the owning authenticatable id
    sig { params(authenticatable_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def count_by_authenticatable_id(authenticatable_id)
      total_records = AuthenticationToken.where(authenticatable_id: authenticatable_id).count
    end

    # finds Authenticatable ids that have active authentication tokens
    sig { params(authenticatable_ids: T::Array[Integer], authenticatable_type: String).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def authenticatable_ids_with_active_tokens(authenticatable_ids, authenticatable_type)
      AuthenticationToken.where(
        authenticatable_id: authenticatable_ids, authenticatable_type: authenticatable_type
      ).active.pluck(:authenticatable_id)
    end

    # update an Authentication Token's expires_at
    sig { params(token_id: Integer, expires_at: T.nilable(String), entry_point: T.nilable(Symbol)).returns(GH::Result[IAuthenticationToken]).checked(:always).on_failure(:raise) }
    def extend_expires_at(token_id, expires_at, entry_point: nil)
      record = ::AuthenticationToken.find_by(id: token_id)
      return GH::Result::Error::NotFound.new unless record
      result = AuthenticationToken.extend_expires_at(record, expires_at, entry_point: entry_point)
      return GH::Result::Ok.new(record) if result.success?
      GH::Result::Error.new(result.message)
    end

    # destroy an Authentication Token by its id
    sig { params(token_id: Integer).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def destroy(token_id)
      record = ::AuthenticationToken.find_by(id: token_id)
      return GH::Result::Error::NotFound.new unless record
      record.destroy
      GH::Result::Ok.new(true)
    end

    # delete all AuthenticationTokens associated with the authenticatable_id
    sig { params(authenticatable_id: Integer).returns(GH::Result[Integer]).checked(:always).on_failure(:raise) }
    def destroy_by_authenticatable_id(authenticatable_id)
      deleted_count = 0
      AuthenticationToken.with_read do
        AuthenticationToken.where(authenticatable_id: authenticatable_id).in_batches(of: DESTROY_LOOKUP_BATCH_SIZE) do |batch|
          AuthenticationToken.with_write do
            AuthenticationToken.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              batch.each do |record|
                if record.destroy
                  deleted_count += 1
                else
                  GitHub.logger.warn(
                    "Dependent record failed to be destroyed", {
                      "code.namespace" => "ServerToServerTokens::Domain", "code.function" => "destroy_by_authenticatable_id",
                      "table_model" => record.class.name, "table_model_id" => record.id, "parent_model_id" => authenticatable_id,
                      "error" => record.errors.full_messages.join(","),
                    }
                  )
                end
              end
            end
          end
        end
      end
      GH::Result::Ok.new(deleted_count)
    end

    # create a new Authentication Token
    sig do params(authenticatable_id: Integer, authenticatable_type: String, span_attributes: T::Hash[String, String], code_path: T.nilable(String))
      .returns(GH::Result[CreateResult]).checked(:always).on_failure(:raise)
    end
    def create(authenticatable_id, authenticatable_type, span_attributes, code_path: nil)
      record, token = AuthenticationToken.create_for(authenticatable_id, authenticatable_type, span_attributes, code_path: code_path)
      GH::Result::Ok.new(CreateResult.new(record, token))
    rescue ActiveRecord::RecordInvalid, NameError => e
      GH::Result::Error.new(e.message)
    end

    # Authenticates a server to server token (using authnd's authenticate API)
    #
    # This method should be used when you know that the access token is a ServerToServerToken
    # but there is no difference in the underlying authenticate call when you don't know which type of access token you have
    sig { params(calling_service: String, token: String).returns(::Authnd::Response).checked(:always).on_failure(:raise) }
    def authenticate(calling_service, token)
      ::ServerToServerToken::Authenticator.perform(calling_service, token)
    end
  end
end
