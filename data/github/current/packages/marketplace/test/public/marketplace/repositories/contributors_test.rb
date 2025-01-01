# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Repositories::ContributorsTest < GitHub::TestCase
  include AvatarHelper

  setup { @repository = build(:repository) }

  def setup_repo_with_contributors
    @contributor1 = build(:user)
    @contributor2 = build(:user)
    @contributor3 = build(:user)
    create(:commit_contribution, :with_summaries, repository: @repository, user: @contributor1, commit_count: 5)
    create(:commit_contribution, :with_summaries, repository: @repository, user: @contributor2, commit_count: 3)
    create(:commit_contribution, :with_summaries, repository: @repository, user: @contributor3, commit_count: 1)
  end

  context "#total_count" do
    test "returns the count of contributors" do
      setup_repo_with_contributors
      result = Marketplace::Repositories::Contributors.new(@repository, nil).total_count

      assert_equal 3, result
    end
  end

  context "#top_contributors_data" do
    context "when the repository has top contributors" do
      test "returns the top contributors src, alt, and display login up to the contributor limit" do
        setup_repo_with_contributors
        expected_data = [
          {
            src: avatar_url_for(@contributor1, 64),
            alt: alt_text(@contributor1),
            displayLogin: @contributor1.display_login
          },
          {
            src: avatar_url_for(@contributor2, 64),
            alt: alt_text(@contributor2),
            displayLogin: @contributor2.display_login
          }
        ]

        Marketplace::Repositories::Contributors.stub_const(:CONTRIBUTOR_LIMIT, 2) do
          result = Marketplace::Repositories::Contributors.new(@repository, nil).top_contributors_data
          assert_equal expected_data, result
        end
      end
    end

    context "when the repository has no top contributors" do
      test "returns an empty array" do
        Marketplace::Repositories::Contributors.stub_const(:CONTRIBUTOR_LIMIT, 2) do
          result = Marketplace::Repositories::Contributors.new(@repository, nil).top_contributors_data
          assert_equal [], result
        end
      end
    end
  end
end
