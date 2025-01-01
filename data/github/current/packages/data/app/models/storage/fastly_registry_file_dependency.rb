# typed: strict
# frozen_string_literal: true

module Storage
  module FastlyRegistryFileDependency
    extend T::Helpers
    include FastlyDependency

    abstract!

    sig { override.returns(String) }
    def storage_fastly_acceleration_bucket
      "github-registry-files.githubusercontent.com"
    end

    sig { override.returns(T.nilable(String)) }
    def fastly_dictionary_key_name
      nil
    end

    sig { override.returns(T.nilable(String)) }
    def fastly_dictionary_key_value
      nil
    end

    sig { override.returns(T.nilable(String)) }
    def fastly_jwt_audience
      nil
    end
  end
end
