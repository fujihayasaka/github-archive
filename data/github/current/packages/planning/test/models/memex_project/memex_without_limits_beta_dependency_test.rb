# typed: true
# frozen_string_literal: true
require "test_helper"

class MemexWithoutLimitsBetaDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization, login: "github")
    @user = create(:verified_user).tap { |u| @org.add_member(u) }
    @org_memex_creator = create(:verified_user).tap { |u| @org.add_member(u) }
    @org_memex = create(:memex_project, owner: @org, creator: @org_memex_creator)
  end

  setup do
    GitHub.flipper[:memex_without_limits_banner_safe_rollout].enable
    GitHub.flipper[:memex_without_limits_staffship_banner_safe_rollout].enable
  end

  context "#eligible_for_memex_without_limits_waitlist?" do
    test "returns true when project meets criteria", skip_enterprise: true do
      @org_memex.stubs(:created_at).returns(DateTime.now - 10.years)
      create(:memex_project_item, memex_project: @org_memex)
      MemexProject.stub_const(:MWL_MINIMUM_ITEM_THRESHOLD, 1) do
        assert @org_memex.eligible_for_memex_without_limits_waitlist?
      end
    end

    test "returns false when project meets criteria but memex_without_limits_banner_safe_rollout is disabled" do
      GitHub.flipper[:memex_without_limits_banner_safe_rollout].disable
      @org_memex.stubs(:created_at).returns(DateTime.now - 10.years)
      create(:memex_project_item, memex_project: @org_memex)
      MemexProject.stub_const(:MWL_MINIMUM_ITEM_THRESHOLD, 1) do
        refute @org_memex.eligible_for_memex_without_limits_waitlist?
      end
    end

    test "returns false when project is < six months old" do
      @org_memex.stubs(:created_at).returns(DateTime.now - 1.hour)

      refute @org_memex.eligible_for_memex_without_limits_waitlist?
    end

    test "returns false when project has too few unarchived items" do
      new_threshold = 1
      refute @org_memex.memex_project_items.count >= new_threshold,
        "Test setup failure: project has too many items"

      create(:memex_project_item, :archived, memex_project: @org_memex)
      create(:memex_project_item, :archived, memex_project: @org_memex)
      @org_memex.stubs(:created_at).returns(DateTime.now - 10.years)
      MemexProject.stub_const(:MWL_MINIMUM_ITEM_THRESHOLD, new_threshold) do
        refute @org_memex.eligible_for_memex_without_limits_waitlist?
      end
    end

    test "returns true when project has no slice_by (it can be nil apparently)" do
      view = create(:memex_project_view, memex_project: @org_memex, slice_by: nil)
      view.update_column(:slice_by, nil)
      assert_nil @org_memex.memex_project_views.last.slice_by

      @org_memex.stubs(:created_at).returns(DateTime.now - 10.years)
      create(:memex_project_item, memex_project: @org_memex)
      MemexProject.stub_const(:MWL_MINIMUM_ITEM_THRESHOLD, 1) do
        assert @org_memex.eligible_for_memex_without_limits_waitlist?
      end
    end

    test "returns false when project has slice_by" do
      view = create(:memex_project_view, memex_project: @org_memex, slice_by: nil)
      view.update_attribute(:slice_by, { field: @org_memex.status_column.id })
      refute_nil @org_memex.memex_project_views.last.slice_by

      @org_memex.stubs(:created_at).returns(DateTime.now - 10.years)
      create(:memex_project_item, memex_project: @org_memex)
      MemexProject.stub_const(:MWL_MINIMUM_ITEM_THRESHOLD, 1) do
        refute @org_memex.eligible_for_memex_without_limits_waitlist?
      end
    end

    test "returns false when project has unsupported field" do
      create(
        :memex_project_view,
        memex_project: @org_memex,
        visible_fields: [create(:memex_project_column, memex_project: @org_memex, data_type: :tracked_by, user_defined: true).id]
      )

      @org_memex.stubs(:created_at).returns(DateTime.now - 10.years)
      MemexProject.stub_const(:MWL_MINIMUM_ITEM_THRESHOLD, 1) do
        refute @org_memex.eligible_for_memex_without_limits_waitlist?
      end
    end

    test "returns false when project has insights charts" do
      create(:memex_project_chart, memex_project: @org_memex)

      @org_memex.stubs(:created_at).returns(DateTime.now - 10.years)
      MemexProject.stub_const(:MWL_MINIMUM_ITEM_THRESHOLD, 1) do
        refute @org_memex.eligible_for_memex_without_limits_waitlist?
      end
    end
  end

  context "#eligible_for_staffship_memex_without_limits_waitlist?" do
    test "returns true when project meets criteria", skip_enterprise: true do
      assert @org_memex.eligible_for_staffship_memex_without_limits_waitlist?
    end

    test "returns false when project meets criteria but memex_without_limits_staffship_banner_safe_rollout is disabled" do
      GitHub.flipper[:memex_without_limits_staffship_banner_safe_rollout].disable
      refute @org_memex.eligible_for_staffship_memex_without_limits_waitlist?
    end

    test "returns false when project is not internal", skip_enterprise: true do
      external_org = create(:organization, login: "external-org")
      external_org_creator = create(:verified_user).tap { |u| external_org.add_member(u) }
      external_org_memex = create(:memex_project, owner: external_org, creator: external_org_creator)

      refute external_org_memex.eligible_for_staffship_memex_without_limits_waitlist?
    end

    test "returns true when project has no slice_by (it can be nil apparently)" do
      view = create(:memex_project_view, memex_project: @org_memex, slice_by: nil)
      view.update_column(:slice_by, nil)
      assert_nil @org_memex.memex_project_views.last.slice_by

      assert @org_memex.eligible_for_staffship_memex_without_limits_waitlist?
    end

    test "returns true even if project has slice_by" do
      view = create(:memex_project_view, memex_project: @org_memex, slice_by: nil)
      view.update_attribute(:slice_by, { field: @org_memex.status_column.id })
      refute_nil @org_memex.memex_project_views.last.slice_by

      assert @org_memex.eligible_for_staffship_memex_without_limits_waitlist?
    end

    test "returns false when project has unsupported field" do
      create(
        :memex_project_view,
        memex_project: @org_memex,
        visible_fields: [create(:memex_project_column, memex_project: @org_memex, data_type: :tracked_by, user_defined: true).id]
      )

      refute @org_memex.eligible_for_staffship_memex_without_limits_waitlist?
    end

    test "returns false when project has insights charts" do
      create(:memex_project_chart, memex_project: @org_memex)

      refute @org_memex.eligible_for_staffship_memex_without_limits_waitlist?
    end
  end

  context "#optout" do
    test "removes the projects from the feature flag" do
      GitHub.flipper[:memex_table_without_limits].enable(@org_memex)
      @org_memex.remove_from_beta
      refute GitHub.flipper[:memex_table_without_limits].enabled?(@org_memex)
    end

    test "does not throw error if project isn't already flagged in" do
      GitHub.flipper[:memex_table_without_limits].disable(@org_memex)
      assert_nothing_raised do
        @org_memex.remove_from_beta
      end
    end
  end
end
