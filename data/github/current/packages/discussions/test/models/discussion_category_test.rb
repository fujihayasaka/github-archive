# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionCategoryTest < GitHub::TestCase
  include DiscussionsTestHelper
  include HydroTestHelpers
  include StringFromBinaryTestHelper

  fixtures do
    create_discussions_authz_fixtures

    @category = create(:discussion_category, repository: @repo)
    @private_category = create(:discussion_category, repository: @private_repo)
    @org_category = create(:discussion_category, repository: @org_repo)
    @org_private_category = create(:discussion_category, repository: @org_private_repo)
    @business_internal_category = create(:discussion_category, repository: @business_internal_repo)

    @announcements_category = create(:discussion_category,
      repository: @org_repo,
      name: "Cool Announcements",
      supports_announcements: true,
    )

    @org_without_default_permission_repo_category = create(:discussion_category,
      repository: @org_without_default_permission_repo,
    )
    @org_without_default_permission_private_repo_category = create(:discussion_category,
      repository: @org_without_default_permission_private_repo,
    )
  end

  setup do
    @matrix = DiscussionsTestHelper::AccessMatrix.new(self)
    @matrix.setup_subjects(
      repo: @category,
      private_repo: @private_category,
      org_repo: @org_category,
      org_private_repo: @org_private_category,
      org_without_default_permission_repo: @org_without_default_permission_repo_category,
      org_without_default_permission_private_repo: @org_without_default_permission_private_repo_category,
      business_internal_repo: @business_internal_category,
    )
  end

  def matrix_turn_off_discussions
    @matrix.each_repo { |repo, admin| repo.turn_off_discussions(actor: admin, instrument: false) }
  end

  %i[name description emoji].each do |field|
    test "supports emoji for #{field}" do
      encoded_value = "❤️"
      encoded_value2 = "\xE2\x9D\xA4\xEF\xB8\x8F"
      encoded_value3 = "🧪"
      category = create(:discussion_category, field => encoded_value)

      assert_multibyte_tracked_changes(category, field, encoded_value, encoded_value2, encoded_value3)
    end
  end

  context "validations" do
    test "name is stripped on validation" do
      @org_category.name = " my name "

      @org_category.validate

      assert_equal "my name", @org_category.name
    end

    test "requires a present name" do
      category = build :discussion_category, name: ""
      refute_predicate category, :valid?
    end

    test "ensure valid utf8 in name, description, and emoji" do
      %i[name description emoji].each do |attr|
        category = build :discussion_category, attr => "bad \x80 utf8".dup # dup to unfreeze!
        refute_predicate category, :valid?
      end
    end

    test "supports 4-byte unicode name" do
      category = build :discussion_category, name: "𬉼𠳐龦鿯𬉼𠳐龦鿯"
      assert_predicate category, :valid?
      assert category.errors[:slug].empty?
      assert category.save
    end

    test "ensures that :emoji is a single, present, recognized emoji" do
      [":+1:", GRIN_EMOJI].each do |good|
        category = build :discussion_category, emoji: good
        assert_predicate category, :valid?, "did not accept #{good.inspect}"
      end

      [nil, "", ":one::two:", ":notes: extra text :notes:"].each do |bad|
        category = build :discussion_category, emoji: bad
        refute_predicate category, :valid?, "incorrectly accepted #{bad.inspect}"
      end
    end

    test "limits length of emoji" do
      max = GitHub::Validations::SingleEmojiValidator::EMOJI_MAX_LENGTH
      category = DiscussionCategory.new(emoji: "a" * (max + 1))
      refute_predicate category, :valid?
      assert_equal "is too long (maximum is #{max} characters)",
                   category.errors[:emoji].first
    end

    test "emoji field can hold long Unicode emoji" do
      emoji = "👩‍❤️‍💋‍👩"
      category = build(:discussion_category, emoji: emoji)
      assert_predicate category, :valid?
      assert category.save
      assert_equal emoji, category.reload.emoji
    end

    test "emoji field can hold long colon-style emoji" do
      emoji = ":south_georgia_south_sandwich_islands:"
      category = build(:discussion_category, emoji: emoji)
      assert_predicate category, :valid?
      assert category.save
      assert_equal emoji, category.reload.emoji
    end

    test "emoji field disallows more than one native emoji" do
      category = build(:discussion_category, emoji: "#{GRIN_EMOJI}#{GRIN_EMOJI}")
      refute_predicate category, :valid?
      assert_equal "can only be one emoji", category.errors[:emoji].first
    end

    # https://github.com/github/github/issues/109560
    test "emoji field disallows non-emoji text" do
      category = build(:discussion_category, emoji: ":chicken: hello")
      refute_predicate category, :valid?
      assert_equal "can only contain one supported emoji", category.errors[:emoji].first
    end

    test "emoji field requires a supported emoji" do
      category = build(:discussion_category, emoji: ":not-a-real-emoji:")
      refute_predicate category, :valid?
      assert_equal "does not contain a recognized emoji", category.errors[:emoji].first
    end

    test "emoji field cannot contain a custom image" do
      category = build(:discussion_category, emoji: %q(<img src="some-fake-emoji.png">))
      refute_predicate category, :valid?
      assert_equal "does not contain a recognized emoji", category.errors[:emoji].first
    end

    test "emoji field can contain a custom emoji" do
      category = build(:discussion_category, emoji: ":octocat:")
      assert_predicate category, :valid?
    end

    GitHub::Validations::AllowedEmojiValidator::BLOCKED_CUSTOM_EMOJI.each do |emoji_name|
      test "disallows #{emoji_name} colon-style emoji" do
        category = build(:discussion_category, emoji: ":#{emoji_name}:")
        refute_predicate category, :valid?
        assert_equal "contains an emoji that is not allowed", category.errors[:emoji].first
      end
    end

    GitHub::Validations::AllowedEmojiValidator::BLOCKED_NATIVE_EMOJI.each do |emoji_name|
      test "disallows #{emoji_name} colon-style emoji" do
        category = build(:discussion_category, emoji: ":#{emoji_name}:")
        refute_predicate category, :valid?
        assert_equal "contains an emoji that is not allowed", category.errors[:emoji].first
      end

      test "disallows #{emoji_name} Unicode emoji" do
        emoji = Emoji.find_by_alias(emoji_name)
        category = build(:discussion_category, emoji: emoji.raw)
        refute_predicate category, :valid?
        assert_equal "contains an emoji that is not allowed", category.errors[:emoji].first
      end
    end

    test "bounds to MAX_CATEGORIES_PER_REPO categories within a repository" do
      repo = create(:repository, has_discussions: true)
      repo.discussion_categories.destroy_all
      create_list(:discussion_category, 3, repository: repo)

      DiscussionCategory.stub_const(:MAX_CATEGORIES_PER_REPO, 3) do
        category = build(:discussion_category, repository: repo)
        refute_predicate category, :valid?
        assert_equal ["Repository can only have a maximum of 3 categories"], category.errors.full_messages
      end
    end

    test "allows for max categories override limit" do
      repo = create(:repository, has_discussions: true)
      repo.discussion_categories.destroy_all
      create_list(:discussion_category, 3, repository: repo)
      DiscussionCategory.stub_const(:MAX_CATEGORIES_PER_REPO, 3) do
        DiscussionCategory::LimitOverride.stub_const(:MINIMUM_LIMIT, 4) do
          override = DiscussionCategory::LimitOverride.new(
            repository: repo,
            actor: create(:staff_admin_user)
          )
          result = override.set(limit: 4)
          assert_predicate result, :success?
          assert_equal 4, DiscussionCategory::LimitOverride.for(repo)

          category = build(:discussion_category, repository: repo)
          assert_predicate category, :valid?
        end
      end
    end
  end

  context "sorting of .discussion_categories scope" do
    test "orders alphabetically" do
      repo = create(:repository)
      categories = %w(TIL General Abc Thanks aardvark).map do |name|
        repo.discussion_categories.create(name: name)
      end

      sorted_names = repo.discussion_categories.pluck(:name)
      assert_equal %w(aardvark Abc General Thanks TIL), sorted_names
    end
  end

  context "#readable_by? and #async_readable_by?" do
    test "requires read+" do
      @matrix.user_scenarios(
        :readable_by?,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when discussions is turned off" do
      matrix_turn_off_discussions

      @matrix.user_scenarios(
        :readable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "true for anonymous user in a public repository" do
      assert @category.readable_by?(nil)
      assert @category.async_readable_by?(nil).sync
    end

    test "false for anonymous user in a private repository" do
      refute @private_category.readable_by?(nil)
      refute @private_category.async_readable_by?(nil).sync
    end

    test "requires read+ for bots" do
      @matrix.bot_scenarios(
        :readable_by?,
        install_needed: false,
        discussions_permission_needed: false,
        none: false,
        read: true,
        write: true,
      )
    end

    test "false for bots when discussions are turned off" do
      matrix_turn_off_discussions

      @matrix.bot_scenarios(
        :readable_by?,
        install_needed: false,
        discussions_permission_needed: false,
        none: false,
        read: false,
        write: false,
      )
    end
  end

  context "#deleting?" do
    test "false for categories that are not being deleted" do
      refute_predicate @category, :deleting?
    end

    test "true for categories that have been marked for deletion" do
      to_delete = create :discussion_category
      to_delete.mark_as_deleting!
      assert_predicate to_delete, :deleting?
    end

    test "false for categories that are marked then unmarked for deletion" do
      to_delete = create :discussion_category
      to_delete.mark_as_deleting!
      to_delete.unmark_as_deleting!
      refute_predicate to_delete, :deleting?
    end

    test "times out KV entries on destroy" do
      to_delete = create :discussion_category
      now = Time.now

      Timecop.freeze(now) { to_delete.mark_as_deleting! }

      Timecop.freeze(now + 10.minutes) do
        refute_predicate to_delete, :deleting?
      end
    end
  end

  context ".any_not_deleting?" do
    test "returns true if at least one category is not marked for deletion" do
      categories = create_list :discussion_category, 3

      assert DiscussionCategory.any_not_deleting?(categories)

      categories[0].mark_as_deleting!
      assert DiscussionCategory.any_not_deleting?(categories)
    end

    test "returns false if all categories are marked for deletion" do
      categories = create_list :discussion_category, 3
      categories.each(&:mark_as_deleting!)

      refute DiscussionCategory.any_not_deleting?(categories)
    end

    test "returns false if the list is empty" do
      refute DiscussionCategory.any_not_deleting?([])
    end
  end

  context "#deletable_by?" do
    test "requires maintainer+ for users" do
      @matrix.user_scenarios(
        :deletable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: true,
        admin: true,
      )
    end
  end

  context "#modifiable_by?" do
    test "requires triage+ for users" do
      @matrix.user_scenarios(
        :modifiable_by?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end
  end

  context "v1 Hydro events", skip_enterprise: true do
    test "does not log creation events for seeded category" do
      assert_difference(-> { DiscussionCategory.count }, DiscussionCategory.initial_categories.size) do
        create :repository, has_discussions: true
      end

      refute_hydro_messages schema: "github.discussions.v1.DiscussionCategoryCreate"
    end

    test "logs event on creation" do
      category = create :discussion_category, repository: @repo, actor: @rando

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        discussion_category: Hydro::EntitySerializer.discussion_category(category),
        repository: Hydro::EntitySerializer.repository(@repo),
        repository_owner: Hydro::EntitySerializer.user(@repo.owner),
        actor: Hydro::EntitySerializer.user(@rando),
      }
      assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCategoryCreate")
      assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCategoryCreate")
    end

    test "logs event on update" do
      @category.actor = @rando
      @category.update!(supports_mark_as_answer: false)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        discussion_category: Hydro::EntitySerializer.discussion_category(@category),
        repository: Hydro::EntitySerializer.repository(@repo),
        repository_owner: Hydro::EntitySerializer.user(@repo.owner),
        actor: Hydro::EntitySerializer.user(@rando),
      }
      assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCategoryUpdate")
      assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCategoryUpdate")
    end

    test "does not log an update event when nothing has changed" do
      @category.actor = @rando
      @category.update!({})

      refute_hydro_messages schema: "github.discussions.v1.DiscussionCategoryUpdate"
    end

    test "logs event on deletion" do
      @category.actor = @rando
      @category.destroy

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        discussion_category: Hydro::EntitySerializer.discussion_category(@category),
        repository: Hydro::EntitySerializer.repository(@repo),
        repository_owner: Hydro::EntitySerializer.user(@repo.owner),
        actor: Hydro::EntitySerializer.user(@rando),
      }
      assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCategoryDelete")
      assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCategoryDelete")
    end
  end

  context "v2 DiscussionsCategory Hydro event publishing", skip_enterprise: true do
    test "does not publish creation events for seeded category" do
      assert_difference(-> { DiscussionCategory.count }, DiscussionCategory.initial_categories.size) do
        create :repository, has_discussions: true
      end

      refute_hydro_messages schema: "github.discussions.v2.DiscussionsCategory"
    end

    test "does not publish an update event when nothing has changed" do
      @category.actor = @rando
      @category.update!({})

      refute_hydro_messages schema: "github.discussions.v2.DiscussionsCategory"
    end

    test "publishes event on creation with actor" do
      travel_to Time.now do
        category = create :discussion_category, repository: @repo, actor: @rando
        expected_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@repo.owner),
          actor_id: @rando.id,
          actor: Hydro::EntitySerializer.user(@rando),
          action: :ACTION_DISCUSSION_CREATED,
          action_timestamp: category.created_at,
          category_id: category.id,
          discussion_format: category.discussion_format,
          category_name: category.name,
          discussion_section_id: category.discussion_section_id,
        }

        assert_hydro_published(expected_message, schema: "github.discussions.v2.DiscussionsCategory")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsCategory")
      end
    end

    test "publishes event on creation without actor" do
      travel_to Time.now do
        category = create :discussion_category, repository: @repo, actor: nil
        expected_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@repo.owner),
          actor_id: nil,
          actor: nil,
          action: :ACTION_DISCUSSION_CREATED,
          action_timestamp: category.created_at,
          category_id: category.id,
          discussion_format: category.discussion_format,
          category_name: category.name,
        }

        assert_hydro_published(expected_message, schema: "github.discussions.v2.DiscussionsCategory")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsCategory")
      end
    end

    test "publishes event on update with actor" do
      travel_to Time.now do
        category = create :discussion_category, repository: @repo, actor: @rando
        reset_hydro
        category.update!(supports_mark_as_answer: false)

        expected_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@repo.owner),
          actor_id: @rando.id,
          actor: Hydro::EntitySerializer.user(@rando),
          action: :ACTION_DISCUSSION_UPDATED,
          action_timestamp: Time.now,
          category_id: category.id,
          discussion_format: category.discussion_format,
          category_name: category.name,
        }
        assert_hydro_published(expected_message, schema: "github.discussions.v2.DiscussionsCategory")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsCategory")
      end
    end

    test "publishes event on update without actor" do
      travel_to Time.now do
        category = create :discussion_category, repository: @repo
        reset_hydro
        category.update!(supports_mark_as_answer: false)

        expected_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@repo.owner),
          actor_id: nil,
          actor: nil,
          action: :ACTION_DISCUSSION_UPDATED,
          action_timestamp: Time.now,
          category_id: category.id,
          discussion_format: category.discussion_format,
          category_name: category.name,
        }
        assert_hydro_published(expected_message, schema: "github.discussions.v2.DiscussionsCategory")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsCategory")
      end
    end

    test "publishes event on deletion with actor" do
      travel_to Time.now do
        category = create :discussion_category, repository: @repo, actor: @rando
        reset_hydro
        category.destroy

        expected_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@repo.owner),
          actor_id: @rando.id,
          actor: Hydro::EntitySerializer.user(@rando),
          action: :ACTION_DISCUSSION_DELETED,
          action_timestamp: Time.now,
          category_id: category.id,
          discussion_format: category.discussion_format,
          category_name: category.name,
        }

        assert_hydro_published(expected_message, schema: "github.discussions.v2.DiscussionsCategory")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsCategory")
      end
    end

    test "publishes event on deletion without actor" do
      travel_to Time.now do
        category = create :discussion_category, repository: @repo
        reset_hydro
        category.destroy

        expected_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@repo.owner),
          actor_id: nil,
          actor: nil,
          action: :ACTION_DISCUSSION_DELETED,
          action_timestamp: Time.now,
          category_id: category.id,
          discussion_format: category.discussion_format,
          category_name: category.name,
        }

        assert_hydro_published(expected_message, schema: "github.discussions.v2.DiscussionsCategory")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsCategory")
      end
    end
  end

  test "generates a URL-friendly slug from the stripped name" do
    category = create :discussion_category, name: "This   Is a. weird? category NAME #{GRIN_EMOJI}"
    assert_equal "this-is-a-weird-category-name", category.slug

    category.name = " and now it's changed "
    category.save!
    assert_equal "and-now-it-s-changed", category.slug

    category.name = "你好"
    category.save!
    assert_equal "你好", category.slug
  end

  test "validates that each slug is unique within the repository" do
    create :discussion_category, repository: @repo, name: "same"

    same_slug = build :discussion_category, repository: @repo, name: "Same."
    refute_predicate same_slug, :valid?

    different_slug = build :discussion_category, repository: @repo, name: "Different"
    assert_predicate different_slug, :valid?

    different_repo = build :discussion_category, repository: @private_repo, name: "same"
    assert_predicate different_slug, :valid?
  end

  context "Announcements", skip_enterprise: true do
    test "supports announcements" do
      @general_category = @repo.discussion_categories.find_by(slug: "general")
      @announcements_category = @repo.discussion_categories.find_by(slug: "announcements")
      @announcements_category ||= create(:discussion_category, repository: @repo, name: "Announcements", supports_announcements: true)

      refute_predicate @general_category, :supports_announcements?
      assert_predicate @announcements_category, :supports_announcements?
    end

    test "adds an initial category called announcements" do
      category = DiscussionCategory.initial_categories.first

      refute_nil category
      assert_equal "Announcements", T.must(category)[:name]
    end
  end

  context "#compatible_for_team_posts_transfer?" do
    test "true if name matches and does not support qa, announcements, or polls" do
      category = create(
        :discussion_category,
        repository: @repo,
        name: "Team Posts",
        supports_announcements: false,
        supports_mark_as_answer: false,
        supports_polls: false
      )

      assert_predicate category, :compatible_for_team_posts_transfer?
    end

    test "name matching is case-insensitive" do
      category = create(
        :discussion_category,
        repository: @repo,
        name: "TEAM posts",
        supports_announcements: false,
        supports_mark_as_answer: false,
        supports_polls: false
      )

      assert_predicate category, :compatible_for_team_posts_transfer?
    end

    test "false if support qa, announcements, or polls" do
      category = create(
        :discussion_category,
        repository: @repo,
        name: "Team Posts",
        supports_announcements: true,
        supports_mark_as_answer: false,
        supports_polls: false
      )

      refute_predicate category, :compatible_for_team_posts_transfer?
    end
  end
end

class DiscussionTemplateMethodTest < GitHub::TestCase
  fixtures do
    @repo  = create(:repository, has_discussions: true, from_example: :simple)
    @owner = @repo.owner
    commit = @repo.commits.create({ message: "Add templates", author: @owner }) do |files|
      files.add ".github/DISCUSSION_TEMPLATE/announcements.yml", <<~YAML
      ---
      body:
      - type: input
        attributes:
          label: "what are you announcing?"
      YAML
    end

    @repo.refs["refs/heads/master"].update(commit, @repo.owner)
  end

  context "#template" do
    test "returns a template for category" do
      category = @repo.discussion_categories.find_by(slug: "announcements")

      assert_equal "announcements", category.template.category_slug
    end

    test "returns nil if template does not exist" do
      category = @repo.discussion_categories.find_by(slug: "general")

      assert_nil category.template
    end
  end
end
