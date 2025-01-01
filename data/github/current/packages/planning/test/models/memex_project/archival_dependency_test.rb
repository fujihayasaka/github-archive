# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProject::ArchivalDependencyTest < GitHub::TestCase

  # Either of these memex without limits feature flags will enable the paginated archive
  mwl_archive_feature_flags = [:memex_paginated_archive, :memex_table_without_limits]

  fixtures do
    @memex = create(:memex_project)
  end

  setup do
    GitHub.flipper[:memex_without_limits_kill_switch].disable
    GitHub.flipper[:memex_project_without_limits_public_beta].disable
    GitHub.flipper[:memex_table_without_limits_disabled].disable
    mwl_archive_feature_flags.each { |f| GitHub.flipper[f].disable }
  end

  context "archived_items_limit" do
    mwl_archive_feature_flags.each do |feature_flag|
      test "returns expected value when #{feature_flag} flag is disabled" do
        GitHub.flipper[feature_flag].disable
        assert_equal MemexProjectItem::ARCHIVED_ITEM_LIMIT, @memex.archived_items_limit
      end

      test "returns expected value when #{feature_flag} flag is enabled" do
        GitHub.flipper[feature_flag].enable
        assert_equal MemexProjectItem::EXPANDED_ARCHIVED_ITEM_LIMIT, @memex.archived_items_limit
      end

      test "returns expected value when #{feature_flag} flag is enabled but kill switch is also enabled" do
        GitHub.flipper[feature_flag].enable
        GitHub.flipper[:memex_without_limits_kill_switch].enable
        assert_equal MemexProjectItem::ARCHIVED_ITEM_LIMIT, @memex.archived_items_limit
      end
    end
  end

  context "has_reached_archived_items_limit?" do
    test "returns true when the number of items has reached the limit and both memex_paginated_archive flag and memex_table_without_limits are disabled" do
      fake_limit = 3
      @memex.stubs(:archived_items_limit).returns(fake_limit)
      fake_limit.times do
        refute_predicate @memex, :has_reached_archived_items_limit?
        create(:memex_project_item, :archived, memex_project: @memex)
      end
      assert_predicate @memex, :has_reached_archived_items_limit?
    end
  end

  context "memex_paginated_archive_enabled?" do
    test "returns false when all feature flags are disabled" do
      org = create(:organization)
      memex = create(:memex_project, owner: org)

      refute_predicate memex, :memex_paginated_archive_enabled?
    end

    test "returns true when memex_project_without_limits_public_beta flag is enabled for an organization" do
      org = create(:organization)
      memex = create(:memex_project, owner: org)
      GitHub.flipper[:memex_project_without_limits_public_beta].enable(org)

      assert_predicate memex, :memex_paginated_archive_enabled?
    end

    test "returns false when memex_project_without_limits_public_beta flag is enabled for an organization but memex_table_without_limits_disabled is enabled for a project" do
      org = create(:organization)
      memex = create(:memex_project, owner: org)
      GitHub.flipper[:memex_project_without_limits_public_beta].enable(org)
      GitHub.flipper[:memex_table_without_limits_disabled].enable(memex)

      refute_predicate memex, :memex_paginated_archive_enabled?
    end

    mwl_archive_feature_flags.each do |feature_flag|
      test "returns true when #{feature_flag} flag is enabled for project" do
        GitHub.flipper[feature_flag].enable(@memex)
        assert_predicate @memex, :memex_paginated_archive_enabled?
      end

      test "returns false when #{feature_flag} flag is enabled for project but kill switch is enabled" do
        GitHub.flipper[feature_flag].enable(@memex)
        GitHub.flipper[:memex_without_limits_kill_switch].enable
        refute_predicate @memex, :memex_paginated_archive_enabled?
      end
      test "returns false when #{feature_flag} flag is disabled" do
        GitHub.flipper[feature_flag].disable
        refute_predicate @memex, :memex_paginated_archive_enabled?
      end
    end

    test "returns true when memex_paginated_archive flag is enabled for project owner" do
      GitHub.flipper[:memex_paginated_archive].enable(@memex.owner)
      assert_predicate @memex, :memex_paginated_archive_enabled?
    end

    test "returns false when memex_paginated_archive flag is enabled for project owner but kill switch is enabled" do
      GitHub.flipper[:memex_paginated_archive].enable(@memex.owner)
      GitHub.flipper[:memex_without_limits_kill_switch].enable
      refute_predicate @memex, :memex_paginated_archive_enabled?
    end
  end
end
