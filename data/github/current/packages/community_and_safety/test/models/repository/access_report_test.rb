# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAccessReportTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @member = create(:user)
    @other_member = create(:user)
    @collab = create(:user)
    @triager = create(:user)
    @custom_role_member = create(:user)
    @org = create(:business_plus_organization, admin: @admin)
    @team = create(:team, organization: @org, privacy: :closed)
    @org_owned_repo = create(:repository, owner: @org)

    @org.add_member(@member)
    @org.add_member(@other_member)
    @team.add_member(@member)
    @org_owned_repo.add_member(@collab, action: :write)
    @team.add_repository(@org_owned_repo, :admin)

    @custom_role = create(:custom_repository_role, name: "Some Custom Role",
      owner_id: @org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)
  end

  test "#generate_csv generates a CSV of user permissions" do
    report = Repository::AccessReport.new(repository: @org_owned_repo, viewer: @admin)

    output = report.generate_csv.split("\n")
    assert_equal "login,permission", output.shift
    assert_equal "#{@admin.display_login},admin", output.shift
    assert_equal "#{@member.display_login},admin", output.shift
    assert_equal "#{@other_member.display_login},read", output.shift
    assert_equal "#{@collab.display_login},write", output.shift
  end

  test "#generate_csv returns custom and system role names for users" do
    @org.add_member(@triager)
    @org.add_member(@custom_role_member)
    @org_owned_repo.add_member(@triager, action: :triage)
    @org_owned_repo.add_member(@custom_role_member, action: @custom_role.name)

    report = Repository::AccessReport.new(repository: @org_owned_repo, viewer: @admin)

    output, queries = log_queries do
      report.generate_csv.split("\n")
    end

    assert_equal "login,permission", output.shift
    assert_equal "#{@admin.display_login},admin", output.shift
    assert_equal "#{@member.display_login},admin", output.shift
    assert_equal "#{@other_member.display_login},read", output.shift
    assert_equal "#{@collab.display_login},write", output.shift
    assert_equal "#{@triager.display_login},triage", output.shift
    assert_equal "#{@custom_role_member.display_login},#{@custom_role.name}", output.shift
  end

  test "#generate_csv includes members with inherited permissions" do
    @org.update_default_repository_permission(:none, actor: @admin)
    child_team_member = create(:user)
    @org.add_member(child_team_member)
    child_team = create(:team,
      organization: @org,
      parent_team_id: @team.id,
      privacy: :closed,
    )
    child_team.add_member(child_team_member)

    report = Repository::AccessReport.new(
      repository: @org_owned_repo,
      viewer: @admin,
    )

    output = report.generate_csv.split("\n")
    assert_equal "login,permission", output.shift
    assert_equal "#{@admin.display_login},admin", output.shift
    assert_equal "#{@member.display_login},admin", output.shift
    assert_equal "#{@collab.display_login},write", output.shift
    assert_equal "#{child_team_member.display_login},admin", output.shift
  end

  test "#filename generates filename for csv" do
    report = Repository::AccessReport.new(repository: @org_owned_repo, viewer: @admin)

    assert_equal "#{@org_owned_repo.name}-collaborators.csv", report.filename
  end
end
