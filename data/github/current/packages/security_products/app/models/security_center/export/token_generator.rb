# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Export
    class TokenGenerator

      sig { params(user: User, scope: T.any(Organization, Business), query: String, feature_type: String, requested_at: Time, start_date: T.nilable(Date), end_date: T.nilable(Date)).returns(String) }
      def self.create_token(user:, scope:, query:, feature_type:, requested_at:, start_date: nil, end_date: nil)
        raise "Start and end date must be defined" if feature_type == "overview_dashboard" && (start_date.nil? || end_date.nil?)

        Digest::SHA256.hexdigest([
          "c7a9180a-2a11-4058-af66-530a10c474c7", # random uuid to make it harder to guess what the inputs are
          user.id,
          scope.id,
          scope.class.name,
          query,
          feature_type,
          start_date.to_s,
          end_date.to_s,
          Time.at(requested_at.to_i - (requested_at.to_i % 1.minute)).utc.iso8601, # round to nearest minute to help prevent abuse
        ].join("/"))
      end

      sig { params(token: String).returns(T::Boolean) }
      def self.token_is_sha_256?(token)
        sha256_regex = /\A[a-f0-9]{64}\z/i
        token.match?(sha256_regex)
      end
    end
  end
end
