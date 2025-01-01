# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationArchivedDependencyTest < GitHub::TestCase
  fixtures do
    @site_admin = create :staff_admin_user
    @admin = create(:user)
    @rando = create(:user)
    @organization = create(:organization, admin: @admin, plan: GitHub::Plan.free)
    @archived_organization = create(:archived_organization, admin: @admin)
    @business = create(:business, owners: [@admin])
  end

  test "archived? returns true when organization is archived" do
    assert_performed_jobs(1, only: Organizations::ArchiveJob) do
      @organization.archive(@admin)
    end

    @organization.reload
    assert @organization.archived?
    assert @organization.archived_at
  end

  test "archived_or_archiving? returns true while job is still processing" do
    @organization.archive(@admin)

    refute @organization.archived?
    assert_nil @organization.archived_at
    assert @organization.archived_or_archiving?

    perform_enqueued_jobs only: Organizations::ArchiveJob

    @organization.reload
    assert @organization.archived?
    assert @organization.archived_at
    assert @organization.archived_or_archiving?
  end

  test "archived_at returns the time when organization is archived" do
    Timecop.freeze do
      assert_performed_with(job: Organizations::ArchiveJob, args: [@organization, @admin, { by_site_admin: false }]) do
        @organization.archive(@admin)
      end

      @organization.reload
      assert_equal Time.current.to_i, @organization.archived_at.to_i
      assert @organization.archived?
    end
  end

  test "allows free orgs to be archived" do
    free_org = create(:organization, admin: @admin, plan: GitHub::Plan.free)
    active_org = T.let(free_org, Organization)

    assert active_org.archive(@admin)
  end

  test "allows free with addons orgs to be archived" do
    free_org = create(:organization, admin: @admin, plan: GitHub::Plan.free_with_addons)
    active_org = T.let(free_org, Organization)

    assert active_org.archive(@admin)
  end

  test "allows orgs in an enterprise account to be archived" do
    business_org = create(:enterprise_linked_organization, admin: @admin, business: @business)

    active_org = T.let(business_org, Organization)
    assert active_org.archive(@admin)
  end

  test "allows orgs to be archived by site admin" do
    refute_predicate @organization, :archived?

    perform_enqueued_jobs only: Organizations::ArchiveJob do
      assert @organization.archive(@site_admin)
    end

    assert_predicate @organization.reload, :archived?
  end

  test "disallows non-free orgs to be archived" do
    GitHub::Plan.all_non_free_org_plans
    .reject { |plan| plan.name == GitHub::Plan::FREE_WITH_ADDONS }
    .each do |paid_plan|
      paid_org = create(:organization, admin: @admin, plan: paid_plan)

      active_org = T.let(paid_org, Organization)
      refute active_org.archive(@admin)
    end
  end

  test "disallows orgs to be archived by a non-admin" do
    refute @organization.archive(@rando)
  end

  test "does not queue job or update timestamp when org is already archived" do
    Timecop.freeze do
      assert_performed_with(job: Organizations::ArchiveJob, args: [@organization, @admin, { by_site_admin: false }]) do
        @organization.archive(@admin)
      end

      @organization.reload
      assert_equal Time.current.to_i, @organization.archived_at.to_i
      assert @organization.archived?

      Timecop.travel(1.day.from_now)
      assert_no_changes "@organization.archived_at" do
        assert_no_performed_jobs only: Organizations::ArchiveJob do
          assert @organization.archive(@admin)
        end
      end
    end
  end

  test "instruments org.archive" do
    events = subscribe "org.archive"

    assert_performed_with job: Organizations::ArchiveJob, args: [@organization, @admin, { by_site_admin: false }] do
      @organization.archive(@admin)
    end

    expected_payload = {
      org: @organization.login,
      org_id: @organization.id,
      actor: @admin.login,
      actor_id: @admin.id
    }

    assert event = events.pop, "expected an event"
    assert_equal expected_payload, event.payload
  end

  test "unarchive returns true when organization is not archived" do
    refute @organization.archived?
    assert @organization.unarchive(@admin)
  end

  test "unarchive unsets unarchived_at and returns true when organization is archived" do
    assert @archived_organization.unarchive(@admin)
    assert_nil @archived_organization.archived_at
    refute @archived_organization.archived?
  end

  test "allows orgs to be unarchived by site admin" do
    assert_predicate @archived_organization, :archived?

    assert @archived_organization.unarchive(@site_admin)

    refute_predicate @archived_organization, :archived?
  end

  test "disallows orgs to be unarchived by a non-admin" do
    refute @archived_organization.unarchive(@rando)
  end

  test "instruments org.unarchive" do
    events = subscribe "org.unarchive"

    @archived_organization.unarchive(@admin)

    expected_payload = {
      org: @archived_organization.login,
      org_id: @archived_organization.id,
      actor: @admin.login,
      actor_id: @admin.id
    }

    assert event = events.pop, "expected an event"
    assert_equal expected_payload, event.payload
  end
end
