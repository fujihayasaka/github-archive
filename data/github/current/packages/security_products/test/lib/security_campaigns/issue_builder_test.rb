# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::IssueBuilderTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @another_user = create(:user)

    @org = create(:business_plus_organization, admin: @owner)
    @repo = create(:private_repository, owner: @org, from_example: :simple)

    @public_team = create(:public_team, organization: @org)
    @secret_team = create(:secret_team, organization: @org)

    @campaign = create(:security_campaign, organization: @org)
    @suggested_fix_description = "suggested fix description"
  end

  test "creates correct issue title" do
    title = builder.issue_title

    assert_match @campaign.name, title
  end

  test "creates correct issue body" do
    body = builder.issue_body

    assert_match "**Description**\n#{@campaign.description}", body
    assert_match "Campaign manager**", body
    assert_match "@#{@campaign.user_manager_users.first.display_login}", body
    assert_match Rails.application.routes.url_helpers.user_url(@campaign.user_manager_users.first, host: GitHub.url), body
    assert_match "Contact the campaign managers using the [link provided]", body
    assert_match @campaign.contact_link, body
    assert_match @campaign.ends_at.strftime("%b %-d, %Y"), body
    assert_equal "[Security campaign tracking] #{@campaign.name}", builder.issue_title
    assert_not_match @another_user.display_login, body
  end

  test "builds issue with multiple managers" do
    @campaign.update!(user_manager_users: [@owner, @another_user])

    body = builder(@campaign).issue_body

    assert_match "Campaign managers", body
    assert_match "@#{@owner.display_login}", body
    assert_match Rails.application.routes.url_helpers.user_url(@owner, host: GitHub.url), body
    assert_match "@#{@another_user.display_login}", body
    assert_match Rails.application.routes.url_helpers.user_url(@another_user, host: GitHub.url), body
  end

  test "builds issue with team manager" do
    @campaign.update!(user_manager_users: [], team_manager_teams: [@public_team])

    body = builder(@campaign).issue_body

    assert_match "Campaign manager", body
    assert_match "@#{@org.display_login}/#{@public_team.slug}", body
    assert_match Rails.application.routes.url_helpers.team_url(@org, @public_team, host: GitHub.url), body
  end

  test "builds issue with team and user managers" do
    @campaign.update!(user_manager_users: [@owner, @another_user], team_manager_teams: [@public_team])

    body = builder(@campaign).issue_body

    assert_match "Campaign managers", body
    assert_match "@#{@owner.display_login}", body
    assert_match Rails.application.routes.url_helpers.user_url(@owner, host: GitHub.url), body
    assert_match "@#{@another_user.display_login}", body
    assert_match Rails.application.routes.url_helpers.user_url(@another_user, host: GitHub.url), body
    assert_match "@#{@org.display_login}/#{@public_team.slug}", body
    assert_match Rails.application.routes.url_helpers.team_url(@org, @public_team, host: GitHub.url), body
  end

  test "hides secret teams" do
    @campaign.update!(user_manager_users: [@owner], team_manager_teams: [@public_team, @secret_team])

    body = builder(@campaign).issue_body

    assert_match "Campaign manager", body
    assert_match "@#{@owner.display_login}", body
    assert_match "@#{@org.display_login}/#{@public_team.slug}", body
    refute_match @secret_team.slug, body
  end

  test "omits manager section if all managers are secret teams" do
    @campaign.update!(user_manager_users: [], team_manager_teams: [@secret_team])

    body = builder(@campaign).issue_body

    refute_match "Campaign manager", body
    refute_match @secret_team.slug, body
  end

  test "builds issue without contact link" do
    old_link = @campaign.contact_link
    @campaign.update!(contact_link: nil)

    body = builder(@campaign).issue_body

    assert_not_match old_link, body
    assert_not_match "Contact the campaign managers", body
  end

  test "unsafe characters in the campaign name are escaped" do
    @campaign.update!(name: "Bad *chars* [can](link) be_ `in a <b>link\\!</b>")

    body = builder(@campaign).issue_body

    assert_match "### [Security campaign] [Bad \\*chars\\* \\[can\\]\\(link\\) be\\_ \\`in a &lt;b&gt;link\\\\!&lt;/b&gt;]", body
  end

  test "unsafe characters in the campaign description are escaped" do
    @campaign.update!(description: "This is *italic* [and](https://example.com) this_ `is <b>bold\\!</b>")

    body = builder(@campaign).issue_body

    assert_match "**Description**\nThis is \\*italic\\* \\[and\\]\\(https://example.com\\) this\\_ \\`is &lt;b&gt;bold\\\\!&lt;/b&gt;", body
  end

  test "provides updated issues body" do
    issue_body = builder.updated_issue_body(@owner.name)

    assert_match @campaign.description, issue_body
    assert_match "These campaign details have been edited", issue_body
    assert_match @owner.name, issue_body
  end

  def builder(campaign = @campaign)
    SecurityCampaigns::IssueBuilder.new(
      security_campaign: campaign,
      repository: @repo,
    )
  end
end
