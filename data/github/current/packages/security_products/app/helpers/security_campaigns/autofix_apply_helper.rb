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
        user_commit_message: T.nilable(String),
      ).returns(
        T::Array[String]
      )
    end
    def apply_multiple_autofix_suggestions(suggested_fixes, alerts:, repository:, ref:, author:, user_commit_message: nil)
      # Create a list of proposed commits. Each proposed commit is a single fix to apply and might result in a new commit.
      proposed_commits = T.let([], T::Array[ProposedCommit])
      proposed_commits = suggested_fixes.map do |alert_number, suggested_fix|
        alert = alerts.find { |a| a.result.number == alert_number }
        raise "Alert not found for alert number #{alert_number}" if alert.nil?

        # Create a commit message for this commit if one wasn't provided
        commit_message = user_commit_message || CodeScanning::AutofixCommit.message_for_alert(alert_number:, alert_title: result_title(alert.result))

        ProposedCommit.new(commit_message:, alert_number: alert.result.number, autofix_suggestion: CodeScanning::AutofixSuggestion.new(suggested_fix))
      end

      # Filter the proposed commits to only include non-conflicting commits
      proposed_commits, removed_commits = filter_proposed_commits(proposed_commits, repository:)

      error_messages = commit_fixes(proposed_commits:, repository:, ref:, author:)

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
      ).returns(
        T::Array[String]
      )
    end
    def commit_fixes(proposed_commits:, repository:, ref:, author:)
      current_commit = ref.commit

      messages = []

      proposed_commits.each do |proposed_commit|
        # Then commit this change to the new branch
        begin
          commit_oid, _branch, error_message = CodeScanning::AutofixCommit.create(
            alert_number: proposed_commit.alert_number,
            commit_message: proposed_commit.commit_message,
            repository: repository,
            ref:,
            author:,
            suggested_fix: proposed_commit.autofix_suggestion,
            reflog_via: "apply autofix suggestion from security campaign",
            current_oid: current_commit.oid
          )
        rescue CodeScanning::AutofixError, DiffEntrySuggestedChange::Error, Git::Ref::InvalidName, Git::Ref::ExistsError, Git::Ref::UpdateError => e
          messages << e.message
        end

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
        security_campaign: SecurityCampaigns::SecurityCampaign,
      ).returns(::PullRequest)
    end
    def commit_to_pr(suggested_fixes:, alerts:, user:, repository:, branch:, security_campaign:)
      if alerts.length == 1
        alert = T.must(alerts.first&.result)
        alert_number = alert.number
        title = CodeScanning::AutofixCommit.message_for_alert(alert_number:, alert_title: result_title(alert))
        body = CodeScanning::AutofixCommit.pull_request_description_for_alert(repository:, alert_number:, suggested_fix: suggested_fixes[alert_number], security_campaign:)
      else
        alert_numbers = alerts.map { |alert| alert.result.number }
        title = CodeScanning::AutofixCommit.message_for_alerts(alert_numbers:)
        body = CodeScanning::AutofixCommit.pull_request_description_for_alerts(repository:, alert_numbers:, suggested_fixes:, security_campaign:)
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

    class ProposedCommit
      sig { returns(String) }
      attr_reader :commit_message

      sig { returns(T::Array[GitHub::Diff::Entry]) }
      attr_reader :diff_entries

      sig { returns(Integer) }
      attr_reader :alert_number

      sig { returns(CodeScanning::AutofixSuggestion) }
      attr_reader :autofix_suggestion

      sig do
        params(
          commit_message: String,
          alert_number: Integer,
          autofix_suggestion: CodeScanning::AutofixSuggestion,
        ).void
      end
      def initialize(commit_message:, alert_number:, autofix_suggestion:)
        @commit_message = T.let(commit_message, String)
        @alert_number = T.let(alert_number, Integer)
        @autofix_suggestion = T.let(autofix_suggestion, CodeScanning::AutofixSuggestion)
        @diff_entries = T.let(autofix_suggestion.diff_entries, T::Array[GitHub::Diff::Entry])
      end
    end
  end
end
