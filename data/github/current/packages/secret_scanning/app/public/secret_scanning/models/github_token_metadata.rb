# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    class GitHubTokenMetadata
      attr_reader :created_at, :expires_at, :last_accessed_at, :name, :org_access, :link, :owner_id, :token_type, :access_id, :is_owner_suspended

      sig do
        params(
          created_at: T.nilable(Time),
          expires_at: T.nilable(Time),
          last_accessed_at: T.nilable(Time),
          org_access: T.nilable(Symbol),
          token_type: String,
          access_id: T.nilable(Integer),
          is_owner_suspended: T::Boolean,
          owner_id: T.nilable(Integer),
          name: T.nilable(String),
          link: T.nilable(String),
        ).void
      end
      def initialize(created_at:, expires_at:, last_accessed_at:, org_access:, token_type:, access_id:, is_owner_suspended: false, owner_id: nil, name: nil, link: nil)
        @created_at = created_at
        @expires_at = expires_at
        @last_accessed_at = last_accessed_at
        @org_access = org_access
        @owner_id = owner_id
        @name = name
        @link = link
        @token_type = token_type
        @access_id = access_id
        @is_owner_suspended = is_owner_suspended
      end
    end
  end
end
