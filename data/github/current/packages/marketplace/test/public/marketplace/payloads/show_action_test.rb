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

  context "#call" do
    test "correctly serializes the action data" do
      Marketplace::Serializers::Action.stubs(:svg_icon_string).returns("sweet svg")
      payload = Marketplace::Payloads::ShowAction.new(repository_action: @action).call[:action]

      assert_equal [@category1.name.downcase, @category2.name.downcase].sort, payload[:categories].sort
      assert_equal @action.color, payload[:color]
      assert_equal @action.description + "\n", payload[:description]
      assert_equal "sweet svg", payload[:iconSvg]
      assert_equal @action.id, payload[:id]
      assert_equal @action.verified_owner?, payload[:isVerifiedOwner]
      assert_equal @action.name, payload[:name]
      assert_equal @action.owner&.display_login, payload[:ownerLogin]
      assert_equal @action.slug, payload[:slug]
      assert_equal @action.repository&.stargazer_count, payload[:stars]
      assert_equal Marketplace::Types::ListingTypes::RepositoryAction.serialize, payload[:type]
    end
  end
end unless GitHub.enterprise?
