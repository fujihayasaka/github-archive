# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryDiscussionsDependencyTest < GitHub::TestCase
  include DiscussionsTestHelper
  include FineGrainedPermissionsTestHelper
  include NewsiesHelper

  fixtures do
    create_discussions_authz_fixtures

    @owner.watch_repo(@repo)

    @repo_without_discussions = create(:repository, owner: @owner, has_discussions: false)
    @private_repo_without_discussions = create(:private_repository, owner: @owner, has_discussions: false)

    @global_repo = create(:repository,
      owner: @org_repo.owner,
      name: Repository::GLOBAL_HEALTH_FILES_NAME,
    )
    @staff = create(:staff_admin_user)
  end

  setup do
    @polls_category_notice_date = UserNotice.find("discussions_polls_category").effective_at
    @repo_from_before_polls_category_notice = travel_to(@polls_category_notice_date - 1.day) do
      create(:repository, owner: @owner, has_discussions: true)
    end

    example_repo :simple, @org_repo
    example_repo :simple, @global_repo
  end

  SEED_CATEGORY_NAMES = DiscussionCategory.initial_categories.map { |attrs| attrs[:name] }

  def ensure_announcement_category(repo)
    announcements_category = repo.discussion_categories.find_by(slug: "announcements")
    announcements_category ||= create(:discussion_category,
      repository: repo,
      name: DiscussionCategory::ANNOUNCEMENTS_NAME,
      supports_announcements: true,
    )
  end

  setup do
    enable_notifications_for_user(@owner)

    @matrix = AccessMatrix.new(self)
    @matrix.setup_repo_subjects
  end

  context "#eligible_for_discussions?" do
    test "returns true if the repository is private" do
      assert_predicate @private_repo_without_discussions, :eligible_for_discussions?
    end

    test "returns true for public repositories" do
      assert_predicate @org_repo, :eligible_for_discussions?
    end

    if GitHub.enterprise?
      test "returns true in test mode for a public repo on enterprise" do
        assert_predicate @org_repo, :eligible_for_discussions?
      end
    end
  end

  context "#discussion_creation_requires_explicit_permission? and its async form" do
    test "true when repo is owned by an org and readers aren't allowed to create discussions" do
      @org.block_readers_from_creating_discussions(actor: @org_admin)
      assert_predicate @org_repo, :discussion_creation_requires_explicit_permission?
      assert @org_repo.async_discussion_creation_requires_explicit_permission?.sync
    end

    test "false when repo is owned by a user" do
      refute_predicate @repo, :discussion_creation_requires_explicit_permission?
      refute @repo.async_discussion_creation_requires_explicit_permission?.sync
    end

    test "false when repo is owned by an org and readers are allowed to create discussions" do
      @org.allow_readers_to_create_discussions(actor: @org_admin)
      refute_predicate @org_repo, :discussion_creation_requires_explicit_permission?
      refute @org_repo.async_discussion_creation_requires_explicit_permission?.sync
    end
  end

  context "#can_toggle_discussions_setting?" do
    test "requires maintain+ for users" do
      @matrix.user_scenarios(
        :can_toggle_discussions_setting?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: true,
        admin: true,
      )
    end

    test "true for user without a verified email address" do
      @owner.emails.map(&:unverify!)
      assert @repo.can_toggle_discussions_setting?(@owner)
    end
  end

  context "#can_convert_issues_to_discussions?" do
    test "requires triage+ for users" do
      @matrix.user_scenarios(
        :can_convert_issues_to_discussions?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "true for custom role with FGP granted" do
      user = create(:verified_user)
      org = create(:business_plus_organization, admin: user)
      org_repo = create(:repository, owner: org, has_discussions: true)

      grant_custom_role(
        user: user,
        target: org_repo,
        fgps: [:convert_issues_to_discussions],
      )
      assert org_repo.can_convert_issues_to_discussions?(user)
    end

    test "false when repo has discussions off" do
      refute @repo_without_discussions.can_convert_issues_to_discussions?(@owner)
    end

    if GitHub.email_verification_enabled?
      test "false for user without a verified email address" do
        @owner.emails.map(&:unverify!)
        refute @repo.can_convert_issues_to_discussions?(@owner)
      end
    else
      test "true for user without a verified email address" do
        @owner.emails.map(&:unverify!)
        assert @repo.can_convert_issues_to_discussions?(@owner)
      end
    end
  end

  context "#discussions_on?" do
    test "begins off by default for user-owned repositories" do
      repo = create(:repository, owner: @owner)

      refute_predicate repo, :discussions_on?
    end

    test "begins off by default for org-owned repositories" do
      # We used to default has_discussions to true for repositories created within an organization, hence this oddly
      # specific separate test.
      repo = create(:org_owned_repository)

      refute_predicate repo, :discussions_on?
    end

    test "is true if the configuration value is true" do
      repo = create(:repository, owner: @owner)
      repo.turn_on_discussions(actor: @owner, instrument: false)

      assert_predicate repo, :discussions_on?
    end
  end

  context "#populate_initial_discussion_categories" do
    test "creates seed categories when creating a repository with has_discussions enabled" do
      repo = create(:repository, has_discussions: true)
      assert_same_elements SEED_CATEGORY_NAMES, repo.discussion_categories.unscope(where: :name).pluck(:name)
    end

    test "creates seed categories when has_discussions is changed to true" do
      repo = create(:repository, has_discussions: false)
      assert_predicate repo.discussion_categories, :empty?

      repo.turn_on_discussions(actor: repo.owner, instrument: false)

      assert_same_elements SEED_CATEGORY_NAMES, repo.discussion_categories.unscope(where: :name).pluck(:name)
    end

    test "does not create seed categories if the repository is created with them" do
      categories = build_pair(:discussion_category)
      repo = create(:repository, has_discussions: true, discussion_categories: categories)
      assert_same_elements categories, repo.discussion_categories
    end

    test "does not create seed categories if the repository already has some" do
      categories = build_pair(:discussion_category)
      repo = create(:repository, has_discussions: false, discussion_categories: categories)
      assert_same_elements categories, repo.discussion_categories

      repo.turn_on_discussions(actor: repo.owner, instrument: false)

      assert_same_elements categories, repo.discussion_categories
    end
  end

  context "#fallback_discussion_category!" do
    test "returns 'General' if a category called 'General' exists" do
      general_category = @repo.discussion_categories.find_by!(name: DiscussionCategory::GENERAL_NAME)
      assert_equal general_category, @repo.fallback_discussion_category!
    end

    test "returns an arbitrary non-nil category if no category called 'General' exists" do
      repo = create(:repository, has_discussions: true)
      repo.discussion_categories.destroy_all
      categories = create_list :discussion_category, 3, repository: repo
      repo.discussion_categories.reset

      assert_includes categories, repo.fallback_discussion_category!
    end

    test "raises an exception if the receiver has no associated categories" do
      repo = create(:repository, has_discussions: true)
      repo.discussion_categories.destroy_all

      assert_raises(ActiveRecord::RecordNotFound) { repo.fallback_discussion_category! }
    end
  end

  context "#team_post_category!" do
    test "creates the category if doesn't exist" do
      assert_difference(-> { @repo.discussion_categories.count }, 1) do
        @repo.team_post_category!
      end

      assert @repo.discussion_categories.exists?(name: "Team Posts")
    end

    test "finds the category if it exists" do
      category = @repo.discussion_categories.create!(DiscussionCategory::TEAM_POST_MIGRATION_CATEGORY)
      assert_difference(-> { @repo.discussion_categories.count }, 0) do
        @repo.team_post_category!
      end

      assert_equal category.id, @repo.team_post_category!.id
    end

    test "raises an exception if category cannot be created" do
      DiscussionCategory.stub_const(:MAX_CATEGORIES_PER_REPO, 10) do
        create_list(:discussion_category, 4, repository: @repo)

        assert_raises(ActiveRecord::RecordInvalid) do
          @repo.team_post_category!
        end
      end
    end
  end

  context "#available_discussion_categories" do
    test "returns categories available for the repository" do
      repo = create(:repository, has_discussions: true)
      assert_same_elements SEED_CATEGORY_NAMES, repo.available_discussion_categories.pluck(:name)
    end
  end

  context "#available_discussion_categories_for_actor" do
    test "returns categories that are available for the user" do
      user_repo = create(:repository, owner: @owner, has_discussions: true)

      @non_owner_user = create(:verified_user)

      assert_includes user_repo.available_discussion_categories_for_actor(@owner).map(&:name), "Announcements"
      refute_includes user_repo.available_discussion_categories_for_actor(@non_owner_user).map(&:name), "Announcements"
    end
  end

  context "#discussions_active?" do
    test "returns true when the repo has discussions turned on" do
      assert_predicate @org_repo, :discussions_active?
      assert_predicate @private_repo, :discussions_active?
      assert @org_repo.async_discussions_active?.sync
      assert @private_repo.async_discussions_active?.sync
    end

    test "returns false when discussions are turned off" do
      @repo.turn_off_discussions(actor: @owner, instrument: false)
      @private_repo.turn_off_discussions(actor: @owner, instrument: false)

      refute_predicate @repo, :discussions_active?
      refute_predicate @private_repo, :discussions_active?

      refute @repo.async_discussions_active?.sync
      refute @private_repo.async_discussions_active?.sync
    end
  end

  context "#discussions_ever_active?" do
    test "returns false when the repo has never had discussions turned on" do
      never = create(:repository, has_discussions: false)
      refute_predicate never, :discussions_ever_active?
    end

    test "returns true when the repo has discussions on" do
      assert_predicate @repo, :discussions_ever_active?
    end

    test "returns true when the repo has discussions turned on then back off" do
      @repo.turn_off_discussions(actor: @owner, instrument: false)

      assert_predicate @repo, :discussions_ever_active?
    end

    test "returns false when discussions are not available on this platform" do
      GitHub.stubs(:discussions_available_on_platform?).returns(false)

      refute_predicate @repo, :discussions_ever_active?
    end
  end

  context "#show_landing_page?" do
    test "returns false when the viewer is anonymous/nil" do
      refute @repo_without_discussions.show_landing_page?(nil)
    end

    test "returns false when the viewer has dismissed the repository notice" do
      @owner.dismiss_repository_notice("discussions_tab", repository_id: @repo.id)
      refute @repo_without_discussions.show_landing_page?(@owner)
    end

    test "returns false when the viewer cannot toggle the discussions setting" do
      refute @repo_without_discussions.show_landing_page?(@rando)
    end

    test "returns false when discussions has already been enabled then disabled" do
      @repo.turn_off_discussions(actor: @owner, instrument: false)
      refute @repo.show_landing_page?(@owner)
    end

    test "returns false for private repos" do
      refute @private_repo_without_discussions.show_landing_page?(@owner)
    end

    test "returns false when repo has 4 or fewer issues" do
      create_list(:issue, 4, repository: @repo_without_discussions)
      refute @repo_without_discussions.show_landing_page?(@owner)
    end

    test "returns true when all conditions are met" do
      create_list(:issue, 5, repository: @repo_without_discussions)
      assert @repo_without_discussions.show_landing_page?(@owner)
    end
  end

  context "#can_create_discussion_announcements? and #async_can_create_discussion_announcements?" do
    test "requires maintain+ for users" do
      @matrix.user_scenarios(
        :can_create_discussion_announcements?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: true,
        admin: true,
      )
    end

    test "false when repository is archived" do
      @matrix.each_repo do |repo, _admin|
        ensure_announcement_category(repo)
        repo.set_archived
      end

      @matrix.user_scenarios(
        :can_create_discussion_announcements?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    if GitHub.email_verification_enabled?
      test "false when user does not have a verified email" do
        ensure_announcement_category(@org_repo)

        @admin.emails.map(&:unverify!)
        refute @org_repo.can_create_discussion_announcements?(@admin)
        refute @org_repo.async_can_create_discussion_announcements?(@admin).sync
      end
    else
      test "true when user does not have a verified email" do
        ensure_announcement_category(@org_repo)

        @admin.emails.map(&:unverify!)
        assert @org_repo.can_create_discussion_announcements?(@admin)
        assert @org_repo.async_can_create_discussion_announcements?(@admin).sync
      end
    end

    test "false when user is blocked by owner" do
      ensure_announcement_category(@org_repo)

      @org.block(@admin)

      assert @org.blocking?(@admin)
      refute @org_repo.can_create_discussion_announcements?(@admin)
      refute @org_repo.async_can_create_discussion_announcements?(@admin).sync
    end
  end

  context "#discussions_metadata_readable_by?" do
    test "requires read+ for users" do
      @matrix.user_scenarios(
        :discussions_metadata_readable_by?,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "returns false when discussions are turned off" do
      @matrix.each_repo { |repo, admin| repo.turn_off_discussions(actor: admin, instrument: false) }

      @matrix.user_scenarios(
        :discussions_metadata_readable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end
  end

  context "#preferred_discussion_templates and #async_preferred_discussion_templates" do
    test "returns discussions templates for local repository" do
      commit = @org_repo.commits.create({ message: "Add templates", author: @org_repo.owner }) do |files|
        files.add ".github/DISCUSSION_TEMPLATE/announcements.yml", <<~YAML
        ---
        body:
        - type: input
          attributes:
            label: "what are you announcing?"
        YAML

        files.add ".github/DISCUSSION_TEMPLATE/general.yml", <<~YAML
        ---
        body:
        - type: input
          attributes:
            label: "what is your favorite pizza?"
        YAML
      end
      @org_repo.refs["refs/heads/master"].update(commit, @org_repo.owner)


      expected_templates = %w[announcements general]
      preferred_templates = @org_repo.preferred_discussion_templates
      assert_equal 2, preferred_templates.templates.size
      assert_equal 2, preferred_templates.valid_templates.size
      assert_equal expected_templates, preferred_templates.valid_templates.map(&:category_slug)

      preferred_templates = @org_repo.async_preferred_discussion_templates.sync
      assert_equal 2, preferred_templates.templates.size
      assert_equal 2, preferred_templates.valid_templates.size
      assert_equal expected_templates, preferred_templates.valid_templates.map(&:category_slug)
    end

    test "returns discussions templates from global repository" do
      commit = @global_repo.commits.create({ message: "Add templates", author: @global_repo.owner }) do |files|
        files.add ".github/DISCUSSION_TEMPLATE/show-and-tell.yml", <<~YAML
        ---
        body:
        - type: input
          attributes:
            label: "what are you showing?"
        YAML
      end
      @global_repo.refs["refs/heads/master"].update(commit, @global_repo.owner)

      expected_templates = ["show-and-tell"]
      preferred_templates = @org_repo.preferred_discussion_templates
      assert_equal 1, preferred_templates.templates.size
      assert_equal 1, preferred_templates.valid_templates.size
      assert_equal expected_templates, preferred_templates.valid_templates.map(&:category_slug)

      preferred_templates = @org_repo.async_preferred_discussion_templates.sync
      assert_equal 1, preferred_templates.templates.size
      assert_equal 1, preferred_templates.valid_templates.size
      assert_equal expected_templates, preferred_templates.valid_templates.map(&:category_slug)
    end
  end

  context "#has_max_categories?" do
    test "returns false if under the default maximum" do
      refute @repo.has_max_categories?
    end

    test "returns true if >= the default maximum" do
      DiscussionCategory.stub_const(:MAX_CATEGORIES_PER_REPO, 10) do
        categories = create_list(:discussion_category, 4, repository: @repo)
        assert @repo.has_max_categories?
      end
    end

    test "returns false if under the limit override" do
      DiscussionCategory::LimitOverride.new(
        repository: @repo,
        actor: @staff,
      ).set(limit: 30)

      categories = create_list(:discussion_category, 16, repository: @repo)
      refute @repo.has_max_categories?
    end

    test "returns true if >= the limit override" do
      DiscussionCategory::LimitOverride.new(
        repository: @repo,
        actor: @staff,
      ).set(limit: 30)

      categories = create_list(:discussion_category, 25, repository: @repo)
      assert @repo.has_max_categories?
    end
  end

  context "#disassociate_from_org_level_discussions" do
    test "returns true if no org level discussions association" do
      assert_nil @repo.organization_discussion
      assert @repo.disassociate_from_org_level_discussions
    end

    test "destroys record if repository was set" do
      org_discussion_config = create(:organization_discussion_config)
      refute_nil org_discussion_config.repository_id

      repo = org_discussion_config.repository

      assert_difference(-> { OrganizationDiscussionConfig.count }, -1) do
        assert repo.disassociate_from_org_level_discussions
      end
    end
  end
end
