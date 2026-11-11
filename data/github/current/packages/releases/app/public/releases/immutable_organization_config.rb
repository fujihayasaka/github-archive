# typed: strict
# frozen_string_literal: true

module Releases
  class ImmutableOrganizationConfig
    extend T::Helpers
    include Instrumentation::Model

    POLICY_KEY = "immutable_releases_organization_policy"
    ENFORCED_KEY = "immutable_releases_enforced_by_owner"

    # Possible values for the immutable releases state.
    ALL = "all"
    SELECTED = "selected"
    NONE = "none"

    VALUES = T.let([ALL, SELECTED, NONE].freeze, T::Array[String])
    DEFAULT_VALUE = NONE

    BATCH_SIZE = 500
    private_constant :BATCH_SIZE

    sig { returns(Users::IUser) }
    attr_reader :organization

    sig { params(organization: Users::IUser).void }
    def initialize(organization)
      @organization = organization
    end

    sig { params(value: String, actor: ::User).void }
    def set_immutable_releases_policy(value, actor:)
      raise ArgumentError, "Invalid value for immutable releases policy" unless VALUES.include?(value)

      if value != immutable_releases_policy
        T.cast(@organization, ::Organization).instrument :update_immutable_releases_settings_policy,
          actor: actor,
          old_policy: immutable_releases_policy,
          new_policy: value
      end

      config.set!(POLICY_KEY, value, actor)
    end

    sig { returns(String) }
    def immutable_releases_policy
      config.get(POLICY_KEY) || DEFAULT_VALUE
    end

    sig { returns(T::Boolean) }
    def immutable_releases_enabled_for_all?
      immutable_releases_policy == ALL
    end

    sig { returns(T::Boolean) }
    def immutable_releases_enabled_for_selected?
      immutable_releases_policy == SELECTED
    end

    sig { returns(T::Boolean) }
    def immutable_releases_enabled_for_none?
      immutable_releases_policy == NONE
    end

    # Returns a list of repository IDs that have immutable releases enforced by the organization.
    sig { returns(T::Array[Integer]) }
    def immutable_releases_enforced_repo_ids
      repo_ids = T.cast(organization, ::Organization).repository_ids

      for_each_repo(ENFORCED_KEY, repo_ids) do |rel|
        rel.with_true_value.pluck(:target_id)
      end
    end

    # Enforce immutable releases for specific repository IDs. This will set the `immutable_releases_enforced_by_owner`
    # config entry to true for specified repository IDs.
    #
    # There may or may not be existing config entries for these repository IDs, so this operation has two parts:
    # 1. It updates any existing entries that are set to false, ensuring they are set to true.
    # 2. It creates new entries for any repository IDs that do not already have an entry.
    sig { params(ids: T::Array[Integer], actor: ::User).returns(Integer) }
    def enforce_immutable_releases_for_repo_ids(ids, actor:)
      # Filter out any IDs that are not part of the organization's repositories.
      repo_ids = filter_repo_ids(ids)

      # Find the repo IDs that already have the enforced config entry.
      existing_ids = for_each_repo(ENFORCED_KEY, repo_ids) do |rel|
        rel.pluck(:target_id)
      end

      # For any existing entries, ensure they are set to true.
      for_each_repo(ENFORCED_KEY, existing_ids) do |rel|
        rel.with_value("false").update_all(value: "true", updated_at: Time.current, updater_id: actor.id)
      end

      new_ids = repo_ids - existing_ids

      # For repositories that do not have an existing entry, create a new one.
      if new_ids.any?
        new_ids.each_slice(BATCH_SIZE) do |slice|
          new_entries = slice.map do |repo_id|
            {
              name: ENFORCED_KEY,
              target_type: "Repository",
              target_id: repo_id,
              value: "true",
              updater_id: actor.id,
              created_at: Time.current,
              updated_at: Time.current
            }
          end
          ::Configuration::Entry.insert_all(new_entries)
        end
      end

      repo_ids.count
    end

    # Unenforce immutable releases for specific repository IDs. This will set the
    # `immutable_releases_enforced_by_owner` config entry to false for specified repository IDs. Given that
    # "unenforced" is the default state, this will only update existing entries that are currently set to true.
    sig { params(ids: T::Array[Integer], actor: ::User).returns(Integer) }
    def unenforce_immutable_releases_for_repo_ids(ids, actor:)
      # Filter out any IDs that are not part of the organization's repositories.
      repo_ids = filter_repo_ids(ids)

      unenforce_immutable_releases(repo_ids, actor:)
    end

    # Unenforce immutable releases for all organization repositories. Given that "unenforced" is the default state,
    # this will only update existing entries that are currently set to true. This should be used whenever the org
    # admin switchs the policy to `none`.
    #
    # Returns the total number of updated rows.
    sig { params(actor: ::User).returns(Integer) }
    def unenforce_immutable_releases_for_all_repos(actor:)
      # Retrieve all repository IDs for the organization.
      repo_ids = T.cast(organization, ::Organization).repository_ids

      unenforce_immutable_releases(repo_ids, actor:)
    end

    private

    # Leverage the organization's cached config.
    sig { returns(Configuration) }
    def config
      T.cast(organization, ::User).config # rubocop:todo GitHub/AvoidCast
    end

    # Unenforce immutable releases for specific repository IDs.
    #
    # NOTE: This method does NOT verify repository IDs against the organization. It assumes that the provided
    # repository IDs are valid and part of the organization.
    sig { params(repo_ids: T::Array[Integer], actor: ::User).returns(Integer) }
    def unenforce_immutable_releases(repo_ids, actor:)
      results = for_each_repo(ENFORCED_KEY, repo_ids) do |rel|
        rel.with_true_value.update_all(value: "false", updated_at: Time.current, updater_id: actor.id)
      end

      # Sum the total number of updated rows across all batches
      results.inject(0) { |sum, result| sum + result }
    end

    # Iterate over repository IDs in batches and apply the block to each batch. This is useful for operations that
    # need to be performed on a large number of repositories without hitting database limits or performance issues.
    #
    # Returns an array of results from the block for each batch.
    sig do
      params(
        key: String,
        repo_ids: T::Array[Integer],
        block: T.proc.params(arg: T.untyped).returns(T.untyped)
      ).returns(T::Array[T.untyped])
    end
    def for_each_repo(key, repo_ids, &block)
      results = repo_ids.each_slice(BATCH_SIZE).map do |slice|
        block.call(
          ::Configuration::Entry
            .targeting_repository_ids(slice)
            .named(key)
        )
      end

      results.flatten
    end

    # Filter the repository IDs to only include those that are part of the organization -- ensuring that we only
    # operate on valid repositories. Processes the IDs in batches to avoid hitting database limits or performance
    # issues.
    #
    # Returns the subset of input repository IDs that are part of the organization.
    sig { params(repo_ids: T::Array[Integer]).returns(T::Array[Integer]) }
    def filter_repo_ids(repo_ids)
      repo_ids.each_slice(BATCH_SIZE).map do |slice|
        T.cast(organization, ::Organization).repositories.where(id: slice).pluck(:id)
      end.flatten
    end
  end
end
