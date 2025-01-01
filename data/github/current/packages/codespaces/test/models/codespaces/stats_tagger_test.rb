# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesStatsTaggerTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @codespace = create(:codespace)
  end

  setup do
    skip if GitHub.enterprise?
    disable_feature_flag(:codespaces_automated_testing, @user)
  end

  context "#all_tags" do
    test "it works when given no data" do
      expected_tags = {}
      assert_equal expected_tags, Codespaces::StatsTagger.new.all_tags
    end

    test "returns tags for a given codespace" do
      expected_tags = {
        location: @codespace.location,
        repository: @codespace.repository.id,
        name: @codespace.name,
        sku_name: @codespace.sku_name,
        from_pr: false,
        from_fork: false,
        vscs_target: @codespace.vscs_target,
        billable_owner_type: @codespace.billable_owner.class.name.downcase,
        is_copilot_workspace: false,
        is_workspace_editor_cloud_environment: false
      }
      all_tags = Codespaces::StatsTagger.new(codespace: @codespace).all_tags
      assert_equal expected_tags, all_tags
    end

    test "tags copilot workspaces as such" do
      copilot_workspace = create(:copilot_workspace)
      all_tags = Codespaces::StatsTagger.new(codespace: copilot_workspace).all_tags
      assert all_tags[:is_copilot_workspace]
    end

    test "tags is copilot workspace true without codespace passed" do
      all_tags = Codespaces::StatsTagger.new(is_copilot_workspace: true).all_tags
      assert all_tags[:is_copilot_workspace]
    end

    test "tags is copilot workspace false without codespace passed" do
      all_tags = Codespaces::StatsTagger.new(is_copilot_workspace: false).all_tags
      refute all_tags[:is_copilot_workspace]
    end

    test "does not tag is copilot workspace false when nothing is passed" do
      all_tags = Codespaces::StatsTagger.new.all_tags
      assert_nil all_tags[:is_copilot_workspace]
    end

    test "returns tags when given an owner if that owner is an automated user" do
      enable_feature_flag(:codespaces_automated_testing, @user)
      expected_tags = {
        codespaces_automated_testing: true
      }
      all_tags = Codespaces::StatsTagger.new(owner: @user).all_tags
      assert_equal expected_tags, all_tags
    end

    test "returns tags when given a user if that owner is an automated user" do
      enable_feature_flag(:codespaces_automated_testing, @user)
      expected_tags = {
        codespaces_automated_testing: true
      }
      all_tags = Codespaces::StatsTagger.new(user: @user).all_tags
      assert_equal expected_tags, all_tags
    end

    test "returns testing tag when there is no user if the vscs_target is not production" do
      codespace = create(:codespace, vscs_target: :ppe)
      all_tags = Codespaces::StatsTagger.new(codespace: codespace).all_tags
      assert_equal true, all_tags[:codespaces_automated_testing]
    end

    test "it allows specific overrides" do
      expected_tags = {
        location: @codespace.location,
        repository: @codespace.repository.id,
        name: "foobar",
        sku_name: @codespace.sku_name,
        from_pr: false,
        from_fork: false,
        vscs_target: @codespace.vscs_target,
        billable_owner_type: @codespace.billable_owner.class.name.downcase,
        is_copilot_workspace: false,
        is_workspace_editor_cloud_environment: false,
      }
      all_tags = Codespaces::StatsTagger.new(codespace: @codespace, name: "foobar").all_tags
      assert_equal expected_tags, all_tags
    end

    test "it passes through unrecognized tags, but notes them in datadog for semconv" do
      expected_tags = { foo: "bar" }
      all_tags = Codespaces::StatsTagger.new(foo: "bar").all_tags
      assert_equal expected_tags, all_tags

      semconv_tags = Codespaces::StatsTagger.new(foo: "bar").all_semconv_tags
      assert_equal expected_tags, semconv_tags
      assert_dogstats_increment(1, "codespaces.stats_tagger.unmapped_semconv_key", tags: ["key:foo"])
    end
  end

  context "#datadog_tags" do
    test "it filters high cardinality data and transforms tags to an array for datadog" do
      enable_feature_flag(:codespaces_automated_testing, @codespace.owner)
      expected_tags = [
        "location:#{@codespace.location}",
        "sku_name:#{@codespace.sku_name}",
        "vscs_target:#{@codespace.vscs_target}",
        "codespaces_automated_testing:true",
        "billable_owner_type:user",
        "is_copilot_workspace:false",
        "is_workspace_editor_cloud_environment:false",
      ]
      datadog_tags = Codespaces::StatsTagger.new(codespace: @codespace).datadog_tags
      assert_same_elements expected_tags, datadog_tags
    end
  end
end
