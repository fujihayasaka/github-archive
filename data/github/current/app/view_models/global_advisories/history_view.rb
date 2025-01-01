# typed: true
# frozen_string_literal: true

module GlobalAdvisories
  class HistoryView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :advisory

    def dotcom_suffix
      GitHub.single_or_multi_tenant_enterprise? ? " on GitHub.com" : ""
    end

    def show_history_changes_text?
      !GitHub.single_or_multi_tenant_enterprise?
    end

    def show_history_section?
      return true if GitHub.single_or_multi_tenant_enterprise?
      return false unless advisories_repository

      cached_advisories_repository_history
    end

    def advisory_history_url
      "#{GitHub.single_or_multi_tenant_enterprise? ? "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_host_name}" : ""}/#{AdvisoryDB::ADVISORIES_REPOSITORY_NWO}/commits/#{AdvisoryDB::ADVISORIES_REPOSITORY_DEFAULT_BRANCH}/#{advisory_file_path}"
    end

    private

    def advisories_repository
      return @advisories_repository if defined?(@advisories_repository)

      @advisories_repository = AdvisoryDB.advisories_repository
    end

    def advisory_file_path
      return @advisory_file_path if defined?(@advisory_file_path)

      @advisory_file_path = AdvisoryDB.repo_file_path(advisory)
    end

    # The underlying commits should remain unchanged between advisory
    # publishing events, so we can cache this to improve performance.
    # The KV will be reset by an after_commit hook on the advisory, and
    # changes to the repo file content/existance should be synonymous with
    # changes to the instance. We still set a reasonable TTL on it just to
    # ensure the KV is cleaned up on occasion for advisories that don't get
    # much traffic.
    def cached_advisories_repository_history
      history_key = advisory.github_kv_advisories_repository_commits_history_key
      cached_history = AdvisoryDB::KV.store.get(history_key).value { nil }
      return (cached_history == "1" ? true : false) if cached_history.present?

      history = begin
        # To display history, we want to make sure the advisory repository file
        # exists by checking the tree path. If this is false it will raise a
        # GitRPC::NoSuchPath exception
        advisories_repository.tree_entry(
          advisories_repository.default_branch_ref.target_oid,
          advisory_file_path
        )

        # We also want to make sure there is more than one commit to the file
        advisories_repository.commits.history(
          advisories_repository.default_branch_ref.target_oid,
          2, 0, advisory_file_path
        ).size > 1
      rescue GitRPC::NoSuchPath
        false
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        history_kv_value = history ? "1" : "0"
        AdvisoryDB::KV.store.set(history_key, history_kv_value, expires: 1.month.from_now)
      end

      history
    end
  end
end
