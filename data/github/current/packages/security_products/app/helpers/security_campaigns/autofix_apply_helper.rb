# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module AutofixApplyHelper
    extend T::Sig

    include CodeScanningHelper
    include Kernel

    sig do
      params(
        suggested_fixes: T.untyped, # It's actually Google::Protobuf::Map, but unfortunately the syntax for setting the type parameters doesn't seem to work
        alerts: T.untyped, # It's actually Google::Protobuf::RepeatedField, but unfortunately the syntax for setting the type parameters doesn't seem to work
        repository: ::Repository,
        ref: ::Git::Ref,
        author: ::User,
        author_email: T.nilable(String),
        reflog_data: T::Hash[String, T.untyped],
      ).returns(
        T::Array[String]
      )
    end
    def apply_multiple_autofix_suggestions(suggested_fixes, alerts:, repository:, ref:, author:, author_email:, reflog_data:)
      # Create a list of proposed commits. Each proposed commit is a single fix to apply and might result in a new commit.
      proposed_commits = suggested_fixes.map do |alert_number, suggested_fix|
        alert = alerts.find { |a| a.number == alert_number }
        raise "Alert not found for alert number #{alert_number}" if alert.nil?

        # Create a commit message for this commit
        commit_message = commit_message_for(alert, repository: repository, author: author)

        # Convert the suggested fix into diff entries (i.e. Git diff hunks)
        diff_entries = diff_entries_for(suggested_fix)

        ProposedCommit.new(commit_message:, diff_entries:, alert:)
      end
      proposed_commits = T.let(proposed_commits, T::Array[ProposedCommit])

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
            "gh.code_scanning.alert.number": proposed_commit.alert.number,
            "gh.security_campaigns.file_paths": changed_files.to_a,
          )
        end

        conflicting_files.empty?
      end
    end

    # Creates a draft pull request for the given branch and returns the pull request.
    sig do
      params(
        alerts: T::Array[SecurityCampaigns::CampaignWithAlerts::TurboscanAlert],
        user: ::User,
        repository: ::Repository,
        branch: ::Git::Ref,
      ).returns(::PullRequest)
    end
    def commit_to_pr(alerts:, user:, repository:, branch:)
      title = alerts.size == 1 ? "Fix code scanning alert: #{result_title(alerts.first)}" : "Fix #{alerts.size} code scanning alerts"
      body = if alerts.size == 1
        <<~MARKDOWN
          Fixes #{UrlHelpers.repository_code_scanning_result_url(repository.owner, repository, number: alerts.first&.number, host: GitHub.url)}
        MARKDOWN
      else
        <<~MARKDOWN
          Fixes #{alerts.size} code scanning alerts:
          #{alerts.map { |alert| "- #{UrlHelpers.repository_code_scanning_result_url(repository.owner, repository, number: alert.number, host: GitHub.url)}" }.join("\n")}
        MARKDOWN
      end

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

    sig do
      params(
        suggested_fix: ::Turboscan::Proto::SuggestedFix,
      ).returns(
        T::Array[GitHub::Diff::Entry]
      )
    end
    def diff_entries_for(suggested_fix)
      suggested_fix.files.each_with_object([]) do |file, out|
        parser = GitHub::Diff::Parser.new(file.diff_content)
        parser.each do |entry|
          out << entry
        end
      end
    end

    sig do
      params(
        alert: SecurityCampaigns::CampaignWithAlerts::TurboscanAlert,
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
        "Apply code scanning fix for #{result_title(alert).downcase}",
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
      code_scanning_app = Apps::Internal.integration(:code_scanning)
      raise "code scanning integration not installed!" if code_scanning_app.nil?

      "Co-authored-by: Copilot Autofix powered by AI <#{code_scanning_app.bot.git_author_email}>"
    end

    class ProposedCommit
      extend T::Sig

      sig { returns(String) }
      attr_reader :commit_message

      sig { returns(T::Array[GitHub::Diff::Entry]) }
      attr_reader :diff_entries

      sig { returns(SecurityCampaigns::CampaignWithAlerts::TurboscanAlert) }
      attr_reader :alert

      sig do
        params(
          commit_message: String,
          diff_entries: T::Array[GitHub::Diff::Entry],
          alert: SecurityCampaigns::CampaignWithAlerts::TurboscanAlert,
        ).void
      end
      def initialize(commit_message:, diff_entries:, alert:)
        @commit_message = T.let(commit_message, String)
        @diff_entries = T.let(diff_entries, T::Array[GitHub::Diff::Entry])
        @alert = T.let(alert, SecurityCampaigns::CampaignWithAlerts::TurboscanAlert)
      end
    end
  end
end
