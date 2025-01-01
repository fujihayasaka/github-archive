# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class CodeReviewGenerator
    # Public: Generate a code review from Copilot for the given pull request.
    # requestor - User manually requesting a review from Copilot, or PR author for automatic reviews.
    sig { params(repo: Repository, pull: PullRequest, requestor: User).void }
    def initialize(repo:, pull:, requestor:)
      @repo = repo
      @pull = pull
      @requestor = requestor
    end

    # Public: Generate a code review from Copilot for the given pull request.
    # This assumes that feature flag and license checks have already passed.
    sig { void }
    def generate
      return if repo.nil? || requestor.nil? || pull.nil?

      include_full_files = requestor.feature_enabled?(:copilot_reviews_include_full_files)
      pr_ref = T.must(Copilot::PullRequests::CodeReviewReferenceSerializer.new.to_hash(pull, include_diff: true, include_full_files: include_full_files))
      # Load coding guideline references
      guidelines = Copilot::CodingGuideline.references_for(repo.id)

      # Mint a copilot chat app token so we can invoke CAPI on behalf of the user
      app = ::Apps::Internal.integration(:copilot_pull_request_reviewer)
      new_access = app.grant(requestor)
      access, _ = new_access.redeem(extended_expiry: true)
      token = Copilot::DecryptedToken.from(access)

      capi = Copilot::User::CopilotApi.new(
        requestor,
        integration_id: CopilotAPI::COPILOT_4_PRS_INTEGRATION_ID,
        session: nil, # There won't ever be a user session
        real_ip: nil, # Same as above
        token: token,
      )
      resp = capi.create_code_review(
        references: [pr_ref].concat(guidelines),
        role: "user",
        experiment_headers: {
          "X-Experiment-Code-Review-Stream-Review" => "true",
        },
      )

      submit_review(repo, pull, pr_ref, resp)
    end

    private

    attr_reader :repo, :pull, :requestor

    def submit_review(repo, pull, pr_ref, resp)
      ref_data = pr_ref[:data]
      commit_id = ref_data[:headRevision]
      diff_start_commit_oid = ref_data[:comparisonStartOID]
      diff_end_commit_oid = ref_data[:comparisonEndOID]
      diff_base_commit_oid = ref_data[:comparisonBaseOID]

      pr_comments = resp[:copilot_references].filter_map do |ref|
        next unless ref[:type] == "github.generated-pull-request-comment"

        # path, line, body, side
        ref[:data]
      end

      PullRequests::Copilot::CodeReviewCreator.new(
        pull:,
        repo:,
        commit_id:,
        comments: pr_comments,
        diff_start_commit_oid:,
        diff_end_commit_oid:,
        diff_base_commit_oid:,
        body: pr_comments.any? ? code_review_with_comments_body(repo) : nil,
      ).create
    end

    def code_review_with_comments_body(repo)
      return unless repo.owner_display_login == "github"
      return unless GitHub.flipper[:copilot_code_reviews_internal_feedback_advert].enabled?

      <<~EOS
        🎁 **Share your feedback on Copilot Code Reviews and win up to $300!**
        * Complete this [short 3 minute survey](https://survey3.medallia.com/?code-reviews) and tell us how we can improve Copilot Code Reviews for you and your team. You will receive $20 for completing the survey and be entered into a draw for a $300 Visa gift card.
        * Leave feedback on Copilot's comments with the 👍/👎 buttons, and you could be one of 3 Hubbers to win a $50 GitHub Shop credit.
      EOS
    end
  end
end
