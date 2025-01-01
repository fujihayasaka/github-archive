# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class ProgrammaticAccessGrant::FinderTest < GitHub::TestCase
  include PermissionsHelper
  include ApiProgrammaticGrantHelpers

  fixtures do
    @admin = create(:user)
    @org = create(:organization, admin: @admin)
    @member = create(:user)

    @org.add_member(@member)
  end

  def create_grant(requester: @admin, target: @org, accessed_at: nil, permissions: { "metadata" => :read }, repositories: [], repository_selection: nil)
    access = create(:user_programmatic_access, owner: requester, accessed_at: accessed_at) if accessed_at
    make_user_programmatic_access_with_grant(
      requester: requester,
      target: @org,
      access: access,
      permissions: permissions,
      repositories: repositories,
      repository_selection: repository_selection
    ).grant
  end

  context "#perform" do
    test "sets base model to OrganizationProgrammaticAccessGrant when org target provided" do
      params = { target: @org }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      finder.perform
      assert_equal OrganizationProgrammaticAccessGrant, finder.grantable_klass
    end

    test "sets base model to OrganizationProgrammaticAccessGrant when org-owned repo provided" do
      repo = create(:repository, :minimal, owner: @org)
      params = { repository: repo }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      finder.perform
      assert_equal OrganizationProgrammaticAccessGrant, finder.grantable_klass
    end

    test "sets base model to OrganizationProgrammaticAccessGrant when '#{@org.class.name}' target_type provided" do
      params = { target_type: @org.class.name }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      finder.perform
      assert_equal OrganizationProgrammaticAccessGrant, finder.grantable_klass
    end

    test "sets base model to UserProgrammaticAccessGrant when user target provided" do
      params = { target: @admin }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      finder.perform
      assert_equal UserProgrammaticAccessGrant, finder.grantable_klass
    end

    test "sets base model to UserProgrammaticAccessGrant when user-owned repo provided" do
      repo = create(:repository, :minimal, owner: @admin)
      params = { repository: repo }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      finder.perform
      assert_equal UserProgrammaticAccessGrant, finder.grantable_klass
    end

    test "sets base model to UserProgrammaticAccessGrant when '#{@user.class.name}' target_type provided" do
      params = { target_type: @admin.class.name }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      finder.perform
      assert_equal UserProgrammaticAccessGrant, finder.grantable_klass
    end

    test "raises error when target_type not provided" do
      params = { target_type: nil }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      assert_raises_with_message StandardError, "Invalid target type: NilClass" do
        finder.perform
      end
    end

    test "filters grants by repo" do
      create_grant
      repo = create(:repository, owner: @org)
      other_grant = create_grant(requester: @admin, repositories: [repo], repository_selection: :all)

      params = { repository: repo }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      result = finder.perform

      assert_equal 1, result.size
      assert_equal other_grant, result.first
    end

    test "filters grants by single owner" do
      create_grant
      other_grant = create_grant(requester: @member)

      params = { target: @org, owner: @member }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      result = finder.perform

      assert_equal 1, result.size
      assert_equal other_grant, result.first
    end

    test "filters grants by two owners" do
      create_grant(requester: @admin)
      grant = create_grant(requester: @member)
      other_user = create(:user)
      @org.add_member(other_user)
      other_grant = create_grant(requester: other_user)

      params = { target: @org, owner: [@member, other_user] }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      result = finder.perform

      assert_equal 2, result.size
      assert_same_elements [grant, other_grant], result
    end

    test "filters grants by permission" do
      create_grant(permissions: { "metadata" => :read })
      other_grant = create_grant(permissions: { "members" => :write })

      params = { target: @org, permission: { "members" => :write } }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      result = finder.perform

      assert_equal 1, result.size
      assert_equal other_grant, result.first
    end


    test "filters grants by access" do
      create_grant
      other_grant = create_grant

      params = { target: @org, access: other_grant.user_programmatic_access }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      result = finder.perform

      assert_equal 1, result.size
      assert_equal other_grant, result.first
    end

    test "filters grants by last_used_before String" do
      Timecop.travel(DateTime.parse("2023-02-15 11:30:00 UTC")) do
        last_week_grant = create_grant(accessed_at: 1.week.ago.change(usec: 0).utc)
        last_month_grant = create_grant(accessed_at: 1.month.ago.change(usec: 0).utc)

        params = { target: @org, last_used_before: last_week_grant.user_programmatic_access.accessed_at.utc.iso8601 }
        finder = ProgrammaticAccessGrant::Finder.new(params: params)
        result = finder.perform

        assert_equal 1, result.size
        assert_equal last_month_grant, result.first
      end
    end

    test "filters grants by last_used_before as Time object" do
      Timecop.travel(DateTime.parse("2023-02-15 11:30:00 UTC")) do
        last_week_grant = create_grant(accessed_at: 1.week.ago.change(usec: 0).utc)
        last_month_grant = create_grant(accessed_at: 1.month.ago.change(usec: 0).utc)

        params = { target: @org, last_used_before: last_week_grant.user_programmatic_access.accessed_at.utc }
        finder = ProgrammaticAccessGrant::Finder.new(params: params)
        result = finder.perform

        assert_equal 1, result.size
        assert_equal last_month_grant, result.first
      end
    end

    test "filters grants by last_used_after String" do
      Timecop.travel(DateTime.parse("2023-02-15 11:30:00 UTC")) do
        last_week_grant = create_grant(accessed_at: 1.week.ago.change(usec: 0).utc)
        last_month_grant = create_grant(accessed_at: 1.month.ago.change(usec: 0).utc)

        params = { target: @org, last_used_after: last_month_grant.user_programmatic_access.accessed_at.utc.iso8601 }
        finder = ProgrammaticAccessGrant::Finder.new(params: params)
        result = finder.perform

        assert_equal 1, result.size
        assert_equal last_week_grant, result.first
      end
    end

    test "filters grants by last_used_after as Time object" do
      Timecop.travel(DateTime.parse("2023-02-15 11:30:00 UTC")) do
        last_week_grant = create_grant(accessed_at: 1.week.ago.change(usec: 0).utc)
        last_month_grant = create_grant(accessed_at: 1.month.ago.change(usec: 0).utc)

        params = { target: @org, last_used_after: last_month_grant.user_programmatic_access.accessed_at.utc }
        finder = ProgrammaticAccessGrant::Finder.new(params: params)
        result = finder.perform

        assert_equal 1, result.size
        assert_equal last_week_grant, result.first
      end
    end

    test "filters grants by time window" do
      Timecop.travel(DateTime.parse("2023-02-15 11:30:00 UTC")) do
        last_day_grant = create_grant(accessed_at: 1.day.ago.change(usec: 0).utc)
        last_week_grant = create_grant(accessed_at: 1.week.ago.change(usec: 0).utc)
        last_month_grant = create_grant(accessed_at: 1.month.ago.change(usec: 0).utc)

        last_used_before = last_day_grant.user_programmatic_access.accessed_at.utc
        last_used_after = last_month_grant.user_programmatic_access.accessed_at.utc
        params = { target: @org, last_used_before: last_used_before, last_used_after: last_used_after }
        finder = ProgrammaticAccessGrant::Finder.new(params: params)
        result = finder.perform

        assert_equal 1, result.size
        assert_equal last_week_grant, result.first
      end
    end

    test "filters grants by the token id" do
      grant = create_grant
      other_grant = create_grant
      third_grant = create_grant

      params = { target: @org, token_ids: [grant.user_programmatic_access.id, third_grant.user_programmatic_access.id] }
      finder = ProgrammaticAccessGrant::Finder.new(params: params)
      result = finder.perform

      assert_equal 2, result.size
      assert_same_elements [grant, third_grant], result
    end
  end
end
