# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Payloads::ShowActionTest < GitHub::TestCase
  fixtures do
    @category1 = create(:marketplace_category)
    @category2 = create(:marketplace_category)
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @action = create(:repository_action,
                     categories: [@category1, @category2],
                     dependents_count: 4,
                     security_email: "security@email.com",
                     slug: "action-slug",
                     repository: @repo)
    @current_user = create(:user)
  end

  setup do
    Marketplace::Serializers::Action.stubs(:svg_icon_string).returns("sweet svg")
    Marketplace::Actions::GetReadmeHtml.stubs(:new).returns(stub(call: "<div/>"))
    Marketplace::Serializers::Repository.any_instance.stubs(:call).returns({
      id: 1,
      name: "repo",
      owner: "owner",
      isDiscussionsActive: true,
      hasIssues: true,
      hasSecurityPolicy: true,
      isThirdParty: true,
      isOrganization: true,
      contributorsCount: 5,
      topContributorsData: [],
      openIssuesCount: 0,
      openPullRequestsCount: 0
    })
    Marketplace::Serializers::ReleaseData.any_instance.stubs(:call).returns({
      selectedRelease: { "tagName": "selected", "isPrerelease": true },
      latestRelease: { "tagName": "latest", "isPrerelease": true },
      releases: [{ "tagName": "release", "isPrerelease": true }]
    })
    Marketplace::Serializers::StarData.any_instance.stubs(:call).returns({
      starredByCurrentUser: true,
      currentUserAbleToStar: true,
      currentUserEnterpriseName: "enterprise"
    })
    @payload = Marketplace::Payloads::ShowAction.new(
      repository_action: @action,
      selected_version: nil,
      current_user: @current_user,
      selected_release: nil,
      releases: Release.none,
      latest_release: build(:release),
      logged_in: false,
      emu_contribution_blocked: false
    ).call
  end

  context "#call" do
    test "correctly serializes the action data" do
      action_result = @payload[:action]
      expected_categories = [
        { name: @category1.name, slug: @category1.slug },
        { name: @category2.name, slug: @category2.slug }
      ].sort_by { |hash| hash[:name] }

      assert_equal expected_categories, action_result[:categories].sort_by { |hash| hash[:name] }
      assert_equal @action.color, action_result[:color]
      assert_equal @action.description + "\n", action_result[:description]
      assert_equal "sweet svg", action_result[:iconSvg]
      assert_equal @action.id, action_result[:id]
      assert_equal @action.verified_owner?, action_result[:isVerifiedOwner]
      assert_equal @action.name, action_result[:name]
      assert_equal @action.owner&.display_login, action_result[:ownerLogin]
      assert_equal @action.slug, action_result[:slug]
      assert_equal @action.repository&.stargazer_count, action_result[:stars]
      assert_equal Marketplace::Types::ListingTypes::RepositoryAction.serialize, action_result[:type]
      assert_equal @action.external_uses_path_prefix, action_result[:externalUsesPathPrefix]
      assert_equal @action.global_relay_id, action_result[:globalRelayId]
    end

    test "hash includes the readme data" do
      assert_equal "<div/>", @payload[:readmeHtml]
    end

    test "hash includes the help url" do
      assert_equal "#{GitHub.help_url}/articles/about-readmes/", @payload[:helpUrl]
    end

    test "correctly serializes the repository data" do
      repository_result = @payload[:repository]

      assert_equal 1, repository_result[:id]
      assert_equal "repo", repository_result[:name]
      assert_equal "owner", repository_result[:owner]
      assert_equal true, repository_result[:isDiscussionsActive]
      assert_equal true, repository_result[:hasIssues]
      assert_equal true, repository_result[:hasSecurityPolicy]
      assert_equal true, repository_result[:isThirdParty]
      assert_equal true, repository_result[:isOrganization]
      assert_equal 5, repository_result[:contributorsCount]
      assert_equal [], repository_result[:topContributorsData]
      assert_equal 0, repository_result[:openIssuesCount]
      assert_equal 0, repository_result[:openPullRequestsCount]
    end

    test("correctly serializes the release data") do
      release_data_result = @payload[:releaseData]

      assert_equal({ "tagName": "selected", "isPrerelease": true }, release_data_result[:selectedRelease])
      assert_equal({ "tagName": "latest", "isPrerelease": true }, release_data_result[:latestRelease])
      assert_equal [{ "tagName": "release", "isPrerelease": true }], release_data_result[:releases]
    end

    context "repoAdminableByViewer" do
      context "when the action has a repository" do
        context "when the current user is an admin of the repository" do
          test "repoAdminableByViewer is true" do
            @repo.add_member(@current_user, action: :admin)
            @payload = Marketplace::Payloads::ShowAction.new(
              repository_action: @action,
              selected_version: nil,
              current_user: @current_user,
              selected_release: nil,
              releases: Release.none,
              latest_release: build(:release),
              logged_in: false,
              emu_contribution_blocked: false
            ).call

            assert_equal true, @payload[:repoAdminableByViewer]
          end
        end

        context "when the current user is not an admin of the repository" do
          test "repoAdminableByViewer is false" do
            assert_equal false, @payload[:repoAdminableByViewer]
          end
        end

        context "when current user is not present" do
          test "repoAdminableByViewer is false" do
            @payload = Marketplace::Payloads::ShowAction.new(
              repository_action: @action,
              selected_version: nil,
              current_user: nil,
              selected_release: nil,
              releases: Release.none,
              latest_release: build(:release),
              logged_in: false,
              emu_contribution_blocked: false
            ).call

            assert_equal false, @payload[:repoAdminableByViewer]
          end
        end
      end
    end

    test "correctly serializes the logged in value" do
      assert_equal false, @payload[:loggedIn]
    end

    test("correctly serializes the star data") do
      star_data_result = @payload[:starData]

      assert_equal true, star_data_result[:starredByCurrentUser]
      assert_equal true, star_data_result[:currentUserAbleToStar]
      assert_equal "enterprise", star_data_result[:currentUserEnterpriseName]
    end
  end
end unless GitHub.enterprise?
