# typed: strict
# frozen_string_literal: true

module Storage
  class JwtSign

    DEFAULT_EXPIRATION_TIME = T.let(5.minutes, ActiveSupport::Duration)
    MEDIUM_FILE_EXPIRATION_TIME = T.let(30.minutes, ActiveSupport::Duration)
    LARGE_FILE_EXPIRATION_TIME = T.let(60.minutes, ActiveSupport::Duration)
    MEDIUM_FILE_THRESHOLD = T.let(10.megabytes, Integer)
    LARGE_FILE_THRESHOLD = T.let(100.megabytes, Integer)

    sig { params(uploadable: T.untyped).void }
    def initialize(uploadable)
      @uploadable = uploadable
    end

    sig { params(query: T::Hash[T.untyped, T.untyped], path: String, expiration_time: T.nilable(ActiveSupport::Duration)).returns(T::Hash[T.untyped, T.untyped]) }
    def add_jwt_token_to_query(query, path, expiration_time = nil)
      query.merge(jwt: generate_jwt_token_for(path, expiration_time))
    end

    sig { params(path: String, expiration_time: T.nilable(ActiveSupport::Duration)).returns(String) }
    def generate_jwt_token_for(path, expiration_time = nil)
      timestamp = Time.now.to_i

      # If expiration_time is not provided, we use the default one
      expiration_time ||= jwt_expiration_time_for_file_size

      payload = {
        iss: "github.com",
        aud: @uploadable.fastly_jwt_audience,
        key: @uploadable.fastly_dictionary_key_name,
        exp: expiration_time.from_now.to_i,
        nbf: timestamp,
        path: path
      }
      JWT.encode(payload, @uploadable.fastly_dictionary_key_value, "HS256", { typ: "JWT" })
    end

    sig { returns(ActiveSupport::Duration) }
    def jwt_expiration_time_for_file_size
      return DEFAULT_EXPIRATION_TIME unless @uploadable.respond_to?(:size) && @uploadable.size

      if @uploadable.size > LARGE_FILE_THRESHOLD
        LARGE_FILE_EXPIRATION_TIME
      elsif @uploadable.size > MEDIUM_FILE_THRESHOLD
        MEDIUM_FILE_EXPIRATION_TIME
      else
        DEFAULT_EXPIRATION_TIME
      end
    end

  end
end
