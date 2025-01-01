# typed: strict
# frozen_string_literal: true

module Storage
  module FastlyMediaBlobDependency
    extend T::Helpers
    include FastlyDependency

    abstract!

    sig { override.returns(T.nilable(String)) }
    def storage_fastly_acceleration_bucket
      if !GitHub.single_or_multi_tenant_enterprise? && !Rails.env.development?
        "github-cloud.githubusercontent.com"
      end
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
