# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Payloads::ShowActionTest < GitHub::TestCase
  fixtures do
    @category1 = create(:marketplace_category)
    @category2 = create(:marketplace_category)
    @action = create(:repository_action,
                     categories: [@category1, @category2],
                     dependents_count: 4,
                     security_email: "security@email.com",
                     slug: "action-slug")
  end

  setup do
    Marketplace::Serializers::Action.stubs(:svg_icon_string).returns("sweet svg")
    Marketplace::Actions::GetReadmeHtml.stubs(:new).returns(stub(call: "<div/>"))
    Marketplace::Serializers::Repository.any_instance.stubs(:call).returns({
      name: "repo",
      owner: "owner",
      isDiscussionsActive: true,
      hasIssues: true,
      hasSecurityPolicy: true,
      mitLicensePath: "www.path.com",
      isThirdParty: true,
      isOrganization: true,
      contributorsCount: 5,
      topContributorsData: []
    })
    Marketplace::Serializers::DelistActionData.any_instance.stubs(:call).returns({
      hydroAttrs: { "hydro": "attrs" },
      repoAdminableByViewer: true
    })
    @payload = Marketplace::Payloads::ShowAction.new(
      repository_action: @action, selected_version: nil, current_user: nil, request_url: "www.request.com"
    ).call
  end

  context "#call" do
    test "correctly serializes the action data" do
      action_result = @payload[:action]
      expected_categories = [
        { name: @category1.name.parameterize, slug: @category1.slug },
        { name: @category2.name.parameterize, slug: @category2.slug }
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
    end

    test "hash includes the readme data" do
      assert_equal "<div/>", @payload[:readmeHtml]
    end

    test "hash includes the help url" do
      assert_equal "#{GitHub.help_url}/articles/about-readmes/", @payload[:helpUrl]
    end

    test "correctly serializes the repository data" do
      repository_result = @payload[:repository]

      assert_equal "repo", repository_result[:name]
      assert_equal "owner", repository_result[:owner]
      assert_equal true, repository_result[:isDiscussionsActive]
      assert_equal true, repository_result[:hasIssues]
      assert_equal true, repository_result[:hasSecurityPolicy]
      assert_equal "www.path.com", repository_result[:mitLicensePath]
      assert_equal true, repository_result[:isThirdParty]
      assert_equal true, repository_result[:isOrganization]
      assert_equal 5, repository_result[:contributorsCount]
      assert_equal [], repository_result[:topContributorsData]
    end

    test "correctly serializes the delist action data" do
      delist_action_result = @payload[:delistActionData]

      assert_equal({ "hydro": "attrs" }, delist_action_result[:hydroAttrs])
      assert_equal true, delist_action_result[:repoAdminableByViewer]
    end
  end
end unless GitHub.enterprise?
