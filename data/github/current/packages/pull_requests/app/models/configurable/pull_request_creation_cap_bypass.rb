# typed: strict
# frozen_string_literal: true

# Configures a bypass list of users that are exempt from the open pull request
# cap. Users on the bypass list can open pull requests regardless of the
# configured cap.
#
# The list is stored as a JSON array of integer IDs in the pull requests
# service KV store (ipr_key_values table), scoped to the repository.
# For example: [1234, 5678, 9012]
module Configurable
  module PullRequestCreationCapBypass
    extend T::Helpers

    requires_ancestor { PullRequestCreationConfig }

    # All keys must be prefixed with "pull_requests/" to avoid collisions with
    # Issues::KV, which shares the same underlying table.
    BYPASS_USER_IDS_KEY = T.let("pull_requests/pull_request_creation_cap_bypass/user_ids".freeze, String)

    # The user bypass list is intentionally capped at 100 entries. The KV store
    # can technically hold more, but this feature is expected to remain a narrow
    # use case: public repositories with an open-PR cap that want to exempt
    # specific non-collaborators. A larger list would require migrating to a
    # dedicated database table.
    BYPASS_USER_IDS_MAX = T.let(100, Integer)

    # -- Users ----------------------------------------------------------------

    # Public: Add multiple users to the bypass list in a single read/write cycle.
    # Raises if adding the new users would exceed BYPASS_USER_IDS_MAX.
    sig { params(users: T::Array[User]).void }
    def add_pull_request_creation_cap_bypass_users(users:)
      current_ids = read_bypass_ids(BYPASS_USER_IDS_KEY)
      new_ids = users.map(&:id).reject { |id| current_ids.include?(id) }
      return if new_ids.empty?

      if current_ids.size + new_ids.size > BYPASS_USER_IDS_MAX
        raise ArgumentError, "bypass list is at the maximum"
      end

      write_bypass_ids(key: BYPASS_USER_IDS_KEY, ids: current_ids + new_ids)
    end

    # Public: Returns true when the user bypass list has reached BYPASS_USER_IDS_MAX.
    sig { returns(T::Boolean) }
    def pull_request_creation_cap_bypass_user_list_full?
      pull_request_creation_cap_bypass_user_ids.size >= BYPASS_USER_IDS_MAX
    end

    # Public: Remove multiple users from the bypass list in a single read/write cycle.
    sig { params(users: T::Array[User]).void }
    def remove_pull_request_creation_cap_bypass_users(users:)
      current_ids = read_bypass_ids(BYPASS_USER_IDS_KEY)
      ids_to_remove = users.map(&:id).select { |id| current_ids.include?(id) }
      return if ids_to_remove.empty?

      write_bypass_ids(key: BYPASS_USER_IDS_KEY, ids: current_ids - ids_to_remove)
    end

    # Public: Return the list of user IDs exempt from the cap.
    sig { returns(T::Array[Integer]) }
    def pull_request_creation_cap_bypass_user_ids
      return [] unless allowlist_enabled?

      read_bypass_ids(BYPASS_USER_IDS_KEY)
    end

    # -- Check ----------------------------------------------------------------

    # Public: Is the user exempt from the cap?
    #
    # user - The User attempting to open a pull request.
    #
    # Returns Boolean.
    sig { params(user: User).returns(T::Boolean) }
    def pull_request_creation_cap_bypassed?(user:)
      return false unless allowlist_enabled?

      pull_request_creation_cap_bypass_user_ids.include?(user.id)
    end

    private

    sig { returns(GitHub::KV) }
    def kv_store
      PullRequests::KV.for_repository(repository)
    end

    sig { returns(T::Boolean) }
    def allowlist_enabled?
      FeatureFlag.vexi.enabled?(:pull_request_creation_cap, repository, default: false) && FeatureFlag.vexi.enabled?(:pull_request_creation_cap_allowlist, repository, default: false)
    end

    sig { params(key: String).returns(T::Array[Integer]) }
    def read_bypass_ids(key)
      raw = kv_store.get(key).value { nil }
      return [] if raw.nil?

      begin
        parsed = JSON.parse(raw)
        parsed.map { |id| Integer(id) }
      rescue JSON::ParserError, TypeError, ArgumentError => e
        Failbot.report(e, "gh.repo.id": repository.id, key: key, raw_value: raw)
        []
      end
    end

    sig { params(key: String, ids: T::Array[Integer]).void }
    def write_bypass_ids(key:, ids:)
      unique_ids = ids.uniq

      if unique_ids.empty?
        kv_store.del(key)
      else
        kv_store.set(key, JSON.generate(unique_ids))
      end

      nil
    end
  end
end
