# typed: strict
# frozen_string_literal: true

module Storage
  module FastlyReleaseAssetsDependency
    extend T::Helpers
    include FastlyDependency

    abstract!

    sig { override.returns(String) }
    def storage_fastly_acceleration_bucket
      GitHub.memory_alpha_fastly_host
    end

    sig { override.returns(T.nilable(String)) }
    def fastly_dictionary_key_name
      "key1"
    end

    sig { override.returns(T.nilable(String)) }
    def fastly_dictionary_key_value
      GitHub.private_abs_asset_cdn_key
    end

    sig { override.returns(T.nilable(String)) }
    def fastly_jwt_audience
      GitHub.release_assets_fastly_host
    end
  end
end
