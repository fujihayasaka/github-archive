# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Serializers::RepositoryTest < GitHub::TestCase
  include UrlHelper

  setup { @repository = create(:repository, name: "repo", owner: create(:user, login: "owner")) }

  context "#call" do
    context "id" do
      test "returns the repository id" do
        result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

        assert_equal @repository.id, result[:id]
      end
    end

    context "name" do
      test "returns the repository name" do
        result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

        assert_equal "repo", result[:name]
      end
    end

    context "owner" do
      test "returns the repository owner" do
        result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

        assert_equal "owner", result[:owner]
      end
    end

    context "isDiscussionsActive" do
      test "returns the repository discussions_active? value" do
        result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

        assert_equal @repository.discussions_active?, result[:isDiscussionsActive]
      end
    end

    context "hasIssues" do
      test "returns the repository has_issues? value" do
        result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

        assert_equal @repository.has_issues?, result[:hasIssues]
      end
    end

    context "hasSecurityPolicy" do
      context "when the repository has a security policy" do
        test "returns true" do
          RepositoryPreferredFile.create!(repository: @repository, filetype: :security, path: "SECURITY.md", commit_oid: "oid")
          result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

          assert_equal true, result[:hasSecurityPolicy]
        end
      end

      context "when the repository does not have a security policy" do
        test "returns false" do
          result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

          assert_equal false, result[:hasSecurityPolicy]
        end
      end
    end
  end

  context "isThirdParty" do
    context "when the repository is owned by the actions org" do
      test "returns false" do
        @repository = create(:repository, owner: create(:user, login: RepositoryAction::ACTIONS_ORG_NAME))
        result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

        assert_equal false, result[:isThirdParty]
      end
    end

    context "when the repository is not owned by the actions org" do
      test "returns true" do
        result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

        assert_equal true, result[:isThirdParty]
      end
    end
  end

  context "isOrganization" do
    context "when the repository is owned by an organization" do
      test "returns true" do
        @repository = create(:repository, owner: create(:organization))
        result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

        assert_equal true, result[:isOrganization]
      end
    end

    context "when the repository is not owned by an organization" do
      test "returns false" do
        result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

        assert_equal false, result[:isOrganization]
      end
    end
  end

  context "contributorsCount" do
    test "returns the total number of contributors" do
      Marketplace::Repositories::Contributors.any_instance.stubs(:total_count).returns(40)
      result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

      assert_equal 40, result[:contributorsCount]
    end
  end

  context "topContributorsData" do
    test "returns the top contributors data" do
      contributors_data = [{
        src: "monalisa.jpg",
        alt: "monalisa",
        displayLogin: "monalisa"
      }]
      Marketplace::Repositories::Contributors.any_instance.stubs(:top_contributors_data).returns(contributors_data)
      result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

      assert_equal contributors_data, result[:topContributorsData]
    end
  end

  context "openIssuesCount" do
    test "returns the open issue count" do
      @repository.stubs(:open_issue_count_for).returns(10)
      result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

      assert_equal 10, result[:openIssuesCount]
    end
  end

  context "openPullRequestsCount" do
    test "returns the open pull request count" do
      @repository.stubs(:open_pull_request_count_for).returns(5)
      result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

      assert_equal 5, result[:openPullRequestsCount]
    end
  end
end
