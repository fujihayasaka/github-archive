# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests::Copilot
  class CodeReviewBodyMessageTipGeneratorTest < GitHub::TestCase

    G = PullRequests::Copilot::CodeReviewBodyMessageTipGenerator
    def setup
      @owner = create(:paid_user)
      @org = create(:organization, admin: @owner)
      @repo = create(:private_repository, owner: @org, from_example: :with_tokens)
      example_repo :pull_request_source, @repo
      @pull = PullRequest.create_for! @repo, user: @owner, base: "master", head: "master-forward-2", title: "asdf", body: "asdf"
      @comments = []

      # The conditions where these are turned on are tested explicitly, but these stubs are set
      # for every test to reduce the noise in the test assertions.
      Copilot::CodingGuideline.stubs(:references_for).returns([{}, {}])
      @pull.stubs(:base_branch_rule_evaluator).returns(stub(automatic_copilot_code_review_enabled?: true))
      disable_feature_flag(:copilot_code_review_vs_code_tip)
      disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @org)
    end

    test "tip_for always includes 'Tip:' and the learn more link" do
      result = PullRequests::Copilot::CodeReviewBodyMessageTipGenerator.tip_for(@pull, @repo, @comments)
      assert_includes result, "Tip:"
      assert_includes result, PullRequests::Copilot::CodeReviewBodyMessageTipGenerator::LEARN_MORE
    end

    test "tip_for with no comments" do
      assert_response_is_one_of([G::LANGUAGES, G::CONFIDENCE]) do
        PullRequests::Copilot::CodeReviewBodyMessageTipGenerator.tip_for(@pull, @repo, @comments)
      end
    end

    test "tip_for with comments" do
      assert_response_is_one_of([G::WITH_COMMENTS, G::LANGUAGES, G::CONFIDENCE]) do
        @comments = [{ body: "Great job!" }]
        PullRequests::Copilot::CodeReviewBodyMessageTipGenerator.tip_for(@pull, @repo, @comments)
      end
    end

    test "tip_for with automatic_copilot_code_review enabled" do
      assert_response_is_one_of([G::LANGUAGES, G::CONFIDENCE]) do
        @pull.stubs(:base_branch_rule_evaluator).returns(stub(automatic_copilot_code_review_enabled?: true))
        PullRequests::Copilot::CodeReviewBodyMessageTipGenerator.tip_for(@pull, @repo, @comments)
      end
    end

    test "tip_for with automatic_copilot_code_review disabled" do
      assert_response_is_one_of([G::AUTO_REVIEWS, G::LANGUAGES, G::CONFIDENCE]) do
        @pull.stubs(:base_branch_rule_evaluator).returns(stub(automatic_copilot_code_review_enabled?: false))
        PullRequests::Copilot::CodeReviewBodyMessageTipGenerator.tip_for(@pull, @repo, @comments)
      end
    end

    test "tip_for with copilot_reviews_automatic_pull_request_review enabled" do
      @pull.stubs(:base_branch_rule_evaluator).returns(stub(automatic_copilot_code_review_enabled?: false))
      enable_feature_flag(:copilot_reviews_automatic_pull_request_review, @org)
      assert_response_is_one_of([G::LANGUAGES, G::CONFIDENCE]) do
        PullRequests::Copilot::CodeReviewBodyMessageTipGenerator.tip_for(@pull, @repo, @comments)
      end
    end

    test "tip_for with copilot_reviews_automatic_pull_request_review disabled" do
      @pull.stubs(:base_branch_rule_evaluator).returns(stub(automatic_copilot_code_review_enabled?: false))
      assert_response_is_one_of([G::AUTO_REVIEWS, G::LANGUAGES, G::CONFIDENCE]) do
        PullRequests::Copilot::CodeReviewBodyMessageTipGenerator.tip_for(@pull, @repo, @comments)
      end
    end

    test "tip_for with copilot_code_review_vs_code_tip feature flag enabled" do
      assert_response_is_one_of([G::LANGUAGES, G::CONFIDENCE, G::VS_CODE]) do
        enable_feature_flag(:copilot_code_review_vs_code_tip)
        PullRequests::Copilot::CodeReviewBodyMessageTipGenerator.tip_for(@pull, @repo, @comments)
      end
    end

    test "tip_for with copilot_code_review_vs_code_tip feature flag disabled" do
      assert_response_is_one_of([G::LANGUAGES, G::CONFIDENCE]) do
        PullRequests::Copilot::CodeReviewBodyMessageTipGenerator.tip_for(@pull, @repo, @comments)
      end
    end

    def assert_response_is_one_of(expected, max_tries: 100)
      tries = 0
      results = expected.each_with_object(0).to_h # rubocop:disable Lint/EachWithObjectArgument
      while tries < max_tries
        result = yield
        match = expected.find { result =~ /#{_1}/ }
        if match
          results[match] += 1
        else
          assert false, "Expected result to match one of #{expected}, but it was:\n '#{result}'"
        end
        break if results.values.all? { _1 > 0 }
        tries += 1
      end
      expected.each do |e|
        assert results[e] > 0, "Expected \"#{e}\" to be returned at least once, but it was returned #{results[e]} times.\nResults:\n#{results.map { |k, v| "'#{k}': #{v} times" }.join("\n")}"
      end
    end
  end
end
