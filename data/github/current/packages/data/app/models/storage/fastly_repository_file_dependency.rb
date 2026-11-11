# typed: strict
# frozen_string_literal: true

module Storage
  module FastlyRepositoryFileDependency
    extend T::Helpers
    include FastlyDependency

    abstract!

    sig { override.returns(String) }
    def storage_fastly_acceleration_bucket
      GitHub.memory_alpha_fastly_host
    end

    sig { override.returns(T.nilable(String)) }
    def fastly_dictionary_key_name
      nil
    end

    sig { override.returns(String) }
    def fastly_dictionary_key_value
      GitHub.private_abs_asset_cdn_key
    end

    sig { override.returns(T.nilable(String)) }
    def fastly_jwt_audience
      nil
    end
  end
end
