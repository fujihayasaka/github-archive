# typed: false
# frozen_string_literal: true

require "test_helper"

class AchievableTest < GitHub::TestCase
  context ".with_slug" do
    test "it returns the proper achievable from the given slug" do
      assert_instance_of Achievable::DustBunny, Achievable.with_slug("dust-bunny")
    end
  end

  context ".display_name" do
    test "it returns the display name for the achievable class" do
      assert_equal "Dust Bunny", Achievable::DustBunny.display_name
    end
  end

  context ".slug" do
    test "it returns the slug for the achievable class" do
      assert_equal "dust-bunny", Achievable::DustBunny.slug
    end
  end

  context ".feature_flag_name" do
    test "it returns the name of the feature flag used to control this specific Achievable class" do
      assert_equal :achievements_dust_bunny, Achievable::DustBunny.feature_flag_name
    end
  end

  context ".enabled?" do
    test "it returns true when the feature is enabled" do
      GitHub.flipper[Achievable::DustBunny.feature_flag_name].enable

      assert_predicate Achievable::DustBunny, :enabled?
    end

    test "it returns false when the feature is disabled" do
      GitHub.flipper[Achievable::DustBunny.feature_flag_name].disable

      refute_predicate Achievable::DustBunny, :enabled?
    end
  end

  context "well-known instances" do
    test "enumerates well-known instances of all achievable subclasses" do
      seen_classes = Set.new
      Achievable.all_known do |achievable|
        assert_kind_of Achievable, achievable
        refute_includes seen_classes, achievable.class, "expected #{achievable.class} to only be seen once"
        assert_same achievable, achievable.class.instance, "incorrect slug registration for #{achievable.class}"

        seen_classes << achievable.class
      end
      refute_empty seen_classes, "expected .all_known to yield at least one achievable"
    end
  end

  context "#display_name" do
    test "it returns the titleized name of the achievable" do
      dust_bunny_achievable = create(:achievable, :dust_bunny)

      assert_equal "Dust Bunny", dust_bunny_achievable.display_name
    end
  end

  context "#slug" do
    test "it returns a parameterized version of the name" do
      dust_bunny_achievable = create(:achievable, :dust_bunny)

      assert_equal "dust-bunny", dust_bunny_achievable.slug
    end
  end

  context "#feature_flag_name" do
    test "it returns the name of the feature flag used to control this specific Achievable instance" do
      dust_bunny_achievable = create(:achievable, :dust_bunny)

      assert_equal :achievements_dust_bunny, dust_bunny_achievable.feature_flag_name
    end
  end

  context "#skin_tone_name_at_tier" do
    test "returns the name of a skin tone of a tone-able Achievable" do
      assert_equal "light-medium", create(:achievable, :quickdraw).skin_tone_name_at_tier(tier: 0, tone: 2)
    end

    test "returns the name of a skin tone of a multi-tier Achievable at a toneable tier" do
      assert_equal "medium-dark", create(:achievable, :starstruck).skin_tone_name_at_tier(tier: 0, tone: 4)
    end

    test "returns nil for a non-tone-able Achievable" do
      assert_nil create(:achievable, :pull_shark).skin_tone_name_at_tier(tier: 0, tone: 3)
    end

    test "returns nil for a multi-tier Achievable at a non-toneable tier" do
      assert_nil create(:achievable, :starstruck).skin_tone_name_at_tier(tier: 1, tone: 5)
    end

    test "returns nil for an unrecognized tone number" do
      assert_nil create(:achievable, :quickdraw).skin_tone_name_at_tier(tier: 0, tone: 7)
    end
  end

  context "#tiers" do
    test "it returns the tiers of the achievable" do
      Achievable::PullShark.stubs(:defined_tiers).returns([
        Achievable::Tier.new(0, 1, Achievable::PullShark),
        Achievable::Tier.new(1, 2, Achievable::PullShark),
        Achievable::Tier.new(2, 3, Achievable::PullShark),
      ])

      pull_shark_achievable = create(:achievable, :pull_shark)

      assert_equal [0, 1, 2], pull_shark_achievable.tiers.to_a
    end
  end

  context "#highest_tier" do
    test "it returns the highest tier of the achievable" do
      Achievable::PullShark.stubs(:defined_tiers).returns([
        Achievable::Tier.new(0, 1, Achievable::PullShark),
        Achievable::Tier.new(1, 2, Achievable::PullShark),
        Achievable::Tier.new(2, 3, Achievable::PullShark),
      ])

      pull_shark_achievable = create(:achievable, :pull_shark)

      assert_equal 2, pull_shark_achievable.highest_tier
    end
  end

  context "#tier" do
    test "returns the tier object of a valid tier" do
      Achievable::PullShark.stubs(:defined_tiers).returns([
        Achievable::Tier.new(0, 10, Achievable::PullShark),
        Achievable::Tier.new(1, 20, Achievable::PullShark),
      ])

      pull_shark_achievable = create(:achievable, :pull_shark)

      tier0 = pull_shark_achievable.tier(0)
      assert_predicate tier0, :valid?
      assert_equal 0, tier0.index
      assert_equal "default", tier0.name
      assert_equal 10, tier0.threshold
      assert_equal "%{achieving_user_login} opened pull requests that have been merged.", tier0.description_template

      tier1 = pull_shark_achievable.tier(1)
      assert_predicate tier1, :valid?
      assert_equal 1, tier1.index
      assert_equal "bronze", tier1.name
      assert_equal 20, tier1.threshold
      assert_equal "%{achieving_user_login} opened pull requests that have been merged.", tier1.description_template
    end

    test "returns a null tier for an invalid tier ordinal" do
      Achievable::PullShark.stubs(:defined_tiers).returns([
        Achievable::Tier.new(0, 10, Achievable::PullShark),
        Achievable::Tier.new(1, 20, Achievable::PullShark),
      ])

      pull_shark_achievable = create(:achievable, :pull_shark)

      null_tier = pull_shark_achievable.tier(2)
      refute_predicate null_tier, :valid?
      assert_equal 2, null_tier.index
      assert_equal "silver", null_tier.name
      assert_equal 0, null_tier.threshold
      assert_equal "Whoops! Invalid tier for this achievement.", null_tier.description_template
    end
  end

  context ".unlocking_explanation_template" do
    test "returns the unlocking event explanation template configured in each subclass" do
      assert_equal "Commit message contains \"linter\"",
        create(:achievable, :dust_bunny).unlocking_explanation_template

      # %{..} interpolation templates are left intact. (They'll be populated within a call to
      # Profiles::User::Achievements::BaseComponent#render_text_with_substitutions.)
      assert_equal "%{threshold_ordinal} accepted answer",
        create(:achievable, :galaxy_brain).unlocking_explanation_template
    end
  end

  context ".accepted_unlocking_model_types and .needs_unlocking_oid?" do
    test "returns a single, exact unlocking model type" do
      open_sourcerer = create(:achievable, :open_sourcerer)
      assert_same_elements ["PullRequest"], open_sourcerer.accepted_unlocking_model_types
      refute_predicate open_sourcerer, :needs_unlocking_oid?
      refute_predicate open_sourcerer, :has_dynamic_unlocking_model?
    end

    test "returns issue-like model types" do
      heartbreaker = create(:achievable, :heartbreaker)
      assert_same_elements %w[Issue PullRequest], heartbreaker.accepted_unlocking_model_types
      refute_predicate heartbreaker, :needs_unlocking_oid?
      refute_predicate heartbreaker, :has_dynamic_unlocking_model?
    end

    test "returns reactable model types" do
      heart_on_your_sleeve = create(:achievable, :heart_on_your_sleeve)
      assert_includes heart_on_your_sleeve.accepted_unlocking_model_types, "IssueComment"
      refute_predicate heart_on_your_sleeve, :needs_unlocking_oid?
      refute_predicate heart_on_your_sleeve, :has_dynamic_unlocking_model?
    end

    test "returns Repository and unlocking oid requirement for commit model types" do
      dust_bunny = create(:achievable, :dust_bunny)
      assert_same_elements ["Repository"], dust_bunny.accepted_unlocking_model_types
      assert_predicate dust_bunny, :needs_unlocking_oid?
      refute_predicate dust_bunny, :has_dynamic_unlocking_model?
    end

    test "returns fixed type and reports true for virtual unlocking model type" do
      acv = create(:achievable, :arctic_code_vault_contributor)
      assert_same_elements ["AchievementRepositoryList"], acv.accepted_unlocking_model_types
      refute_predicate acv, :needs_unlocking_oid?
      assert_predicate acv, :has_dynamic_unlocking_model?
    end
  end

  test "all subclasses of Achievable have valid tiers" do
    Achievable.all_known do |achievable|
      achievable.tiers.inject(nil) do |last_tier, index|
        tier = achievable.tier(index)
        assert_predicate tier, :valid?, "#{achievable.display_name} has an invalid tier #{index}"
        refute_nil tier.name, "#{achievable.display_name} has an unnamed tier #{index}"

        if last_tier
          assert_operator tier.threshold, :>, last_tier.threshold,
            "#{achievable.display_name} has its tiers out of order"
        end

        tier
      end
    end
  end

  test "all subclasses of Achievable have valid unlocking event specifications" do
    Achievable.all_known do |achievable|
      refute_nil achievable.unlocking_explanation_template
      refute_empty achievable.accepted_unlocking_model_types
    end
  end

  test "all subclasses of Achievable set a valid mobile background color" do
    missing = []
    incorrect = []

    Achievable.all_known do |achievable|
      missing << achievable if achievable.background_color.nil?
      unless achievable.background_color =~ /\A#[0-9a-fA-F]{6}\z/
        incorrect << [achievable, achievable.background_color]
      end
    end

    assert_empty missing, <<~ERR
      The following Achievable classes are missing a mobile background color:
        #{missing.map(&:display_name).join(", ")}
      Please add a call to mobile_background_color.
    ERR
    assert_empty incorrect, <<~ERR
      The following Achievable classes specify an invalid mobile background color:
        #{incorrect.map { |a, c| "#{a.display_name} (#{c})" }.join(", ")}
      Please use a hex color code with 6 digits, e.g. #123456.
    ERR
  end

  test "all achievement badge image assets are present" do
    expected_images = []

    Achievable.all_known do |achievable|
      achievable.tiers.each do |tier_index|
        expected_images << achievable.badge_asset_path(tier: tier_index)
        if achievable.uses_skin_tone?(tier: tier_index)
          Achievable::SKIN_TONE_NAMES.keys.each do |tone|
            expected_images << achievable.badge_asset_path(
              tier: tier_index,
              skin_tone_block: -> { tone },
            )
          end
        end
      end
    end

    missing_images = expected_images.reject do |image_module_path|
      File.exist?(Rails.root.join("public/#{image_module_path}"))
    end

    assert_empty missing_images, "Required achievement badge images are missing"
  end

  test "all achievement social card image assets are present" do
    expected_images = []

    Achievable.all_known do |achievable|
      achievable.tiers.each do |tier_index|
        expected_images << achievable.social_card_asset_url(tier: tier_index).delete_prefix(GitHub.asset_host_url + "/")
        if achievable.uses_skin_tone?(tier: tier_index)
          Achievable::SKIN_TONE_NAMES.keys.each do |tone|
            expected_images << achievable.social_card_asset_url(
              tier: tier_index,
              skin_tone_block: -> { tone },
            ).delete_prefix(GitHub.asset_host_url + "/")
          end
        end
      end
    end

    missing_images = expected_images.reject do |image_module_path|
      File.exist?(Rails.root.join("public/#{image_module_path}"))
    end

    assert_empty missing_images, "Required achievement badge images are missing"
  end

  test "all achievement high-resolution badge image assets are present" do
    missing_images = []

    Achievable.all_known do |achievable|
      expected_asset_path = achievable.high_resolution_asset_url.delete_prefix(GitHub.asset_host_url + "/")
      missing_images << expected_asset_path unless File.exist?(Rails.root.join("public", expected_asset_path))
    end

    assert_empty missing_images, "Required high-resolution achievement badge images are missing"
  end

  test "all achievements that expect a rounded badge variant have a corresponding asset" do
    missing_images = []

    Achievable.all_known do |achievable|
      next unless achievable.has_rounded_badge_variant?
      expected_asset_path = achievable.rounded_badge_asset_url.delete_prefix(GitHub.asset_host_url + "/")
      missing_images << expected_asset_path unless File.exist?(Rails.root.join("public", expected_asset_path))
    end

    assert_empty missing_images, "Required rounded achievement badge images are missing"
  end

  context ".known_slugs" do
    test "returns an array of all the known achievement slugs" do
      assert_same_elements Achievable.known_slugs, Achievable.all_known.map(&:slug)
    end
  end

  test "all achievement detail gradient image assets are present" do
    missing_images = []

    Achievable.all_known do |achievable|
      detail_gradient_path = achievable.gradient_asset_url.delete_prefix(GitHub.asset_host_url + "/")
      missing_images << detail_gradient_path unless File.exist?(Rails.root.join("public", detail_gradient_path))
    end

    assert_empty missing_images, "Required achievement detail gradient images are missing"
  end

  context ".badge_asset_path" do
    test "does not call an unused skin tone block" do
      called = false
      call_me_not = lambda do
        called = true
        999
      end

      Achievable::PullShark.badge_asset_path(tier: 1, skin_tone_block: call_me_not)

      refute called
    end
  end
end
