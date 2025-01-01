# typed: true
# frozen_string_literal: true

require "test_helper"

class SuggesterOrganizationMemberSuggesterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @viewer = create(:user)
    @anon_viewer = create(:user)
    @org = create(:organization)
    @org.add_member(@viewer)
    @team = create(:team, organization: @org)
    @team.add_member(@viewer)
    @followed_user = create(:user)
    @viewer.follow(@followed_user)

    @public_org_member = create(:user)
    @org.add_member(@public_org_member)
    @org.publicize_member(@public_org_member)

    @private_org_member = create(:user)
    @org.add_member(@private_org_member)

    @authorizing_filter = cap_authorizing_filter.freeze
  end

  test "includes members of the organization" do
    member = create(:user)
    @team.add_member(member)

    suggester = create_suggester_with_cap_stubbing(viewer: @viewer, org: @org)

    assert suggester.mentions.any? { |x| x[:login] == member.login }
  end

  test "excludes members of the organization that have the viewer blocked" do
    member = create(:user)
    @team.add_member(member)
    member.block @viewer

    suggester = create_suggester_with_cap_stubbing(viewer: @viewer, org: @org)

    refute suggester.mentions.any? { |x| x[:login] == member.login }
  end

  test "includes teams of the organization" do
    suggester = create_suggester_with_cap_stubbing(viewer: @viewer, org: @org)

    assert suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == @team.id }
  end

  test "includes users who are not members of the organization that the user follows" do
    suggester = create_suggester_with_cap_stubbing(viewer: @viewer, org: @org)

    assert suggester.mentions.any? { |x| x[:login] == @followed_user.login }
  end

  test "excludes users who are not members of the organization that the user does not follow" do
    user = create(:user)
    suggester = create_suggester_with_cap_stubbing(viewer: @viewer, org: @org)

    refute suggester.mentions.any? { |x| x[:login] == user.login }
  end

  test "excludes teams that are not part of the organization" do
    other_team = create(:team)
    suggester = create_suggester_with_cap_stubbing(viewer: @viewer, org: @org)

    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == other_team.id }
  end

  test "excludes non-public organization members for non-members" do
    suggester = create_suggester_with_cap_stubbing(viewer: @anon_viewer, org: @org)

    refute suggester.mentions.any? { |x| x[:login] == @private_org_member.login }
    assert suggester.mentions.any? { |x| x[:login] == @public_org_member.login }
  end

  def create_suggester_with_cap_stubbing(viewer:, org:)
    Suggester::OrganizationMemberSuggester.new(viewer: viewer, org: org, cap_filter: @authorizing_filter)
  end
end
