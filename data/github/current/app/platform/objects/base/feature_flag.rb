# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      # This adds semi-private features to the Public GraphQL API.
      #
      # When a type or field has `feature_flag: :my_cool_feature`, then it's only visible when:
      # - The feature flag is requested for the query:
      #   - For API requests, the request includes a header like `GraphQL-Features: my_cool_feature` (Multiple flags can be comma-separated)
      #    - Or, for non-API requests, `context[:feature_flags]` includes a matching symbol
      # - The `viewer` has a the named flag enabled with Flipper
      module FeatureFlag
        # @return [nil, Symbol] If present, an HTTP header which must be present to access this type
        def feature_flag(flag = nil)
          if flag
            @feature_flag = flag
          else
            @feature_flag
          end
        end

        if Rails.env.test?
          # This is only used for testing
          def feature_flag=(new_flag)
            @feature_flag = new_flag
          end
        end

        def generate_input_type
          apply_flag_to_class(super)
        end

        def generate_payload_type
          apply_flag_to_class(super)
        end

        # Filter `flags` to include only the ones that the current request should have enabled.
        # If the current user has the flag enabled, we enable the flag. However, we also enable the flag
        # For any viewer of a GitHub App or Oauth App that has the flag enabled.
        # @param requested_flags [[Symbol]
        # @param user [User | nil]
        # @param app [OauthApplication | Integration | nil]
        sig do
          params(
            requested_flags: T::Array[Symbol],
            user: T.nilable(::User),
            app: T.any(T.nilable(::OauthApplication), ::Integration)
          )
            .returns(T::Array[Symbol])
        end
        def self.filter_requested_flags(requested_flags, user:, app:)
          return [] if user.nil? && app.nil?

          requested_flags.select do |flag|
            feature = GitHub.flipper[flag]
            feature.enabled?(user) || feature.enabled?(app) || feature.enabled?(app&.owner) || user&.organizations&.any? { |org| feature.enabled?(org) }
          end
        end

        private

        def apply_flag_to_class(defn_class)
          if @feature_flag
            defn_class.feature_flag(@feature_flag)
          end
          defn_class
        end
      end
    end
  end
end
