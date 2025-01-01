# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class ProgrammaticAccessGrantRequest::FinderTest < GitHub::TestCase
  include PermissionsHelper
  include ApiProgrammaticGrantHelpers

  fixtures do
    @admin = create(:user)
    @org = create(:organization, admin: @admin)
    @member = create(:user)

    @org.add_member(@member)
  end

  def create_request(actor: @member, target: @org,  accessed_at: nil, permissions: { "metadata" => :read }, repositories: [], repository_selection: nil)
    access = create(:user_programmatic_access, owner: actor, accessed_at: accessed_at) if accessed_at
    make_user_programmatic_access_with_grant_request(
      actor: actor,
      target: target,
      access: access,
      permissions: permissions,
      repositories: repositories,
      repository_selection: repository_selection
    ).grant_request
  end

  context "#perform" do
    test "sets base model to OrganizationProgrammaticAccessGrantRequest when org target provided" do
      params = { target: @org }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      finder.perform
      assert_equal OrganizationProgrammaticAccessGrantRequest, finder.grantable_klass
    end

    test "sets base model to OrganizationProgrammaticAccessGrantRequest when org-owned repo provided" do
      repo = create(:repository, :minimal, owner: @org)
      params = { repository: repo }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      finder.perform
      assert_equal OrganizationProgrammaticAccessGrantRequest, finder.grantable_klass
    end

    test "sets base model to OrganizationProgrammaticAccessGrantRequest when '#{@org.class.name}' target_type provided" do
      params = { target_type: @org.class.name }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      finder.perform
      assert_equal OrganizationProgrammaticAccessGrantRequest, finder.grantable_klass
    end

    test "sets base model to UserProgrammaticAccessGrantRequest when user target provided" do
      params = { target: @admin }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      finder.perform
      assert_equal UserProgrammaticAccessGrantRequest, finder.grantable_klass
    end

    test "sets base model to UserProgrammaticAccessGrantRequest when user-owned repo provided" do
      repo = create(:repository, :minimal, owner: @admin)
      params = { repository: repo }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      finder.perform
      assert_equal UserProgrammaticAccessGrantRequest, finder.grantable_klass
    end

    test "sets base model to UserProgrammaticAccessGrantRequest when '#{@user.class.name}' target_type provided" do
      params = { target_type: @admin.class.name }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      finder.perform
      assert_equal UserProgrammaticAccessGrantRequest, finder.grantable_klass
    end

    test "raises error when target_type not provided" do
      params = { target_type: nil }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      assert_raises_with_message StandardError, "Invalid target type: NilClass" do
        finder.perform
      end
    end

    test "filters requests by repo" do
      create_request
      repo = create(:repository, owner: @org)
      other_request = create_request(actor: @admin, repositories: [repo], repository_selection: :all)

      params = { repository: repo }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      result = finder.perform

      assert_equal 1, result.size
      assert_equal other_request, result.first
    end

    test "filters requests by single owner" do
      create_request
      other_request = create_request(actor: @admin)

      params = { target: @org, owner: @admin }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      result = finder.perform

      assert_equal 1, result.size
      assert_equal other_request, result.first
    end

    test "filters requests by two owners" do
      create_request(actor: @admin)
      request = create_request(actor: @member)
      other_user = create(:user)
      @org.add_member(other_user)
      other_request = create_request(actor: other_user)

      params = { target: @org, owner: [@member, other_user] }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      result = finder.perform

      assert_equal 2, result.size
      assert_same_elements [request, other_request], result
    end

    test "filters requests by permission" do
      create_request(permissions: { "metadata" => :read })
      other_request = create_request(permissions: { "members" => :write })

      params = { target: @org, permission: { "members" => :write } }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      result = finder.perform

      assert_equal 1, result.size
      assert_equal other_request, result.first
    end


    test "filters requests by access" do
      create_request
      other_request = create_request

      params = { target: @org, access: other_request.user_programmatic_access }
      finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
      result = finder.perform

      assert_equal 1, result.size
      assert_equal other_request, result.first
    end

    test "filters requests by last_used_before String" do
      Timecop.travel(DateTime.parse("2023-02-15 11:30:00 UTC")) do
        last_week_request = create_request(accessed_at: 1.week.ago.change(usec: 0).utc)
        last_month_request = create_request(accessed_at: 1.month.ago.change(usec: 0).utc)

        params = { target: @org, last_used_before: last_week_request.user_programmatic_access.accessed_at.utc.iso8601 }
        finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
        result = finder.perform

        assert_equal 1, result.size
        assert_equal last_month_request, result.first
      end
    end

    test "filters requests by last_used_before as Time object" do
      Timecop.travel(DateTime.parse("2023-02-15 11:30:00 UTC")) do
        last_week_request = create_request(accessed_at: 1.week.ago.change(usec: 0).utc)
        last_month_request = create_request(accessed_at: 1.month.ago.change(usec: 0).utc)

        params = { target: @org, last_used_before: last_week_request.user_programmatic_access.accessed_at.utc }
        finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
        result = finder.perform

        assert_equal 1, result.size
        assert_equal last_month_request, result.first
      end
    end

    test "filters requests by last_used_after String" do
      Timecop.travel(DateTime.parse("2023-02-15 11:30:00 UTC")) do
        last_week_request = create_request(accessed_at: 1.week.ago.change(usec: 0).utc)
        last_month_request = create_request(accessed_at: 1.month.ago.change(usec: 0).utc)

        params = { target: @org, last_used_after: last_month_request.user_programmatic_access.accessed_at.utc.iso8601 }
        finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
        result = finder.perform

        assert_equal 1, result.size
        assert_equal last_week_request, result.first
      end
    end

    test "filters requests by last_used_after as Time object" do
      Timecop.travel(DateTime.parse("2023-02-15 11:30:00 UTC")) do
        last_week_request = create_request(accessed_at: 1.week.ago.change(usec: 0).utc)
        last_month_request = create_request(accessed_at: 1.month.ago.change(usec: 0).utc)

        params = { target: @org, last_used_after: last_month_request.user_programmatic_access.accessed_at.utc }
        finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
        result = finder.perform

        assert_equal 1, result.size
        assert_equal last_week_request, result.first
      end
    end

    test "filters requests by time window" do
      Timecop.travel(DateTime.parse("2023-02-15 11:30:00 UTC")) do
        last_day_request = create_request(accessed_at: 1.day.ago.change(usec: 0).utc)
        last_week_request = create_request(accessed_at: 1.week.ago.change(usec: 0).utc)
        last_month_request = create_request(accessed_at: 1.month.ago.change(usec: 0).utc)

        last_used_before = last_day_request.user_programmatic_access.accessed_at.utc
        last_used_after = last_month_request.user_programmatic_access.accessed_at.utc
        params = { target: @org, last_used_before: last_used_before, last_used_after: last_used_after }
        finder = ProgrammaticAccessGrantRequest::Finder.new(params: params)
        result = finder.perform

        assert_equal 1, result.size
        assert_equal last_week_request, result.first
      end
    end
  end
end
