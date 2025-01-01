# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Serializers::RepositoryTest < GitHub::TestCase
  include UrlHelper

  setup { @repository = create(:repository, name: "repo", owner: create(:user, login: "owner")) }

  context "#call" do
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

  context "mitLicensePath" do
    context "when the repository has a MIT license" do
      context "when the license has a filepath" do
        test "returns the blob path to the license" do
          create(:repository_license, repository: @repository, license_id: License::LICENSES_TO_IDS["mit"], filepath: "mit_file")
          result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

          assert_equal blob_view_path("mit_file", @repository.default_branch, @repository), result[:mitLicensePath]
        end
      end

      context "when the license does not have a filepath" do
        test "returns the path to the default LICENSE file" do
          Marketplace::Serializers::Repository.any_instance.stubs(:preferred_file_path).returns("/path/to/preferred/file")
          create(:repository_preferred_file, repository: @repository, filetype: :license, path: "LICENSE")
          create(:repository_license, repository: @repository, license_id: License::LICENSES_TO_IDS["mit"])
          result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

          assert_equal "/path/to/preferred/file", result[:mitLicensePath]
        end
      end
    end

    context "when the repository does not have a MIT license" do
      test "returns nil" do
        result = Marketplace::Serializers::Repository.new(repository: @repository, current_user: nil).call

        assert_nil result[:mitLicensePath]
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
end
