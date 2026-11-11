# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class CodeScanningAutofix < Seeds::Runner
      def self.help
        <<~HELP
        Create a pull request with an alert and suggested fix for code scanning development (use together with script/turbomock)
        HELP
      end

      def self.run(options = {})
        owner_name = nil
        repository_name = nil

        if options[:repo]
          parts = options[:repo].split("/", 2)
          if parts.size == 2
            owner_name, repository_name = parts
          else
            repository_name = parts[0]
          end
        end

        if options[:org]
          if owner_name && owner_name != options[:org]
            abort "Organization mismatch! #{owner_name} != #{options[:org]}"
          end

          owner_name = options[:org]
        end

        runner = new(owner_name:, repository_name:)

        puts "Starting..."
        puts

        runner.ensure_owner
        puts "✅ Owner: #{runner.owner.display_login}"

        runner.ensure_repository
        puts "✅ Repository: #{runner.repository.nwo}"
        runner.repository.enable_feature_flag(:code_scanning_automated_review_comment) if options[:arc]

        runner.ensure_integrations
        puts "✅ Integrations ready"

        runner.create_pull_request
        puts "✅ PR: ##{runner.pull_request.number}"

        begin
          runner.create_annotations
          puts "✅ Created annotations"
        rescue AnnotationsNotCreatedError
          puts "⚠️ No code scanning alerts found — is turbomock running? Try: script/turbomock"
        end

        if options[:arc]
          synced_comments_count = runner.sync_automated_review_comment_suggestions.count
          puts "✅ Synced #{synced_comments_count} automated review comment suggestion#{"s" unless synced_comments_count == 1}"
        end

        runner.create_ai_finding_comments
        puts "✅ Created AI finding comments"

        runner.create_code_quality_comment
        puts "✅ Created code quality comment with suggestion"

        runner.create_copilot_comment
        puts "✅ Created Copilot finding comment"

        puts
        puts "PR is ready:\n"
        puts "    http://#{GitHub.host_name}/#{runner.repository.nwo}/pull/#{runner.pull_request.number}"
        puts
      end

      attr_reader :owner_name, :repository_name
      attr_reader :owner, :repository, :pull_request, :new_alert
      attr_reader :unique_identifier

      AnnotationsNotCreatedError = Class.new(StandardError)

      def initialize(owner_name: nil, repository_name: nil)
        @owner_name = owner_name
        @repository_name = repository_name
      end

      def ensure_owner
        # Ensure monalisa is created before looking up the owner
        _ = Seeds::Objects::User.monalisa

        @owner = if owner_name
          ::User.find_by(login: owner_name) || Seeds::Objects::Organization.create(login: owner_name, admin: Seeds::Objects::User.monalisa)
        else
          Seeds::Objects::Organization.github
        end

        if owner.organization?
          if owner.business.present?
            owner.business.mark_advanced_security_as_purchased_for_entity(actor: owner.admins.first)
          else
            owner.mark_advanced_security_as_purchased_for_entity(actor: owner.admins.first)
          end
        end
      end

      def ensure_repository
        @repository = Seeds::Objects::Repository.restore_premade_repo(
          location_premade_git: "test/fixtures/git/examples/code_scanning_autofix.git",
          owner_name: owner.display_login,
          repo_name: repository_name || "autofix-demo-#{Time.now.to_i}",
          is_public: false,
        )

        # Restoring a premade repo will in some cases not have the default branch loaded in the call to `@repo.refs`.
        # Reloading resolves this issue.
        repository.reload

        if owner.organization?
          repository.enable_advanced_security(actor: owner.admins.first)
        end
      end

      def create_pull_request
        before_oid = repository.default_branch_ref.commit.oid
        branch = "synthetic-xss-#{unique_identifier}"

        @pull_request = ::PullRequest.create_for!(
          repository,
          user: Seeds::Objects::User.monalisa,
          title: "A simple example of an XSS vulnerability",
          body: "Example from https://github.com/github/codeml-autofix/tree/main/cocofix/examples/synthetic-xss",
          head: "reflected-xss",
          base: repository.default_branch
        )
      end

      def ensure_integrations
        Seeds::Objects::Integration.create_code_scanning_integration
        Seeds::Objects::Integration.create_code_quality_integration
        Seeds::Objects::Integration.create_copilot_pull_request_reviewer_integration
        Apps::Privileged::Registry.instance.reload_caches!
      end

      def create_annotations
        commit_oid = pr_head.commit.oid
        code_scanning_check_suite = ::CheckRun.create_code_scanning_check_suite(
          repository: repository,
          annotated_commit_oid: commit_oid,
          analyzed_commit_oid: commit_oid,
          ref: pr_head.qualified_name,
          base_ref: pr_base.qualified_name,
          base_sha: pull_request.base_sha,
        )

        check_runs = ::CheckRun.create_code_scanning_check_runs(
          check_suite: code_scanning_check_suite.check_suite,
          tool_names: ["CodeQL"]
        )

        alerts_before = alerts_for_pull_request_count

        check_runs.each do |check_run|
          CreateCodeScanningAnnotationsJob.perform_now(check_run_id: check_run.id, reason: :forced_by_seed_script)
        end

        raise AnnotationsNotCreatedError unless alerts_for_pull_request_count > alerts_before
      end

      def alerts_for_pull_request_count
        ::AutomatedReviewComment.where(
          repository: repository,
          pull_request: pull_request,
          source: :source_code_scanning,
          fixed_at: nil,
        ).count +
        pull_request.code_scanning_review_comments.where(fixed: false).count
      end

      def create_ai_finding_comments
        bot = Apps::Privileged.integration(:code_scanning).bot
        commit_oid = pull_request.head_sha
        diff = pull_request.async_diff(end_commit_oid: commit_oid).sync
        delta = diff.deltas.first
        path = delta.path.dup

        review = pull_request.build_automated_variant_review do |r|
          r.user = bot
          r.head_sha = commit_oid
          r.merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: commit_oid)
        end

        # Comment 1 — no suggestion
        thread1 = ::PullRequestReviewThread.new(
          pull_request_review: review,
          pull_request: pull_request,
        )

        review_comment1 = thread1.build_first_diff_position_comment(
          user: bot,
          body: "AI Finding: potential SQL injection vulnerability detected.",
          diff: diff,
          position: 1,
          path: path,
        )

        arc1 = ::AutomatedReviewComment.new(
          repository_id: repository.id,
          pull_request_id: pull_request.id,
          source: :source_code_scanning_ai,
          resource_id: "ai-finding-seed-no-suggestion-#{Time.now.to_i}",
          message: "This code may be vulnerable to SQL injection. Consider using parameterized queries or an ORM.",
          security_severity: :security_severity_high,
          suggestion_state: :suggestion_state_no_suggestion,
        )

        # Comment 2 — with a suggestion
        thread2 = ::PullRequestReviewThread.new(
          pull_request_review: review,
          pull_request: pull_request,
        )

        review_comment2 = thread2.build_first_diff_position_comment(
          user: bot,
          body: "AI Finding: hardcoded credentials detected. A fix is suggested below.",
          diff: diff,
          position: 1,
          path: path,
        )

        arc2 = ::AutomatedReviewComment.new(
          repository_id: repository.id,
          pull_request_id: pull_request.id,
          source: :source_code_scanning_ai,
          resource_id: "ai-finding-seed-with-suggestion-#{Time.now.to_i + 1}",
          message: "A hardcoded credential was found. Move secrets to environment variables or a secrets manager.",
          security_severity: :security_severity_critical,
          suggestion_state: :suggestion_state_present,
        )
        arc2.suggestion = ::ReviewComments::Suggestion.new(
          commit_sha: commit_oid,
          files: [
            ::ReviewComments::Suggestion::File.new(
              path: path,
              diff_content: "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n@@ -1,3 +1,3 @@\n-password = \"hunter2\"\n+password = ENV.fetch(\"APP_PASSWORD\")\n context\n",
            ),
          ],
        )

        ::PullRequestReview.transaction do
          review_comment1.save!
          arc1.pull_request_review_comment_id = review_comment1.id
          arc1.save!

          review_comment2.save!
          arc2.pull_request_review_comment_id = review_comment2.id
          arc2.save!

          review.comment!
        end
      end

      def create_code_quality_comment
        bot = Apps::Privileged.attribution_only_system_identity_for(:code_quality)
        commit_oid = pull_request.head_sha
        diff = pull_request.async_diff(end_commit_oid: commit_oid).sync
        path = diff.deltas.first.path.dup

        review = pull_request.build_automated_variant_review do |r|
          r.user = bot
          r.head_sha = commit_oid
          r.merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: commit_oid)
        end

        thread = ::PullRequestReviewThread.new(
          pull_request_review: review,
          pull_request: pull_request,
        )

        review_comment = thread.build_first_diff_position_comment(
          user: bot,
          body: "Code Quality: unused variable detected. A fix is suggested below.",
          diff: diff,
          position: 1,
          path: path,
        )

        arc = ::AutomatedReviewComment.new(
          repository_id: repository.id,
          pull_request_id: pull_request.id,
          source: :source_code_quality,
          resource_id: "code-quality-seed-#{Time.now.to_i}",
          message: "An unused variable was detected. Remove it to keep the code clean.",
          severity: :severity_warning,
          suggestion_state: :suggestion_state_present,
        )
        arc.suggestion = ::ReviewComments::Suggestion.new(
          commit_sha: commit_oid,
          files: [
            ::ReviewComments::Suggestion::File.new(
              path: path,
              diff_content: "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n@@ -1,4 +1,3 @@\n def process(data)\n-  unused = nil\n   result = data.map { |x| x * 2 }\n   result\n end\n",
            ),
          ],
        )

        ::PullRequestReview.transaction do
          review_comment.save!
          arc.pull_request_review_comment_id = review_comment.id
          arc.save!
          review.comment!
        end
      end

      def create_copilot_comment
        bot = Apps::Privileged.integration(:copilot_pull_request_reviewer).bot
        commit_oid = pull_request.head_sha
        diff = pull_request.async_diff(end_commit_oid: commit_oid).sync
        path = diff.deltas.first.path.dup

        review = pull_request.build_automated_variant_review do |r|
          r.user = bot
          r.head_sha = commit_oid
          r.merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: commit_oid)
        end

        thread = ::PullRequestReviewThread.new(
          pull_request_review: review,
          pull_request: pull_request,
        )

        review_comment = thread.build_first_diff_position_comment(
          user: bot,
          body: "Copilot: this method lacks input validation and may raise an unhandled exception.",
          diff: diff,
          position: 1,
          path: path,
        )

        arc = ::AutomatedReviewComment.new(
          repository_id: repository.id,
          pull_request_id: pull_request.id,
          source: :source_copilot,
          resource_id: "copilot-seed-#{Time.now.to_i}",
          message: "This method does not validate its input. Consider adding a guard clause or raising a descriptive error for unexpected values.",
          severity: :severity_note,
          suggestion_state: :suggestion_state_no_suggestion,
        )

        ::PullRequestReview.transaction do
          review_comment.save!
          arc.pull_request_review_comment_id = review_comment.id
          arc.save!
          review.comment!
        end
      end

      def sync_automated_review_comment_suggestions
        automated_review_comments = ::AutomatedReviewComment.where(
          repository: repository,
          pull_request: pull_request,
          source: :source_code_scanning,
          fixed_at: nil,
        ).to_a
        if automated_review_comments.empty?
          puts "⚠️ No code scanning ARC comments found. Is turbomock running? Try: script/turbomock"
          return automated_review_comments
        end

        alert_numbers = automated_review_comments.map { |comment| comment.resource_id.to_i }
        ::CodeScanning::AutomatedReviewCommentSuggestionFromTurboscan.sync(pull_request:, alert_numbers:)
      rescue ::CodeScanning::AutofixError => error
        puts "⚠️ Failed to sync automated review comment suggestions: #{error.message}"
        puts "   Is turbomock running? Try: script/turbomock"
        []
      end

      private

      def pr_base
        repository.heads.find(pull_request.base_ref)
      end

      def pr_head
        repository.heads.find(pull_request.head_ref)
      end
    end
  end
end
