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

      sig { params(user_id: Integer, repo_id: Integer, token_scan_result_id: Integer, token_number: Integer).returns(T::Hash[Symbol, T.untyped]) }
      def to_metadata_event_hash(user_id:, repo_id:, token_scan_result_id:, token_number:)
        md_keys = build_metadata_keys_found
        success = md_keys.length > 0
        {
          user_id: user_id,
          requested_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
          success: success,
          metadata_keys_found: md_keys,
          token_type: token_type,
          repository_id: repo_id,
          number: token_number,
          token_scan_result_id: token_scan_result_id,
        }
      end

      private

      sig { returns(T::Array[String]) }
      def build_metadata_keys_found
        keys = []
        # These need to be sync'd with key names in TSS that we use to normalize metadata for partner tokens.
        # See: https://github.com/github/token-scanning-service/blob/main/ts/partnermetadata/types/metadata_keys.go
        keys << "Secret issued date" if @created_at
        keys << "Secret expiry date" if @expires_at
        keys << "Owner ID" if @owner_id # if we can get the owner ID, we can show the user
        keys << "Owner name" if @owner_id
        keys << "Secret name" if @name
        keys
      end
    end
  end
end
