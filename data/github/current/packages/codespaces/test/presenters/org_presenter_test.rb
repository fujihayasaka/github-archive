# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::OrgPresenterTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
    @organization = create(:organization, business: @business)
  end

  setup do
    Codespaces::BusinessDelegator.new(@business).enable_codespaces_for_selected_organizations!([@organization.id])
  end

  test "renders organization info" do
    result = Codespaces::OrgPresenter.new(
      business: @business,
      organization: @organization,
      avatar_url: "/fakeurl",
    ).serialize

    assert_equal({
      id: @organization.id,
      displayLogin: @organization.display_login,
      avatarUrl: "/fakeurl",
      memberCount: @organization.members.size,
      enablementStatus: "Enabled",
      path: "/#{@organization.display_login}"
    }, result)
  end

  test "when disabled" do
    Codespaces::BusinessDelegator.new(@business).disable_codespaces_for_selected_organizations!([@organization.id])

    result = Codespaces::OrgPresenter.new(
      business: @business,
      organization: @organization,
    ).serialize

    assert_equal({
      id: @organization.id,
      displayLogin: @organization.display_login,
      avatarUrl: nil,
      memberCount: @organization.members.size,
      enablementStatus: "Disabled",
      path: "/#{@organization.display_login}"
    }, result)
  end
end unless GitHub.enterprise?
