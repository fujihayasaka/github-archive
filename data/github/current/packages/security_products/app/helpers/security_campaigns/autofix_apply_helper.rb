# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module AutofixApplyHelper
    include CodeScanningHelper
    include Kernel

    sig do
      params(
        suggested_fixes: T::Hash[Integer, Turboscan::Proto::SuggestedFix],
        alerts: T::Array[CodeScanning::AlertResult],
        repository: ::Repository,
        ref: ::Git::Ref,
        author: ::User,
        author_email: T.nilable(String),
        reflog_data: T::Hash[String, T.untyped],
        user_commit_message: T.nilable(String),
      ).returns(
        T::Array[String]
      )
    end
    def apply_multiple_autofix_suggestions(suggested_fixes, alerts:, repository:, ref:, author:, author_email:, reflog_data:, user_commit_message: nil)
      # Create a list of proposed commits. Each proposed commit is a single fix to apply and might result in a new commit.
      proposed_commits = T.let([], T::Array[ProposedCommit])
      proposed_commits = suggested_fixes.map do |alert_number, suggested_fix|
        alert = alerts.find { |a| a.result.number == alert_number }
        raise "Alert not found for alert number #{alert_number}" if alert.nil?

        # Create a commit message for this commit if one wasn't provided
        commit_message = user_commit_message || commit_message_for(
          alert,
          repository: repository,
          author: author,
        )

        # Convert the suggested fix into diff entries (i.e. Git diff hunks)
        diff_entries = CodeScanning::AutofixSuggestion.new(suggested_fix).diff_entries

        ProposedCommit.new(commit_message:, diff_entries:, alert_number: alert.result.number)
      end

      # Filter the proposed commits to only include non-conflicting commits
      proposed_commits, removed_commits = filter_proposed_commits(proposed_commits, repository:)

      error_messages = commit_fixes(proposed_commits:, repository:, ref:, author:, author_email:, reflog_data:)

      if removed_commits.any?
        error_messages << "Some autofixes were not applied due to conflicts."
      end

      error_messages
    end

    # Commit the proposed commits to the given branch. This will create a new commit for each proposed commit,
    # unless the proposed commit results in no changes.
    # Returns a list of error messages.
    sig do
      params(
        proposed_commits: T::Array[ProposedCommit],
        repository: ::Repository,
        ref: ::Git::Ref,
        author: ::User,
        author_email: T.nilable(String),
        reflog_data: T.nilable(T::Hash[String, T.untyped]),
      ).returns(
        T::Array[String]
      )
    end
    def commit_fixes(proposed_commits:, repository:, ref:, author:, author_email:, reflog_data:)
      current_commit = ref.commit

      messages = []

      proposed_commits.each do |proposed_commit|
        # Apply the diff entries to the current commit (i.e. the default branch commit or the commit of the previous autofix)
        files = files_for_diff_entries(proposed_commit.diff_entries, repository: repository, commit: current_commit)

        # Then commit this change to the new branch
        commit_oid, _branch, error_message = repository.commit_change_for_user(
          author:,
          author_email:,
          branch: ref.name,
          files:,
          message: proposed_commit.commit_message,
          reflog_data: reflog_data,
          sign: true,
          ref:,
        )

        # If we successfully committed the change, update the current commit to the new commit
        current_commit = repository.commits.find(commit_oid) if commit_oid.present?

        # If we failed to commit the change, add an error message to the messages array
        messages << error_message if error_message.present?
      end

      messages
    end

    # Filter the proposed commits to remove commits that conflict. Returns a list of proposed commits
    # that should be applied in order and a list of proposed commits that were removed because of conflicts.
    # Conflicts are detected by checking if the same file is modified by multiple proposed commits.
    sig do
      params(
        proposed_commits: T::Array[ProposedCommit],
        repository: ::Repository,
      ).returns(
        [T::Array[ProposedCommit], T::Array[ProposedCommit]]
      )
    end
    def filter_proposed_commits(proposed_commits, repository:)
      # Keep track of all the files that have been modified by an included proposed commit
      changed_files = Set.new

      proposed_commits.partition do |proposed_commit|
        # All of the files included in the patch should be unchanged so far
        conflicting_files = proposed_commit.diff_entries.select do |diff_entry|
          changed_files.include?(diff_entry.path)
        end

        # If we're keeping this commit, add all of the files in the patch to the changed files set
        if conflicting_files.empty?
          proposed_commit.diff_entries.each do |diff_entry|
            changed_files << diff_entry.path
          end
        else
          GitHub.logger.info("Filtering out proposed commit due to conflicting patches.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.repo.id": repository.id,
            "gh.code_scanning.alert.number": proposed_commit.alert_number,
            "gh.security_campaigns.file_paths": changed_files.to_a,
          )
        end

        conflicting_files.empty?
      end
    end

    # Creates a draft pull request for the given branch and returns the pull request.
    sig do
      params(
        suggested_fixes: T::Hash[Integer, Turboscan::Proto::SuggestedFix],
        alerts: T::Array[CodeScanning::AlertResult],
        user: ::User,
        repository: ::Repository,
        branch: ::Git::Ref,
      ).returns(::PullRequest)
    end
    def commit_to_pr(suggested_fixes:, alerts:, user:, repository:, branch:)
      title = pr_title(alerts)
      body = pr_body(repository, suggested_fixes, alerts)

      PullRequest.create_for!(repository, {
        user:,
        base: repository.default_branch,
        draft: true,
        head: branch.name,
        title:,
        body:,
      })
    end

    private

    sig { params(alerts: T::Array[CodeScanning::AlertResult]).returns(String) }
    def pr_title(alerts)
      alerts_count = alerts.size

      if alerts_count == 1
        first_alert = T.must(alerts.first)
        "Fix code scanning alert no. #{first_alert.result.number}: #{result_title(first_alert.result)}"
      else
        "Fix #{alerts_count} code scanning alerts"
      end
    end

    sig do
      params(
        repo: Repository,
        suggested_fixes: T::Hash[Integer, Turboscan::Proto::SuggestedFix],
        alerts: T::Array[CodeScanning::AlertResult]
      ).returns(String)
    end
    def pr_body(repo, suggested_fixes, alerts)
      alerts_count = alerts.size

      body = if alerts_count == 1
        first_alert = T.must(alerts.first)
        first_alert_url = UrlHelpers.repository_code_scanning_result_url(repo.owner, repo, number: first_alert.result.number, host: GitHub.url)
        <<~MARKDOWN
          Fixes [#{first_alert_url}](#{first_alert_url})

          #{suggested_fixes[first_alert.result.number]&.description}
        MARKDOWN
      else
        alert_descriptions = if alerts_count < 4
          alerts.map do |alert|
            alert_url = UrlHelpers.repository_code_scanning_result_url(repo.owner, repo, number: alert.result.number, host: GitHub.url)
            # This gets the suggested fix description to render as a markdown list item by
            # adding two spaces after each newline that has text afterwards.
            description = suggested_fixes[alert.result.number]&.description&.gsub(/\n(?!\s)/, "\n  ")

            <<~MARKDOWN
              - #{alert_url}
              #{description}
            MARKDOWN
          end.join("\n\n")
        else
          alerts.map do |alert|
            alert_url = UrlHelpers.repository_code_scanning_result_url(repo.owner, repo, number: alert.result.number, host: GitHub.url)
            # This gets the suggested fix description to render as a markdown list item enclosed in another tag by
            # adding four spaces after each newline that has text afterwards.
            description = suggested_fixes[alert.result.number]&.description&.gsub(/\n(?!\s)/, "\n    ")

            <<~MARKDOWN
              - #{alert_url}
                <details>
                  <summary>Suggested fix description</summary>
                  #{description}
                </details>
            MARKDOWN
          end.join("\n\n")
        end

        <<~MARKDOWN
          Fixes #{alerts_count} code scanning alerts:
          #{alert_descriptions}
        MARKDOWN
      end

      body + "\n_Suggested fixes powered by Copilot Autofix. Review carefully before merging._"
    end

    sig do
      params(
        alert: CodeScanning::AlertResult,
        repository: ::Repository,
        author: ::User,
      ).returns(String)
    end
    def commit_message_for(alert, repository:, author:)
      commit_body = begin
        arr = []
        arr << code_scanning_bot_co_author_note
        arr << DcoSignoffHelper::dco_signoff_text(author) if repository.dco_signoff_enabled?
        arr.join("\n")
      end

      [
        "Fix code scanning alert no. #{alert.result.number}: #{result_title(alert.result)}",
        commit_body,
      ].join("\n\n")
    end

    sig do
      params(
        diff_entries: T::Array[GitHub::Diff::Entry],
        repository: ::Repository,
        commit: ::Commit,
      ).returns(
        T::Hash[String, String]
      )
    end
    def files_for_diff_entries(diff_entries, repository:, commit:)
      diff_entries.each_with_object({}) do |diff_entry, out|
        path = diff_entry.path

        blob = repository.blob(
          commit.tree_oid,
          path,
          { truncate: false, limit: 1.megabytes },
        )

        source = blob.data.split(DiffEntrySuggestedChange::NEWLINE_REGEXP, -1)
        result = []

        ai = bj = 0

        diff_entry.basic_enumerator.each do |line|
          if line.deletion?
            while ai < line.current - 1
              result << source[ai]
              ai += 1
              bj += 1
            end
            ai += 1
          elsif line.addition?
            while bj < line.current - 1
              result << source[ai]
              ai += 1
              bj += 1
            end
            bj += 1

            result << line.text[1..-1]
          end
        end

        while ai < source.size
          result << source[ai]
          ai += 1
          bj += 1
        end

        out[path] = result.join(blob.has_windows_line_endings? ? "\r\n" : "\n")
      end
    end

    sig { returns(String) }
    def code_scanning_bot_co_author_note
      code_scanning_app = Apps::Privileged.integration(:code_scanning)
      raise "code scanning integration not installed!" if code_scanning_app.nil?

      "Co-authored-by: Copilot Autofix powered by AI <#{code_scanning_app.bot.git_author_email}>"
    end

    class ProposedCommit
      sig { returns(String) }
      attr_reader :commit_message

      sig { returns(T::Array[GitHub::Diff::Entry]) }
      attr_reader :diff_entries

      sig { returns(Integer) }
      attr_reader :alert_number

      sig do
        params(
          commit_message: String,
          diff_entries: T::Array[GitHub::Diff::Entry],
          alert_number: Integer,
        ).void
      end
      def initialize(commit_message:, diff_entries:, alert_number:)
        @commit_message = T.let(commit_message, String)
        @diff_entries = T.let(diff_entries, T::Array[GitHub::Diff::Entry])
        @alert_number = T.let(alert_number, Integer)
      end
    end
  end
end
