# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class UnifiedBatchComments < Seeds::Runner
      DEFAULT_NUM_REGULAR_COMMENTS = 2
      DEFAULT_NUM_SUGGESTION_COMMENTS = 2
      DEFAULT_NUM_HUMAN_REGULAR_COMMENTS = 1
      DEFAULT_NUM_HUMAN_SUGGESTION_COMMENTS = 1
      DEFAULT_HUMAN_REVIEWER_LOGIN = "octocat"

      sig { returns String }
      def self.help
        <<~HELP
        Create a pull request in the given repo with seeded Copilot review comments
        (a mix of regular comments and comments with suggestions) plus a separate
        human-authored review covering the same shapes, so the unified batch flow
        can mix automated + human suggestions.

        Options:
          --repo, -r               NWO of the repository to seed (e.g. monalisa/smile). Required.
          --num_regular            Number of regular Copilot comments to create.
                                   Defaults to #{DEFAULT_NUM_REGULAR_COMMENTS}.
          --num_suggestions        Number of Copilot comments with suggestions to create.
                                   Defaults to #{DEFAULT_NUM_SUGGESTION_COMMENTS}.
          --num_human_regular      Number of human-authored regular review comments.
                                   Defaults to #{DEFAULT_NUM_HUMAN_REGULAR_COMMENTS}.
          --num_human_suggestions  Number of human-authored review comments containing
                                   a ```suggestion block. Defaults to #{DEFAULT_NUM_HUMAN_SUGGESTION_COMMENTS}.
          --human_login            Login of the user to author the human review.
                                   Defaults to "#{DEFAULT_HUMAN_REVIEWER_LOGIN}" (created if missing).
          --skip_flag_setup        Skip enabling Copilot code-review feature flags and
                                   writing the prx_files enrollment. Useful for repeat
                                   runs once the codespace is already set up. Defaults to false.

        Note: without --skip_flag_setup, this runner enables feature flags GLOBALLY in
        the current environment (the listed flags include default-flip flags that have
        no per-actor meaning). Safe in a personal codespace; do not run on shared
        environments unless you intend to change the experience for everyone on the box.

        Each run creates a fresh branch and PR; re-running accumulates PRs rather than
        updating the previous one. `--skip_flag_setup` only short-circuits the flag and
        enrollment setup — it does not reuse a prior PR.

        Example:
          bin/seed unified_batch_comments -r monalisa/smile --num_regular 3 --num_suggestions 1
          bin/seed unified_batch_comments -r monalisa/smile --num_human_regular 2 --num_human_suggestions 2
          bin/seed unified_batch_comments -r monalisa/smile --skip_flag_setup
        HELP
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def self.run(options = {})
        new(options).run
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def initialize(options)
        @nwo = options[:repo].to_s
        @num_regular = (options[:num_regular] || DEFAULT_NUM_REGULAR_COMMENTS).to_i
        @num_suggestions = (options[:num_suggestions] || DEFAULT_NUM_SUGGESTION_COMMENTS).to_i
        @num_human_regular = (options[:num_human_regular] || DEFAULT_NUM_HUMAN_REGULAR_COMMENTS).to_i
        @num_human_suggestions = (options[:num_human_suggestions] || DEFAULT_NUM_HUMAN_SUGGESTION_COMMENTS).to_i
        @human_login = (options[:human_login] || DEFAULT_HUMAN_REVIEWER_LOGIN).to_s
        @skip_flag_setup = !!options[:skip_flag_setup]
      end

      sig { void }
      def run
        raise RunnerError, "--repo is required (NWO, e.g. monalisa/smile)" if @nwo.empty?
        raise RunnerError, "--num_regular must be >= 0" if @num_regular.negative?
        raise RunnerError, "--num_suggestions must be >= 0" if @num_suggestions.negative?
        raise RunnerError, "--num_human_regular must be >= 0" if @num_human_regular.negative?
        raise RunnerError, "--num_human_suggestions must be >= 0" if @num_human_suggestions.negative?
        total = @num_regular + @num_suggestions + @num_human_regular + @num_human_suggestions
        raise RunnerError, "must create at least one comment" if total.zero?

        repository = ::Repository.with_name_with_owner(@nwo)
        raise RunnerError, "Repository #{@nwo} not found. Create it first (e.g. with `bin/seed pull_requests`)." unless repository

        author = author_for(repository)
        puts "➡️  Using author @#{author.display_login} for repository #{repository.nwo}"

        if @skip_flag_setup
          puts "⏭️  Skipping feature flag enablement and prx_files enrollment (--skip_flag_setup)"
        else
          enable_feature_flags(author)
          puts "✅ Globally enabled #{FEATURE_FLAGS.size} feature flags in this environment + wrote prx_files enrollment for @#{author.display_login}"
          puts "   (re-run with --skip_flag_setup to skip on subsequent runs)"
        end

        ensure_integration
        puts "✅ copilot_pull_request_reviewer integration ready"

        pull_request = create_pull_request(repository, author)
        puts "✅ Created PR ##{pull_request.number}: #{pull_request.title}"

        if (@num_regular + @num_suggestions).positive?
          create_copilot_review(repository, pull_request)
          puts "✅ Created #{@num_regular} regular and #{@num_suggestions} suggestion Copilot review comments"
        end

        if (@num_human_regular + @num_human_suggestions).positive?
          human_reviewer = ensure_human_reviewer(repository)
          create_human_review(repository, pull_request, human_reviewer)
          puts "✅ Created #{@num_human_regular} regular and #{@num_human_suggestions} suggestion human review comments by @#{human_reviewer.display_login}"
        end

        puts
        puts "PR is ready:"
        puts "    http://#{GitHub.host_name}/#{repository.nwo}/pull/#{pull_request.number}/files"
        puts
      end

      private

      # Feature flags required to exercise the full Copilot code-review UI on the
      # seeded PR: the React Files Changed experience, the unified batch suggestions
      # flow, the "Fix with Copilot" buttons, and the agentic suggestion refresh.
      FEATURE_FLAGS = T.let(%w[
        copilot_code_review_findings_ui
        ccr_automated_review_comment_migration
        prx_files
        prx_files_opt_out_by_default
        copilot_code_review_batch_apply_suggestions
        copilot_code_review_reply_hint
        copilot_swe_agent
        copilot_swe_agent_public_repos
        copilot_swe_agent_enable_repos_by_default
        ccr_implement_suggestion_refresh
        ccr_implement_suggestion_refresh_commit
        updated_pull_request_header
        unified_batch_pr_comments
      ].freeze, T::Array[String])

      sig { params(author: ::User).void }
      def enable_feature_flags(author)
        FEATURE_FLAGS.each do |flag|
          Seeds::Objects::FeatureFlag.enable(feature_flag: flag, diagnostic_io: StringIO.new)
        end

        # `prx_files_opt_out_by_default` only flips the default for users without
        # an explicit enrollment record. If author already has a row that opts
        # them out (or predates the default flip), the new React Files Changed
        # experience stays hidden behind `?new_files_changed=true`. Writing an
        # explicit enrolled=true row makes it stick on plain `/files`.
        feature = ::Feature.find_by(slug: "prx_files")
        ::FeatureEnrollment.set_for(feature: feature, enrollee: author, enrolled: true) if feature
      end

      sig { params(repository: ::Repository).returns(::User) }
      def author_for(repository)
        candidates = []
        candidates << repository.owner if repository.owner&.user?
        if repository.in_organization?
          candidates.concat(T.must(repository.organization).admins.to_a)
        end
        candidates << Seeds::Objects::User.monalisa
        author = candidates.compact.first
        raise RunnerError, "Could not determine a user to author the PR for #{repository.nwo}" unless author
        author
      end

      sig { void }
      def ensure_integration
        Seeds::Objects::Integration.create_copilot_pull_request_reviewer_integration
        Apps::Privileged::Registry.instance.reload_caches!
      end

      sig { params(repo: ::Repository, author: ::User).returns(::PullRequest) }
      def create_pull_request(repo, author)
        total = @num_regular + @num_suggestions + @num_human_regular + @num_human_suggestions
        head_ref_name = "unified-batch-seed-#{SecureRandom.hex(4)}"
        base_oid = repo.default_oid
        raise RunnerError, "Repository #{repo.nwo} has no default branch. Push an initial commit first." unless base_oid

        head_ref = repo.refs.create("refs/heads/#{head_ref_name}", base_oid, author)
        head_ref.append_commit({ message: "Add files for unified batch comments seed", committer: author, author: author }, author) do |changes|
          total.times do |i|
            changes.add(file_path(i), file_content(i))
          end
        end

        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Seeded PR with Copilot + human review comments",
          body: "Generated by `bin/seed unified_batch_comments` with " \
            "#{@num_regular}/#{@num_suggestions} Copilot regular/suggestion and " \
            "#{@num_human_regular}/#{@num_human_suggestions} human regular/suggestion comments.",
          head: head_ref_name,
          base: repo.default_branch,
        )
      end

      sig { params(repo: ::Repository, pull_request: ::PullRequest).void }
      def create_copilot_review(repo, pull_request)
        bot = Apps::Privileged.integration(:copilot_pull_request_reviewer).bot
        commit_oid = pull_request.head_sha

        sample_diff = pull_request.async_diff(end_commit_oid: commit_oid).sync
        total = @num_regular + @num_suggestions
        if sample_diff.deltas.size < total
          raise RunnerError,
            "Expected at least #{total} diff deltas on PR ##{pull_request.number} but found " \
              "#{sample_diff.deltas.size}. Cannot place one Copilot comment per delta."
        end

        # Pre-add all paths to the diff before building comments. Building a comment
        # triggers diff_entry which loads the diff entries; once loaded, add_path raises
        # AlreadyLoaded for any path not already registered.
        all_paths = total.times.map { |i| T.must(sample_diff.deltas[i]).path.dup }
        sample_diff.add_paths(all_paths)

        review = pull_request.build_automated_variant_review do |r|
          r.user = bot
          r.head_sha = commit_oid
          r.merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: commit_oid)
        end

        comments_with_arcs = []

        @num_regular.times do |i|
          path = all_paths[i]
          comments_with_arcs << build_regular_comment(repo, pull_request, review, bot, sample_diff, path, i)
        end

        @num_suggestions.times do |i|
          delta_index = @num_regular + i
          path = all_paths[delta_index]
          comments_with_arcs << build_suggestion_comment(repo, pull_request, review, bot, sample_diff, path, commit_oid, i)
        end

        ::PullRequestReview.transaction do
          comments_with_arcs.each do |comment, arc|
            comment.save!
            arc.pull_request_review_comment_id = comment.id
            arc.save!
          end
          review.comment!
        end
      end

      sig do
        params(
          repo: ::Repository,
          pull_request: ::PullRequest,
          review: ::PullRequestReview,
          bot: ::User,
          diff: T.untyped,
          path: String,
          index: Integer,
        ).returns([::PullRequestReviewComment, ::AutomatedReviewComment])
      end
      def build_regular_comment(repo, pull_request, review, bot, diff, path, index)
        thread = ::PullRequestReviewThread.new(
          pull_request_review: review,
          pull_request: pull_request,
        )

        template = REGULAR_COMMENT_TEMPLATES[index % REGULAR_COMMENT_TEMPLATES.size]

        comment = thread.build_first_diff_position_comment(
          user: bot,
          body: "**Copilot:** #{T.must(template)[:body]}\n\n_#{Faker::Lorem.sentence(word_count: 8)}_",
          diff: diff,
          position: 1,
          path: path,
        )

        arc = ::AutomatedReviewComment.new(
          repository_id: repo.id,
          pull_request_id: pull_request.id,
          source: :source_copilot,
          resource_id: "unified-batch-seed-regular-#{index}-#{Time.now.to_i}-#{SecureRandom.hex(3)}",
          message: T.must(template)[:message],
          severity: T.must(template)[:severity],
          suggestion_state: :suggestion_state_no_suggestion,
        )

        [comment, arc]
      end

      sig do
        params(
          repo: ::Repository,
          pull_request: ::PullRequest,
          review: ::PullRequestReview,
          bot: ::User,
          diff: T.untyped,
          path: String,
          commit_oid: String,
          index: Integer,
        ).returns([::PullRequestReviewComment, ::AutomatedReviewComment])
      end
      def build_suggestion_comment(repo, pull_request, review, bot, diff, path, commit_oid, index)
        thread = ::PullRequestReviewThread.new(
          pull_request_review: review,
          pull_request: pull_request,
        )

        template = SUGGESTION_TEMPLATES[index % SUGGESTION_TEMPLATES.size]

        body = +"**Copilot:** #{T.must(template)[:body]}\n\n"
        body << "_#{Faker::Lorem.sentence(word_count: 10)}_\n\n"
        body << "```suggestion\n#{T.must(template)[:replacement]}\n```\n"

        comment = thread.build_first_diff_position_comment(
          user: bot,
          body: body,
          diff: diff,
          position: 1,
          path: path,
        )

        arc = ::AutomatedReviewComment.new(
          repository_id: repo.id,
          pull_request_id: pull_request.id,
          source: :source_copilot,
          resource_id: "unified-batch-seed-suggestion-#{index}-#{Time.now.to_i}-#{SecureRandom.hex(3)}",
          message: T.must(template)[:message],
          severity: T.must(template)[:severity],
          suggestion_state: :suggestion_state_present,
        )
        arc.suggestion = ::ReviewComments::Suggestion.new(
          commit_sha: commit_oid,
          files: [
            ::ReviewComments::Suggestion::File.new(
              path: path,
              diff_content: suggestion_diff(path, T.must(template)[:replacement]),
            ),
          ],
        )

        [comment, arc]
      end

      sig { params(repository: ::Repository).returns(::User) }
      def ensure_human_reviewer(repository)
        reviewer = ::User.find_by(login: @human_login)
        if reviewer.nil?
          # Use a login-scoped email to avoid collisions with other seed scripts
          # that may already own e.g. octocat@github.com on a differently-logged user.
          reviewer = Seeds::Objects::User.create(
            login: @human_login,
            email: "#{@human_login}+unified-batch-seed@github.com",
          )
          raise RunnerError, "Could not create human reviewer @#{@human_login}" unless reviewer
          puts "➡️  Created human reviewer @#{reviewer.login} (id=#{reviewer.id})"
        else
          puts "➡️  Reusing existing user @#{reviewer.login} (id=#{reviewer.id}) as the human reviewer"
        end

        # User-owned repos: add the reviewer as a collaborator so the comment shows
        # up with appropriate badges and so suggestions they author can be applied
        # by the viewer (push perms on the head ref). Org-owned repos: add the
        # reviewer as a member of the org so the review_threads association loads.
        if repository.in_organization?
          T.must(repository.organization).add_member(reviewer)
          repository.add_member(reviewer) unless repository.member?(reviewer)
        elsif !repository.member?(reviewer)
          repository.add_member(reviewer)
        end

        reviewer
      end

      sig { params(repo: ::Repository, pull_request: ::PullRequest, reviewer: ::User).void }
      def create_human_review(repo, pull_request, reviewer)
        commit_oid = pull_request.head_sha

        sample_diff = pull_request.async_diff(end_commit_oid: commit_oid).sync
        offset = @num_regular + @num_suggestions
        total_needed = offset + @num_human_regular + @num_human_suggestions
        if sample_diff.deltas.size < total_needed
          raise RunnerError,
            "Expected at least #{total_needed} diff deltas on PR ##{pull_request.number} but found " \
              "#{sample_diff.deltas.size}. Cannot place one human comment per delta."
        end

        # Pre-add all paths we'll use so add_path doesn't raise AlreadyLoaded
        # after the first comment's diff_entry triggers entries loading.
        human_count = @num_human_regular + @num_human_suggestions
        all_paths = human_count.times.map { |i| T.must(sample_diff.deltas[offset + i]).path.dup }
        sample_diff.add_paths(all_paths)

        review = pull_request.reviews.build(
          user: reviewer,
          head_sha: commit_oid,
          body: "**@#{reviewer.display_login}:** #{Faker::Lorem.sentence(word_count: 8)}",
        )

        comments = []

        @num_human_regular.times do |i|
          path = all_paths[i]
          comments << build_human_regular_comment(pull_request, review, reviewer, sample_diff, path, i)
        end

        @num_human_suggestions.times do |i|
          path = all_paths[@num_human_regular + i]
          comments << build_human_suggestion_comment(pull_request, review, reviewer, sample_diff, path, i)
        end

        ::PullRequestReview.transaction do
          comments.each(&:save!)
          review.comment!
        end
      end

      sig do
        params(
          pull_request: ::PullRequest,
          review: ::PullRequestReview,
          user: ::User,
          diff: T.untyped,
          path: String,
          index: Integer,
        ).returns(::PullRequestReviewComment)
      end
      def build_human_regular_comment(pull_request, review, user, diff, path, index)
        thread = ::PullRequestReviewThread.new(
          pull_request_review: review,
          pull_request: pull_request,
        )

        template = HUMAN_REGULAR_TEMPLATES[index % HUMAN_REGULAR_TEMPLATES.size]
        body = "#{T.must(template)[:body]}\n\n_#{Faker::Lorem.sentence(word_count: 10)}_"

        thread.build_first_diff_position_comment(
          user: user,
          body: body,
          diff: diff,
          position: 1,
          path: path,
        )
      end

      sig do
        params(
          pull_request: ::PullRequest,
          review: ::PullRequestReview,
          user: ::User,
          diff: T.untyped,
          path: String,
          index: Integer,
        ).returns(::PullRequestReviewComment)
      end
      def build_human_suggestion_comment(pull_request, review, user, diff, path, index)
        thread = ::PullRequestReviewThread.new(
          pull_request_review: review,
          pull_request: pull_request,
        )

        template = HUMAN_SUGGESTION_TEMPLATES[index % HUMAN_SUGGESTION_TEMPLATES.size]
        body = +"#{T.must(template)[:body]}\n\n"
        body << "```suggestion\n#{T.must(template)[:replacement]}\n```\n"

        thread.build_first_diff_position_comment(
          user: user,
          body: body,
          diff: diff,
          position: 1,
          path: path,
        )
      end

      sig { params(path: String, replacement: String).returns(String) }
      def suggestion_diff(path, replacement)
        "diff --git a/#{path} b/#{path}\n" \
          "--- a/#{path}\n" \
          "+++ b/#{path}\n" \
          "@@ -1,3 +1,3 @@\n" \
          "-TODO: line 1\n" \
          "+#{replacement}\n" \
          " TODO: line 2\n" \
          " TODO: line 3\n"
      end

      sig { params(index: Integer).returns(String) }
      def file_path(index)
        "unified-batch-seed/#{Faker::File.dir(segment_count: 1)}/file_#{index}_#{Faker::Lorem.word}.txt"
      end

      sig { params(index: Integer).returns(String) }
      def file_content(index)
        flavor = Faker::Lorem.sentence(word_count: 6)
        "TODO: line 1\n" \
          "TODO: line 2\n" \
          "TODO: line 3\n" \
          "\n" \
          "File ##{index}\n" \
          "Notes: #{flavor}\n" \
          "#{Faker::Lorem.paragraph(sentence_count: 3)}\n"
      end

      # A rotating pool of realistic-sounding Copilot comments without suggestions.
      # Each comment is paired with a longer ARC `message` and a severity so the seeded
      # data covers a range of severities and tones.
      REGULAR_COMMENT_TEMPLATES = T.let([
        {
          body: "Consider validating the input here before passing it downstream.",
          message: "Inputs to this function are not validated, which can cause downstream errors when " \
            "unexpected values are passed in. Consider adding a guard clause or schema validation.",
          severity: :severity_note,
        },
        {
          body: "This block looks like a good candidate for extraction into a helper.",
          message: "The logic in this block is repeated in a few places. Extracting it into a small " \
            "helper would reduce duplication and make the intent clearer.",
          severity: :severity_nit,
        },
        {
          body: "Potential nil dereference if the upstream lookup fails.",
          message: "The result of the upstream lookup can be nil. Calling a method on it without a " \
            "guard may raise a NoMethodError at runtime.",
          severity: :severity_warning,
        },
        {
          body: "This loop runs in O(n²); consider using a Set for membership checks.",
          message: "The nested membership check turns this loop into O(n²). For larger inputs, " \
            "converting the outer collection to a Set first would make it O(n).",
          severity: :severity_medium,
        },
        {
          body: "Missing test coverage for the new branch.",
          message: "There is no test exercising the new else branch. Consider adding a unit test so " \
            "this behavior is locked in.",
          severity: :severity_note,
        },
        {
          body: "Magic number — consider naming this constant.",
          message: "Replacing the bare numeric literal with a named constant would make the intent " \
            "self-documenting and easier to tweak later.",
          severity: :severity_nit,
        },
        {
          body: "This rescue swallows all exceptions silently.",
          message: "A bare rescue without re-raising or logging can hide bugs. Consider narrowing the " \
            "rescued class or at least logging the error.",
          severity: :severity_high,
        },
        {
          body: "Naming nit: this variable doesn't describe what it holds.",
          message: "A more descriptive name would make this code easier to read for future maintainers.",
          severity: :severity_nit,
        },
      ].freeze, T::Array[T::Hash[Symbol, T.untyped]])

      # A rotating pool of suggestion comments. Each entry provides the comment body,
      # ARC message, severity, and the single replacement line that the suggestion will
      # insert in place of "TODO: line 1" in the seeded file.
      SUGGESTION_TEMPLATES = T.let([
        {
          body: "Replace the placeholder line with the implementation we discussed.",
          message: "The TODO placeholder should be replaced with the actual implementation so the " \
            "feature behaves as documented.",
          severity: :severity_warning,
          replacement: "DONE: implemented as discussed in the design doc",
        },
        {
          body: "Move this hardcoded value into configuration.",
          message: "Hardcoding this value makes it harder to tune per-environment. Pull it from " \
            "configuration instead.",
          severity: :severity_medium,
          replacement: "value = Rails.configuration.x.my_feature.threshold",
        },
        {
          body: "Use the canonical helper so behavior stays consistent across the app.",
          message: "There is an existing helper that already covers this case. Using it will keep the " \
            "behavior consistent with the rest of the codebase.",
          severity: :severity_note,
          replacement: "result = MyDomain::Helpers.canonical_form(input)",
        },
        {
          body: "Tighten this guard to avoid leaking nil downstream.",
          message: "Returning early on nil here will keep the downstream callers simpler and avoid " \
            "the `NoMethodError on NilClass` we keep hitting in this area.",
          severity: :severity_high,
          replacement: "return :noop unless input.present?",
        },
        {
          body: "Prefer a frozen constant over rebuilding this list on every call.",
          message: "This list is rebuilt on every call. Hoisting it into a frozen constant avoids " \
            "needless allocations.",
          severity: :severity_nit,
          replacement: "ALLOWED_VALUES = %i[alpha beta gamma].freeze",
        },
        {
          body: "Add explicit timeouts to this network call.",
          message: "Network calls without an explicit timeout can hang indefinitely under failure. " \
            "Pass an explicit `open_timeout` and `read_timeout`.",
          severity: :severity_high,
          replacement: "client = Faraday.new(url) { |f| f.options.timeout = 5; f.options.open_timeout = 2 }",
        },
      ].freeze, T::Array[T::Hash[Symbol, T.untyped]])

      # Human-authored regular review comments. Casual phrasing — these mimic a
      # teammate dropping a quick note on a PR rather than the more structured
      # Copilot output.
      HUMAN_REGULAR_TEMPLATES = T.let([
        { body: "nit: can we rename this for clarity?" },
        { body: "Could you add a comment explaining why this branch exists?" },
        { body: "Have we considered the perf impact here? This runs on every render." },
        { body: "Quick question: is this safe when the upstream call times out?" },
        { body: "Heads up — this duplicates logic from another helper. Worth consolidating?" },
        { body: "Could we add a test that exercises this edge case?" },
      ].freeze, T::Array[T::Hash[Symbol, T.untyped]])

      # Human-authored review comments containing a fenced `suggestion` block —
      # these exercise the classic "Add suggestion to batch" flow.
      HUMAN_SUGGESTION_TEMPLATES = T.let([
        {
          body: "Tiny tweak — let's use the helper here so it stays consistent:",
          replacement: "value = MyDomain::Helpers.canonical_form(input)",
        },
        {
          body: "We standardized on this form in #1234 — could you adopt it here?",
          replacement: "return early_response if input.blank?",
        },
        {
          body: "Suggesting a more descriptive name:",
          replacement: "DEFAULT_REQUEST_TIMEOUT_SECONDS = 5",
        },
        {
          body: "Pretty sure this is the safer order of operations:",
          replacement: "ensure_authorized!; perform_action",
        },
      ].freeze, T::Array[T::Hash[Symbol, T.untyped]])
    end
  end
end
