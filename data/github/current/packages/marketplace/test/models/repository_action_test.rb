# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryActionTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  fixtures do
    @user = create(:staff_admin_user)
    @repo = create(:repository, owner: @user)

    @repo_action = create(:repository_action, :listed, repository: @repo)
  end

  [:name, :description].each do |field|
    test "supports emoji for #{field}" do
      repo_action = create(:repository_action, field => "we ❤️ emojis", :repository => @repo)

      assert_multibyte_tracked_changes(repo_action, field)
    end
  end

  test "requires a path" do
    repo_action = RepositoryAction.new(repository_id: @repo.id, path: nil)
    refute_predicate repo_action, :valid?
    assert repo_action.errors[:path]
  end

  context "remove_description_punctuation" do
    test "when description is nil" do
      repo_action = RepositoryAction.new(name: "Random name", repository_id: @repo.id, path: "path/to/somewhere", description: nil)
      repo_action.save!
      assert_nil repo_action.send(:remove_description_punctuation)
    end

    test "when description is a boolean value" do
      repo_action = RepositoryAction.new(name: "Random name", repository_id: @repo.id, path: "path/to/somewhere", description: true)
      assert_nil repo_action.send(:remove_description_punctuation)
    end
  end

  test "rejects path containing emoji" do
    repo_action = RepositoryAction.new(repository_id: @repo.id, path: "🐹")
    refute_predicate repo_action, :valid?
    assert repo_action.errors[:path]
  end

  test "requires a repository" do
    repo_action = RepositoryAction.new(repository_id: nil, path: "path/to/somewhere")
    refute_predicate repo_action, :valid?
    assert repo_action.errors[:repository_id]
  end

  test "repository and path are unique" do
    duplicate = RepositoryAction.new(repository: @repo, path: "action.yml")
    refute_predicate duplicate, :valid?
    assert duplicate.errors[:path].include? "has already been taken"

    duplicate = RepositoryAction.new(repository: @repo, path: "ACTION.yml")
    refute_predicate duplicate, :valid?
    assert duplicate.errors[:path].include? "has already been taken"
  end

  test "base path returns the basepath" do
    action = RepositoryAction.new(repository: @repo, path: "somewhere/to/somewhere/Dockerfile")
    assert_equal "somewhere/to/somewhere", action.base_path
  end

  test "base path returns the basepath for root files" do
    root = build(:repository_action, path: "Dockerfile")

    assert_equal "", root.base_path
  end

  test "requires slugs to be unique" do
    dupe_action = build(:repository_action, :listed, repository: @repo, slug: @repo_action.slug)
    refute dupe_action.valid?
    assert dupe_action.errors[:slug].include? "has already been taken"
  end

  test "allows duplicate slug when moving from Dockerfile to action.yml" do
    old_action = build(:repository_action, path: "Dockerfile")
    dupe_action = build(:repository_action, path: "action.yml", repository: old_action.repository, slug: old_action.slug)

    assert dupe_action.valid?
  end

  test "can preload categories" do
    regular_cats = create_list(:marketplace_category, 2)
    filter_cats = create_list(:marketplace_category, 2, acts_as_filter: true)
    categories = regular_cats + filter_cats

    action = create(:repository_action, categories: categories)

    table_name = RepositoryAction.table_name
    relation = RepositoryAction.
      where("#{table_name}.id > 0").
      order("#{table_name}.id ASC").
      limit(10).
      includes(:categories)

    actions = relation.to_a

    assert(actions.size > 0, "expected one action to be returned")
    assert_equal action, actions.last
  end

  test "can preload regular categories" do
    regular_cats = create_list(:marketplace_category, 2)
    filter_cats = create_list(:marketplace_category, 2, acts_as_filter: true)
    categories = regular_cats + filter_cats

    action = create(:repository_action, categories: categories)

    table_name = RepositoryAction.table_name
    relation = RepositoryAction.
      where("#{table_name}.id > 0").
      order("#{table_name}.id ASC").
      limit(10).
      includes(:regular_categories)

    actions = relation.to_a

    assert(actions.size > 0, "expected one action to be returned")
    assert_equal action, actions.last
  end

  test "can preload filter categories" do
    regular_cats = create_list(:marketplace_category, 2)
    filter_cats = create_list(:marketplace_category, 2, acts_as_filter: true)
    categories = regular_cats + filter_cats

    action = create(:repository_action, categories: categories)

    table_name = RepositoryAction.table_name
    relation = RepositoryAction.
      where("#{table_name}.id > 0").
      order("#{table_name}.id ASC").
      limit(10).
      includes(:filter_categories)

    actions = relation.to_a

    assert(actions.size > 0, "expected one action to be returned")
    assert_equal action, actions.last
  end

  test "associates an avatar to a repository action" do
    meta = { size: 42, content_type: "image/png", width: 5, height: 6 }
    avatar = Avatar.upload(@user, Sham.sha256, meta.merge(owner_id: @repo_action.id, owner_type: "RepositoryAction"))
    assert_equal @repo_action, avatar.owner
    assert_equal @repo_action.primary_avatar_path, "/ra/#{@repo_action.id}"
  end


  context "#sign_developer_agreement" do
    test "does not allow signature by non org admin" do
      org = create(:organization)
      action = create(:repository_action, :listed)
      repo = action.repository
      repo.owner = org
      repo.save!

      repo_write_user = create(:user)
      result = repo.add_member_without_validation_or_notifications(repo_write_user, action: :write)
      assert_nil(result)

      agreement, is_success = action.sign_developer_agreement(
        actor: repo_write_user,
        org: org,
        agreement: create(:marketplace_agreement)
      )

      refute is_success
      assert(agreement.errors.full_messages.include?("Must have org admin access to sign for this Action"))
    end
  end

  context "#security_email" do
    test "required if owned by an Organization" do
      org = create(:organization)
      action = create(:repository_action, :listed)
      action.repository.owner = org

      refute action.valid?
      assert action.errors[:security_email].any?
    end

    test "not required if owned by a User" do
      user = create(:user)
      action = create(:repository_action, :listed)
      action.repository.owner = user

      assert action.valid?
      assert action.errors[:security_email]
    end
  end

  context "#adminable_by?" do
    test "returns true if user has write access to repo" do
      action = create(:repository_action)
      write_user = create(:user)

      action.repository.add_member(write_user, action: :write)

      assert action.adminable_by?(action.owner)
      assert action.adminable_by?(write_user)
    end

    test "returns false if user only has read access to repo" do
      action = create(:repository_action)
      read_user = create(:user)

      action.repository.add_member(read_user, action: :read)

      refute action.adminable_by?(read_user)
    end

    test "returns false if random user" do
      action = create(:repository_action)
      rando_user = create(:user)

      refute action.adminable_by?(rando_user)
    end
  end

  context "#partnership_managed?" do
    test "returns false when the action does not have any categories" do
      action = create(:repository_action)

      refute action.partnership_managed?
    end

    test "returns false when the category is not github partners" do
      matching_category = create(:marketplace_category)
      expected_action = create(:repository_action, categories: [matching_category])

      refute expected_action.partnership_managed?
    end

    test "returns true when the category is github partners" do
      matching_category = create(:marketplace_category, name: "Github Partners", slug: "github-partners")
      expected_action = create(:repository_action, categories: [matching_category])

      assert expected_action.partnership_managed?
    end
  end

  context "#icon_name" do
    test "icon_names that do not exist in Feather are not saved" do
      action = create(:repository_action, icon_name: "not_a_valid_icon_at_all")

      assert_nil action.reload.icon_name
    end

    test "Feather Icon logos are not allowed" do
      action = create(:repository_action, icon_name: "github")

      assert_nil action.reload.icon_name
    end

    test "valid icon names are downcased" do
      action = create(:repository_action, icon_name: "cloud-LighTNing")

      assert_equal action.reload.icon_name, "cloud-lightning"
    end
  end

  context "#verified_owner?" do
    test "user repo action" do
      user_owned_action = create(:repository_action)
      refute_predicate user_owned_action, :verified_owner?
    end

    test "unverified org owned repo action" do
      org_owned_action = create(:repository_action, :org_owned)
      refute_predicate org_owned_action, :verified_owner?
    end

    test "verified org owned action" do
      org_owned_action = create(:repository_action, :org_owned)
      org_owned_action.owner.verify_for_repo_actions(org_owned_action.owner.admins.first)
      assert_predicate org_owned_action, :verified_owner?

      org_owned_action.owner.unverify_for_repo_actions(org_owned_action.owner.admins.first)
      refute_predicate org_owned_action, :verified_owner?
    end
  end

  context "#color" do
    test "always sets a valid color from Primer" do
      action = create(:repository_action, name: "A Very Good Action", color: "not_a_valid_color_at_all")

      valid_colors = RepositoryActions::Colors::PRIMER_COLORS.map { |primer_color| primer_color[:color_hex] }
      assert valid_colors.include?(action.color)
      assert_predicate action, :valid?
    end

    test "leaves color unchanged if valid" do
      action = create(:repository_action, color: "ffd33d")

      assert_equal action.color, "ffd33d"
      assert_predicate action, :valid?
    end

    test "converts valid color names into hex" do
      action = create(:repository_action, color: "blue")

      assert_equal action.color, "0366d6"
      assert_predicate action, :valid?
    end

    test "handles weird capitalization of color names" do
      action = create(:repository_action, color: "BluE")

      assert_equal action.color, "0366d6"
      assert_predicate action, :valid?
    end

    test "handles weird capitalize of color hex" do
      action = create(:repository_action, color: "FFd33d")

      assert_equal action.color, "ffd33d"
      assert_predicate action, :valid?
    end

    test "returns white if action owner is a partner" do
      repo = create(:repository, owner: create(:organization, login: RepositoryActions::ActionPartners::CUSTOM_ICON_PARTNERS.last))
      action = create(:repository_action, repository: repo, color: "black")

      assert_equal action.color, "ffffff"
      assert_predicate action, :valid?
    end

    test "returns blue if action owner is the Actions org" do
      repo = create(:repository, owner: create(:organization, login: "actions"))
      action = create(:repository_action, repository: repo, color: "black")

      assert_equal action.color, "0366d6"
      assert_predicate action, :valid?
    end
  end

  context "#icon_color" do
    test "all colors have a corresponding icon color set" do
      RepositoryActions::Colors::PRIMER_COLORS.each do |primer_color|
        action = build(:repository_action, color: primer_color[:color_hex])

        assert action.icon_color
      end
    end
  end

  context ".with_name" do
    test "returns actions that include the given name" do
      # NOTE: updating name to avoid potential name matching
      assert @repo_action.update(name: "OG Action")

      expected_action = create(:repository_action, name: "This Funky Action")
      create_list(:repository_action, 2, name: "Boring")

      actions = RepositoryAction.with_name("fUnK")

      assert_equal 1, actions.size
      assert_equal expected_action.id, T.must(actions.first).id
    end
  end

  context ".owned_by" do
    test "returns actions that are owned by the given user owner" do
      user = create(:user, login: "pickle-rick")
      repo = create(:repository, owner: user)
      expected_action = create(:repository_action, repository: repo)
      create(:repository_action, :featured)

      actions = RepositoryAction.owned_by(user.login)

      assert_equal 1, actions.size
      assert_equal expected_action.id, T.must(actions.first).id
    end

    test "returns actions that are owned by the given org owner" do
      org = create(:organization, login: "gazorpazorp")
      repo = create(:repository, owner: org)
      expected_action = create(:repository_action, repository: repo)
      create(:repository_action, :featured)

      actions = RepositoryAction.owned_by(org.login)

      assert_equal 1, actions.size
      assert_equal expected_action.id, T.must(actions.first).id
    end
  end

  context ".with_category" do
    test "returns actions that match the given category" do
      matching_category = create(:marketplace_category)
      expected_action = create(:repository_action, categories: [matching_category])

      other_category = create(:marketplace_category)
      create_list(:repository_action, 2, categories: [other_category])
      create_list(:repository_action, 2, categories: [])

      actions = RepositoryAction.with_category(matching_category.slug)

      assert_equal 1, actions.size
      assert_equal matching_category.id, T.must(T.must(actions.first).categories.first).id
    end

    test "returns actions that match the parent category" do
      parent_category = create(:marketplace_category)
      sub_category = create(:marketplace_category, parent_category: parent_category)
      expected_action = create(:repository_action, categories: [sub_category])

      other_category = create(:marketplace_category)
      create_list(:repository_action, 2, categories: [other_category])
      create_list(:repository_action, 2, categories: [])

      actions = RepositoryAction.with_category(parent_category.slug)

      assert_equal 1, actions.size
      assert_equal expected_action.id, T.must(actions.first).id
      assert_equal sub_category.id, T.must(T.must(actions.first).categories.first).id
    end

    test "returns distinct actions that match the given category" do
      parent_category = create(:marketplace_category)
      sub_category = create(:marketplace_category, parent_category: parent_category)
      expected_action = create(:repository_action, categories: [parent_category, sub_category])

      other_category = create(:marketplace_category)
      create_list(:repository_action, 2, categories: [other_category])
      create_list(:repository_action, 2, categories: [])

      actions = RepositoryAction.with_category(parent_category.slug)

      assert_equal 1, actions.size
      assert_equal expected_action.id, T.must(actions.first).id
    end
  end

  context "validate_name_and_slug" do
    test "returns an error when an action with the same name exists in marketplace" do
      action = create(:repository_action, :with_example_repository, :with_two_factor_enabled, :with_signed_marketplace_agreement)
      published_release = create(:release, repository: action.repository, state: :published, tag_name: "v1")
      create(:repository_action_release, :published, repository_action: action, release: published_release)
      action.listed!
      action_two = build(:repository_action, slug: action.slug)

      action_two.validate
      assert_equal action_two.errors[:slug].first, "has already been taken"
    end

    test "returns when an action with the same name does not exist in marketplace" do
      action = create(:repository_action, :with_example_repository, :with_two_factor_enabled, :with_signed_marketplace_agreement)
      published_release = create(:release, repository: action.repository, state: :published, tag_name: "v1")
      create(:repository_action_release, :published, repository_action: action, release: published_release)
      action_two = build(:repository_action, slug: action.slug)

      action_two.validate
      refute action.errors[:slug].any?
    end
  end

  context "#description" do
    test "can be empty" do
      action = build(:repository_action, description: nil)
      action.validate

      refute action.errors[:description].any?
    end

    test "validates length of description when listed" do
      text = "a" * (RepositoryAction::DESCRIPTION_MAX_LENGTH + 1)
      action = build(:repository_action, state: "listed", description: text)

      action.valid?

      assert_predicate action.errors[:description], :any?
    end

    test "remove punctuation" do
      action = build(:repository_action, state: "listed", description: "We don't want any of these.")

      action.valid?

      assert_equal action.description, "We don't want any of these"
    end

    test "remove multiple punctuation" do
      action = build(:repository_action, state: "listed", description: "We don't want any of these!?,??")

      action.valid?

      assert_equal action.description, "We don't want any of these"
    end
  end

  context ".with_state" do
    test "returns actions that match the given state" do
      expected_action = create(:repository_action, :listed)
      create_list(:repository_action, 2, state: :unlisted)
      create_list(:repository_action, 2, state: :delisted)

      actions = RepositoryAction.with_state(:listed)

      actions.each do |action|
        assert_equal "listed", action.state
      end
    end
  end

  context ".from_external_id" do
    test "docker://" do
      # When an external docker container is used as an action.
      # We return a "ghost docker action" to fill the spot on the UI
      assert_equal RepositoryAction.docker_action,
        RepositoryAction.from_external_id(external_id: "docker://something/otherthing")
    end

    test "ghost actions" do
      # When a corresponding RepositoryAction cannot be found.
      # We return a "ghost action" to fill the spot on the UI

      ghost_action = {
        name: "I was deleted",
        color: "ffffff",
        icon_color: "23292e",
        ghost_action: true,
      }

      assert_equal ghost_action, RepositoryAction.from_external_id(
        external_id: "#{@repo.name_with_owner}/i/was/deleted@SOME_SHA",
        ghost_allowed: true, default_title: "I was deleted")
    end

    test "local paths without a Repository Action - returns the ghost action" do
      ghost_action = {
        name: "I was deleted",
        color: "ffffff",
        icon_color: "23292e",
        ghost_action: true,
      }

      external_id = "./path/to/something"
      assert_equal ghost_action, RepositoryAction.from_external_id(external_id: external_id,
                                                                   repository_id: @repo.id, ghost_allowed: true, default_title: ghost_action[:name])
    end

    test "invalid local paths without a Repository Action - returns the ghost action" do
      ghost_action = {
        name: "I was deleted",
        color: "ffffff",
        icon_color: "23292e",
        ghost_action: true,
      }

      external_id = ".path/to/something"
      assert_equal ghost_action, RepositoryAction.from_external_id(external_id: external_id,
                                                                   repository_id: @repo.id, ghost_allowed: true, default_title: ghost_action[:name])
    end

    test "user/repo@commit" do
      repo_root_action = create(:repository_action, name: "Root Action Name", path: "Dockerfile")

      external_id = repo_root_action.repository.name_with_owner
      external_id += "@THIS_IS_THE_SHA"
      assert_equal repo_root_action, RepositoryAction.from_external_id(external_id: external_id)
    end

    test "user/repo/path/to/something@commit" do
      repo_folder_action = create(:repository_action, name: "Action in folder",
        repository: @repo, icon_name: "github", color: "ASDFJ4",
        description: "This is my description about this action", path: "path/to/something/Dockerfile")
      external_id = @repo.name_with_owner
      external_id += "/path/to/something@THIS_IS_THE_SHA"
      assert_equal repo_folder_action, RepositoryAction.from_external_id(external_id: external_id)
    end

    test "./path/to/something" do
      repo_folder_action = create(:repository_action, name: "Action in folder",
        repository: @repo, icon_name: "github", color: "ASDFJ4",
        description: "This is my description about this action", path: "path/to/something/Dockerfile")
      external_id = "./path/to/something"
      assert_equal repo_folder_action, RepositoryAction.from_external_id(external_id: external_id,
         repository_id: @repo.id)
    end

    test "./path/to/something/" do
      repo_folder_action = create(:repository_action, name: "Action in folder",
        repository: @repo, icon_name: "github", color: "ASDFJ4",
        description: "This is my description about this action", path: "path/to/something/Dockerfile")
      external_id = "./path/to/something/"
      assert_equal repo_folder_action, RepositoryAction.from_external_id(external_id: external_id,
         repository_id: @repo.id)
    end

    test "./github/lint" do
      repo_local_action = create(:repository_action, name: "Action in folder",
        repository: @repo, icon_name: "github", color: "ASDFJ4",
        description: "This is my description about this action", path: ".github/lint/Dockerfile")
      external_id = "./.github/lint"
      assert_equal repo_local_action, RepositoryAction.from_external_id(external_id: external_id,
         repository_id: @repo.id)
    end
  end

  context "#published_releases" do
    test "returns releases where each of their action releases and themselves are published" do
      action = create(:repository_action, :with_example_repository, :with_two_factor_enabled, :with_signed_marketplace_agreement)
      draft_release = create(:release, repository: action.repository, state: :draft, tag_name: "v2.0-beta")
      published_release = create(:release, repository: action.repository, state: :published, tag_name: "v1")
      create(:repository_action_release, :published, repository_action: action, release: draft_release)
      create(:repository_action_release, :published, repository_action: action, release: published_release)

      assert_equal [published_release], action.published_releases
    end
  end

  context "#readme" do
    test "returns the README based on the base path of the action in the repo" do
      action = create(:repository_action, :with_example_repository, path: "subdirectory/to/Dockerfile")
      repo = action.repository
      user = repo.owner
      ref = repo.heads.find(repo.default_branch)
      commit_metadata = { message: "add READMEs", committer: user }
      root_readme_path = "README.md"
      action_readme_path = File.join("subdirectory", "to", "README.md")

      ref.append_commit(commit_metadata, user) do |files|
        files.add(root_readme_path, "# This is at the root")
        files.add(action_readme_path, "# We're now in a subdirectory")
      end

      assert_equal action_readme_path, action.readme.path
    end

    test "returns nil if the README isn't in the same exact directory as the action" do
      action = create(:repository_action, :with_example_repository, path: "subdirectory/to/Dockerfile")
      repo = action.repository
      user = repo.owner
      ref = repo.heads.find(repo.default_branch)
      commit_metadata = { message: "add READMEs", committer: user }
      root_readme_path = "README.md"
      action_readme_path = File.join("subdirectory", "to", "docs", "README.md")

      ref.append_commit(commit_metadata, user) do |files|
        files.add(root_readme_path, "# This is at the root")
        files.add(action_readme_path, "# This is a nested README")
      end

      assert_nil action.readme
    end

    test "returns the README as its latest version on the repo's default branch" do
      action = create(:repository_action, :with_example_repository)
      repo = action.repository
      user = repo.owner
      branch_ref = repo.heads.find(repo.default_branch)

      older_commit_metadata = { message: "add README", committer: user }
      branch_ref.append_commit(older_commit_metadata, user) do |files|
        files.add("README.md", "older content")
      end

      latest_commit_metadata = { message: "update README", committer: user }
      branch_ref.append_commit(latest_commit_metadata, user) do |files|
        files.add("README.md", "NEWER CONTENT!")
      end

      assert_includes "NEWER CONTENT!", action.readme.data
    end

    test "returns the README as its given 'committish' version when a version is provided" do
      action = create(:repository_action, :with_example_repository)
      repo = action.repository
      user = repo.owner
      branch_ref = repo.heads.find(repo.default_branch)

      older_commit_metadata = { message: "add README", committer: user }
      branch_ref.append_commit(older_commit_metadata, user) do |files|
        files.add("README.md", "older content")
      end

      # create release of the repo at its current state
      release = create(:release, repository: repo)

      latest_commit_metadata = { message: "update README", committer: user }
      branch_ref.append_commit(latest_commit_metadata, user) do |files|
        files.add("README.md", "NEWER CONTENT!")
      end

      assert_includes "older content", action.readme(committish: release.tag_name).data
    end
  end

  test "when delisted gets removed from search" do
    action = create(:repository_action, :listed)

    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["repository_action", action.id] do
      action.update(state: :delisted)
    end
  end

  context "#state" do
    test "default is unlisted" do
      action = RepositoryAction.new

      assert_predicate action, :unlisted?
      refute_predicate action, :listed?
      refute_predicate action, :delisted?
    end

    test "can be unlisted" do
      @repo_action.unlisted!
      @repo_action.reload

      assert_predicate @repo_action, :unlisted?
      refute_predicate @repo_action, :listed?
      refute_predicate @repo_action, :delisted?
      assert_includes RepositoryAction.unlisted, @repo_action
    end

    test "can be listed" do
      release = create :release, repository: @repo, tag_name: "v1",
        author: @user, state: :published, created_at: 1.month.ago,
        body: "*version 1*"
      @repo_action.repository_action_releases << RepositoryActionRelease.new(
        release: release, published_on_marketplace: true,
      )
      @repo_action.listed!
      @repo_action.reload

      refute_predicate @repo_action, :unlisted?
      assert_predicate @repo_action, :listed?
      refute_predicate @repo_action, :delisted?
      assert_includes RepositoryAction.listed, @repo_action
    end

    test "instruments when the action is listed" do
      events = subscribe "repository_action.listed"
      action = create(:repository_action, :listed)
      expected_payload = {
        repository_action:    action.slug,
        repository_action_id: action.id,
        repo:                 action.repository.name_with_owner,
        repo_id:              action.repository.id,
        public_repo:          action.repository.public?,
        user:                 action.owner.to_s,
        user_id:              action.owner.id,
      }

      action.unlisted!
      assert_predicate action, :unlisted?

      action.listed!
      listed_event = events.pop

      assert listed_event, "a listed event was expected"
      assert_equal expected_payload, listed_event.payload
      assert_predicate action.reload, :listed?
    end

    test "can be delisted" do
      @repo_action.delisted!
      @repo_action.reload

      refute_predicate @repo_action, :unlisted?
      refute_predicate @repo_action, :listed?
      assert_predicate @repo_action, :delisted?
      assert_includes RepositoryAction.delisted, @repo_action
    end

    test "instruments when the action is delisted" do
      events = subscribe "repository_action.delisted"
      action = create(:repository_action, :listed)
      expected_payload = {
        repository_action:    action.slug,
        repository_action_id: action.id,
        repo:                 action.repository.name_with_owner,
        repo_id:              action.repository.id,
        public_repo:          action.repository.public?,
        user:                 action.owner.to_s,
        user_id:              action.owner.id,
      }

      assert_predicate action, :listed?

      action.delisted!
      delist_event = events.pop

      assert delist_event, "a delist event was expected"
      assert_equal expected_payload, delist_event.payload
      assert_predicate action.reload, :delisted?
    end

    test "remains listed when a release is destroyed and other releases exist" do
      releases = 2.times.map do |i|
        release = create :release, repository: @repo, tag_name: "v#{i}",
          author: @user, state: :published, created_at: 1.month.ago,
          body: "*version #{i}*"
        @repo_action.repository_action_releases << RepositoryActionRelease.new(
          release: release, published_on_marketplace: true,
        )
        release
      end
      @repo_action.listed!

      assert_predicate @repo_action.reload, :listed?
      releases.first.destroy
      assert_predicate @repo_action.reload, :listed?
    end

    test "delists when the last remaining release is destroyed" do
      last_remaining_release = create :release, repository: @repo, tag_name: "v1",
        author: @user, state: :published, created_at: 1.month.ago,
        body: "*version 1*"

      @repo_action.repository_action_releases << RepositoryActionRelease.new(
        release: last_remaining_release, published_on_marketplace: true,
      )

      assert_predicate @repo_action.reload, :listed?
      @repo_action.repository_action_releases.first.destroy
      assert_predicate @repo_action.reload, :listed?
      last_remaining_release.destroy
      assert_predicate @repo_action.reload, :delisted?
    end

    test "all action releases are unpublished on public => private repo transition" do
      release_v11 = create :release, repository: @repo, tag_name: "v1.1",
        author: @user, state: :published, created_at: 1.month.ago,
        body: "*version 1.1*"
      @repo_action.repository_action_releases << RepositoryActionRelease.new(
        release: release_v11, published_on_marketplace: true,
      )

      @repo.update!(public: false)

      @repo_action.repository_action_releases.each do |repository_action_release|
        refute_predicate repository_action_release.reload, :published_on_marketplace?
      end
    end
  end

  test "#default_branch_workflow_snippet" do
    repo_action = create(:repository_action, :listed, file_contents: { name: "An action" })
    expected_example = <<-YAML
- name: #{repo_action.name}
  uses: #{repo_action.external_uses_path_prefix}master
YAML
    assert_equal expected_example, repo_action.default_branch_workflow_snippet
  end

  context "#latest_tag_or_default_branch" do
    test "returns the latest tag if there are published releases" do
      repo_action = create(:repository_action, :listed, file_contents: { name: "An action" })
      tag_name = repo_action.published_releases.first.tag_name
      assert_equal tag_name, repo_action.latest_tag_or_default_branch
    end

    test "returns the default branch if there are no published releases" do
      repo_action = create(:repository_action, :listed, file_contents: { name: "An action" })
      repo_action.published_releases.first.destroy
      assert_equal repo_action.repository.default_branch, repo_action.latest_tag_or_default_branch
    end
  end

  context "#can_viewer_see?" do
    test "returns true for a listed action" do
      user = create(:user)
      action = create(:repository_action, :listed, name: "Apple Action", repository: create(:repository, owner: user))
      assert action.can_viewer_see?(nil)
    end

    test "returns false for an action with no access to the repo to the viewer" do
      action = create(:repository_action, :listed, name: "Apple Action")
      action.repository.private = true
      action.repository.save!
      refute action.can_viewer_see?(nil)
    end

    test "returns true for an action with access to the repo to the viewer" do
      user = create(:user)
      action = create(:repository_action, :listed, name: "Apple Action", repository: create(:repository, owner: user))
      action.repository.private = true
      action.repository.save!
      assert action.can_viewer_see?(user)
    end
  end

  context "#latest_input_params" do
    test "works when the action file contains inputs" do
      file_contents = {
        "inputs" => {
          "publish-profile" => {
            "description" => "Publish profile (*.publishsettings) file contents with Web Deploy secrets",
            "required" => false,
          },
          "app-name" => {
            "description" => "Name of the Azure Web App",
            "required" => true,
          },
          "package" => {
            "description" => "Path to package or folder. *.zip, *.war, *.jar or a folder to deploy",
            "required" => false,
            "default" => ".",
          },
          "slot-name" => {
            "description" => "Enter an existing Slot other than the Production slot",
            "required" => false,
            "default" => "production",
          },
        },
        "outputs" => {
          "webapp-url" => {
            "description" => "URL to work with your webapp",
          },
        },
        "branding" => {
          "icon" => "webapp.svg",
          "color" => "blue",
        },
        "runs" => {
          "using" => "node12",
          "main" => "lib/main.js",
        },
      }
      repo_action = create(:repository_action, :listed, file_contents: file_contents)
      published_releases_workflow_snippet = repo_action.published_releases_workflow_snippet
      last = published_releases_workflow_snippet.last
      sha = repo_action.repository.ref_to_sha(repo_action.latest_tag_or_default_branch)

      space = " "
      expected_example = <<-YAML
- name: #{repo_action.name}
  # You may pin to the exact commit or the version.
  # uses: #{repo_action.external_uses_path_prefix}#{sha}
  uses: #{repo_action.external_uses_path_prefix}#{repo_action.latest_tag_or_default_branch}
  with:
    # Publish profile (*.publishsettings) file contents with Web Deploy secrets
    publish-profile: # optional
    # Name of the Azure Web App
    app-name:#{space}
    # Path to package or folder. *.zip, *.war, *.jar or a folder to deploy
    package: # optional, default is .
    # Enter an existing Slot other than the Production slot
    slot-name: # optional, default is production
YAML

      assert_equal repo_action.latest_tag_or_default_branch, last[:release].tag_name
      assert_equal expected_example.strip, last[:example]
    end

    test "works when the action file does not contain inputs" do
      file_contents = {
        "name" => "Azure WebApp Action",
        "description" => "Deploy Web Apps to Azure",
      }
      repo_action = create(:repository_action, :listed, file_contents: file_contents)
      published_releases_workflow_snippet = repo_action.published_releases_workflow_snippet
      last = published_releases_workflow_snippet.last
      sha = repo_action.repository.ref_to_sha(repo_action.latest_tag_or_default_branch)

      expected_example = <<-YAML
- name: #{repo_action.name}
  # You may pin to the exact commit or the version.
  # uses: #{repo_action.external_uses_path_prefix}#{sha}
  uses: #{repo_action.external_uses_path_prefix}#{repo_action.latest_tag_or_default_branch}
YAML

      assert_equal repo_action.latest_tag_or_default_branch, last[:release].tag_name
      assert_equal expected_example.strip, last[:example]
    end

    test "shows tag only when a GitHub owned Action" do
      file_contents = {
        "name" => "Checkout",
        "description" => "Checkout your repos with this gitastic official Action from GitHub",
      }

      github_org = Organization.find_by_login("GitHub")
      repo = create(:repository, owner: github_org)
      repo_action = create(:repository_action, :listed, repository: repo, file_contents: file_contents)
      published_releases_workflow_snippet = repo_action.published_releases_workflow_snippet
      last = published_releases_workflow_snippet.last

      expected_example = <<-YAML
- name: #{repo_action.name}
  uses: #{repo_action.external_uses_path_prefix}#{repo_action.latest_tag_or_default_branch}
YAML

      assert_equal repo_action.latest_tag_or_default_branch, last[:release].tag_name
      assert_equal expected_example.strip, last[:example]
    end

    test "works when the action file cannot be parsed" do
      file_contents = { name: "This file is wrong because the key is a Symbol" }
      repo_action = create(:repository_action, :listed, file_contents: file_contents)
      published_releases_workflow_snippet = repo_action.published_releases_workflow_snippet
      last = published_releases_workflow_snippet.last
      sha = repo_action.repository.ref_to_sha(repo_action.latest_tag_or_default_branch)

      expected_example = <<-YAML
- name: #{repo_action.name}
  # You may pin to the exact commit or the version.
  # uses: #{repo_action.external_uses_path_prefix}#{sha}
  uses: #{repo_action.external_uses_path_prefix}#{repo_action.latest_tag_or_default_branch}
YAML

      assert_equal repo_action.latest_tag_or_default_branch, last[:release].tag_name
      assert_equal expected_example.strip, last[:example]
    end

    test "works when the actions file cannot be found in git" do
      file_contents = { name: "This file is wrong because the key is a Symbol" }
      repo_action = create(:repository_action, :listed, file_contents: file_contents)
      repo_action.update(path: "unknown-path.yml")
      published_releases_workflow_snippet = repo_action.published_releases_workflow_snippet
      last = published_releases_workflow_snippet.last
      sha = repo_action.repository.ref_to_sha(repo_action.latest_tag_or_default_branch)

      expected_example = <<-YAML
- name: #{repo_action.name}
  # You may pin to the exact commit or the version.
  # uses: #{repo_action.external_uses_path_prefix}#{sha}
  uses: #{repo_action.external_uses_path_prefix}#{repo_action.latest_tag_or_default_branch}
YAML

      assert_equal repo_action.latest_tag_or_default_branch, last[:release].tag_name
      assert_equal expected_example.strip, last[:example]
    end
  end

  context "action_package_listed" do
    test "default is not package listed" do
      action = RepositoryAction.new

      refute action.action_package_listed
      assert_predicate action, :unlisted?
    end

    test "listing to Marketplace requires signing the developer agreement" do
      GitHub.context.push(current_user: @user.id)
      GitHub.flipper[:action_package_marketplace].enable(@user)
      T.must(Marketplace::AgreementSignature.find_by(signatory: @user)).destroy

      @repo_action.update(action_package_listed: true, state: :listed)

      assert(@repo_action.errors.full_messages.include? "must sign latest developer agreement before publishing an Action")
    end

    test "publishing org owned actions to Marketplace requires the org to sign the developer agreement" do
      @org_owner = create(:organization)
      @repo = create :repository, owner: @org_owner
      @repo.add_member(@user, action: :write)
      @action = create :repository_action, :with_example_repository, repository: @repo
      GitHub.context.push(current_user: @user.id)
      GitHub.flipper[:action_package_marketplace].enable(@user)

      @action.update(action_package_listed: true, state: :listed)

      assert(@action.errors.full_messages.include? "organization must sign latest developer agreement before publishing an Action")
    end
  end
end unless GitHub.enterprise?
