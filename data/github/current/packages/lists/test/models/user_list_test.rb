# typed: true
# frozen_string_literal: true

require "test_helper"

class UserListTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include ConditionalAccess::FilterTestHelper
  include HydroTestHelpers

  fixtures do
    @owner = create(:user, login: "list-owner")
    @rando = create(:user)

    @list = create(:user_list, user: @owner, name: "where I keep all my stuff")
  end

  context "#name_html" do
    test "returns raw name when it contains no emoji" do
      list = UserList.new(name: "My Favorite Repos")
      assert_equal "My Favorite Repos", list.name_html
    end

    test "returns nil when name is nil" do
      list = UserList.new(name: nil)
      assert_nil list.name_html
    end

    test "parses colon-style emoji in name" do
      list = UserList.new(name: ":grinning: hello world")
      assert_equal "#{GRIN_EMOJI} hello world", list.name_html
    end

    test "renders g-emoji fallback for raw emoji in name" do
      list = UserList.new(name: "Hi there #{GRIN_EMOJI}")
      assert_equal "Hi there #{GRIN_EMOJI}", list.name_html
    end

    test "does not render formatting Markdown in name" do
      list = UserList.new(name: "*hello* _world_ ## My list <br><br>")
      assert_equal "*hello* _world_ ## My list &lt;br&gt;&lt;br&gt;", list.name_html
    end

    test "does not render arbitrary images in name" do
      list = UserList.new(name: "![](https://example.com/image.png) <img src=\"file.png\">")
      assert_equal "![](https://example.com/image.png) &lt;img src=\"file.png\"&gt;", list.name_html
    end
  end

  context "#description_html" do
    test "returns raw description when it contains no emoji" do
      list = UserList.new(description: "These are my favorite repositories.")
      assert_equal "These are my favorite repositories.", list.description_html
    end

    test "returns nil when description is nil" do
      list = UserList.new(description: nil)
      assert_nil list.description_html
    end

    test "parses colon-style emoji in description" do
      list = UserList.new(description: ":grinning: hello world")
      assert_equal "#{GRIN_EMOJI} hello world",
        list.description_html
    end

    test "renders g-emoji fallback for raw emoji in description" do
      list = UserList.new(description: "Hi there #{GRIN_EMOJI}")
      assert_equal "Hi there #{GRIN_EMOJI}", list.description_html
    end

    test "does not render formatting Markdown in description" do
      list = UserList.new(description: "*hello* _world_ ## My list <br><br>")
      assert_equal "*hello* _world_ ## My list &lt;br&gt;&lt;br&gt;", list.description_html
    end

    test "does not render arbitrary images in description" do
      list = UserList.new(description: "![](https://example.com/image.png) <img src=\"file.png\">")
      assert_equal "![](https://example.com/image.png) &lt;img src=\"file.png\"&gt;", list.description_html
    end
  end

  context ".with_each_default_suggestion" do
    test "loops through all the default user list suggestions with name and HTML name" do
      seen_suggestions = []

      UserList.with_each_default_suggestion do |name, name_html|
        list_with_name = UserList.new(name: name)
        assert_equal name_html, list_with_name.name_html, "should include the rendered HTML version of each name"

        seen_suggestions << name
      end

      assert_equal seen_suggestions, UserList::DEFAULT_SUGGESTIONS
    end
  end

  context ".async_name_html_for" do
    test "returns a promise resolving to how a list with the given name would render in HTML" do
      name = "#{GRIN_EMOJI} cats :point_right: :cat:"
      user_list = UserList.new(name: name)
      expected = %Q(#{GRIN_EMOJI} cats 👉 🐱)

      result = UserList.async_name_html_for(name)
      assert_instance_of Promise, result

      html_str = result.sync
      assert_equal user_list.name_html, html_str, "expected the value to match #name_html"
      assert_equal expected, html_str
    end
  end

  context ".owned_by" do
    test "includes lists owned by the user" do
      owner = create(:user)
      not_owner = create(:user)

      owner_list = create(:user_list, user: owner)
      not_owner_list = create(:user_list, user: not_owner)

      lists = UserList.owned_by(owner)
      assert_includes lists, owner_list
      refute_includes lists, not_owner_list
    end
  end

  context ".with_item" do
    test "finds lists that contain the item" do
      item = create(:user_list_item)
      not_item = create(:user_list_item)

      lists = UserList.with_item(item.repository)

      assert_includes lists, item.user_list
      refute_includes lists, not_item.user_list
    end
  end

  context "before validation" do
    test "strips extra whitespace from the name" do
      list = UserList.new(name: "   a    ")
      list.valid?
      assert_equal "a", list.name
    end

    test "creates URL friendly slugs from the name" do
      {
        "👻👻👻 Te$t 👻 List 👻 " => "te-t-list",
        "test 1️⃣ list" => "test-1-list",
        "用戶列表" => "用戶列表",
        "  \n\t  1234 ┏ ?\r" => "1234",
      }.each do |name, expected_slug|
        list = UserList.new(name: name)
        list.valid?
        assert_equal expected_slug, list.slug, "Name #{name.inspect} did not produce expected slug"
      end
    end
  end

  context "validations" do
    test "requires a user" do
      list = UserList.new
      refute_predicate list, :valid?
      assert_includes list.errors[:user], "can't be blank"
    end

    test "requires a name" do
      list = UserList.new
      refute_predicate list, :valid?
      assert_includes list.errors[:name], "can't be blank"
    end

    test "name cannot be too long" do
      list = UserList.new(name: "abcd" * 2028)
      refute_predicate list, :valid?
      assert_includes list.errors[:name], "is too long (maximum is 32 characters)"
    end

    test "cannot end up with a blank slug" do
      list = UserList.new(name: "#{GRIN_EMOJI} ")
      refute_predicate list, :valid?
      assert_includes list.errors[:name], "must include at least one alphanumeric character"
    end

    test "slug is unique per user" do
      owner, other = create_pair(:user)
      create(:user_list, user: owner, name: "test")

      list = build(:user_list, user: owner, name: "test")
      refute_predicate list, :valid?
      assert_includes list.errors[:name], "has already been taken"

      list = build(:user_list, user: other, name: "test")
      assert_predicate list, :valid?
    end

    test "description cannot be too long" do
      list = UserList.new(description: "abcd" * 2048)
      refute_predicate list, :valid?
      assert_includes list.errors[:description], "is too long (maximum is 160 characters)"
    end

    test "limits maximum number of lists per user" do
      owner = create(:user)
      max = UserList::MAX_PER_USER
      create_list(:user_list, max, user: owner)

      list = UserList.new(user: owner)

      refute_predicate list, :valid?
      assert_includes list.errors[:base], "cannot have more than #{max} lists"
    end
  end

  context "on creation" do
    test "populates the last_added_at timestamp attribute" do
      Timecop.freeze(now = Time.current) do
        list = create(:user_list, created_at: now - 1.day)
        assert_in_delta list.created_at, list.last_added_at
        assert_in_delta list.created_at, list.attributes["last_added_at"]

        list = create(:user_list, created_at: nil)
        assert_in_delta now, list.last_added_at
        assert_in_delta now, list.attributes["last_added_at"]
      end
    end

    test "continues if GitHub::KV is unavailable" do
      user = create(:user)
      repo = create(:repository)

      Stars::Kv.store.stubs(:setnx).raises(GitHub::KV::UnavailableError)

      assert_nothing_raised do
        create(:user_list, user: user)
      end
    end
  end

  context "#owned_by?" do
    test "returns false for anonymous viewers" do
      refute @list.owned_by?(nil)
    end

    test "returns false for randos" do
      refute @list.owned_by?(@rando)
    end

    test "returns true for the list owner" do
      assert @list.owned_by?(@owner)
    end
  end

  context "#title_for" do
    test "generates a title for an anonymous viewer" do
      assert_equal "list-owner's list / where I keep all my stuff", @list.title_for(nil)
    end

    test "generates a title for a non-owning user" do
      assert_equal "list-owner's list / where I keep all my stuff", @list.title_for(@rando)
    end

    test "generates a title for the owning user" do
      assert_equal "Your list / where I keep all my stuff", @list.title_for(@owner)
    end
  end

  context "#item_repositories_visible_to" do
    test "returns all public repositories for an anonymous viewer" do
      public_repo0, public_repo1 = create_pair(:repository)
      private_repo = create(:private_repository, owner: @owner)
      create(:user_list_item, user_list: @list, repository: public_repo0)
      create(:user_list_item, user_list: @list, repository: public_repo1)
      create(:user_list_item, user_list: @list, repository: private_repo)

      assert_same_elements [public_repo0, public_repo1], @list.item_repositories_visible_to(
        viewer: nil,
        cap_filter: cap_authorizing_filter([public_repo0, public_repo1, private_repo]),
      )
    end

    test "returns repositories that the viewer has access to" do
      public_repo = create(:repository)
      private_repo_accessible = create(:private_repository, owner: @owner)
      private_repo_inaccessible = create(:private_repository, owner: @owner)

      viewer = create(:user)
      private_repo_accessible.add_member(viewer)

      [public_repo, private_repo_accessible, private_repo_inaccessible].each do |repo|
        create(:user_list_item, user_list: @list, repository: repo)
      end

      assert_same_elements [public_repo, private_repo_accessible], @list.item_repositories_visible_to(
        viewer: viewer,
        cap_filter: cap_authorizing_filter([public_repo, private_repo_accessible, private_repo_inaccessible]),
      )
    end

    test "excludes repositories disallowed by the CAP filter" do
      repo0, repo1, repo2 = create_list(:repository, 3)
      [repo0, repo1, repo2].each do |repo|
        create(:user_list_item, user_list: @list, repository: repo)
      end

      assert_same_elements [repo0, repo1], @list.item_repositories_visible_to(
        viewer: @owner,
        cap_filter: cap_authorizing_filter([repo0, repo1]),
      )
    end
  end

  context ".recalculate_item_counts_and_last_added_at_times" do
    test "drops item_count to 0 when list has no items, while preserving last_added_at" do
      existing_last_added_at = 1.year.ago
      @list.update_attribute(:item_count, 123)
      @list.update_attribute(:last_added_at, existing_last_added_at)

      UserList.recalculate_item_counts_and_last_added_at_times(user_id: @owner.id, list_ids: [@list.id])

      assert_equal 0, @list.reload.item_count
      refute_nil @list.last_added_at, "should not wipe last_added_at"
      assert_equal existing_last_added_at.to_i, @list.last_added_at.to_i
    end

    test "updates item_count to the number of items in the list and last_added_at to most recent creation time of the list's items" do
      total_list_items = 3

      new_last_added_at = travel_to(@list.created_at + 1.day) do
        new_list_items = create_list(:user_list_item, total_list_items, user_list: @list)
        new_list_items.map(&:created_at).max
      end

      @list.update_attribute(:item_count, 0)
      old_last_added_at = new_last_added_at - 1.hour
      @list.update_attribute(:last_added_at, old_last_added_at)

      travel_to(old_last_added_at + 1.year) do
        UserList.recalculate_item_counts_and_last_added_at_times(user_id: @owner.id, list_ids: [@list.id])

        assert_equal total_list_items, @list.reload.item_count
        assert_equal new_last_added_at, @list.last_added_at
      end
    end

    test "does not update any lists that aren't specified" do
      @list.update_attribute(:item_count, 123)
      UserList.recalculate_item_counts_and_last_added_at_times(user_id: @owner.id, list_ids: [])
      assert_equal 123, @list.reload.item_count
    end
  end

  context ".visible_item_counts" do
    test "returns public repository counts for an anonymous viewer" do
      other_list = create(:user_list, user: @owner)

      public_repos = create_list(:repository, 3) do |repo, i|
        create(:user_list_item, user_list: @list, repository: repo)
        create(:user_list_item, user_list: other_list, repository: repo) if i <= 1
      end

      private_repos = create_pair(:private_repository, owner: @owner) do |repo|
        create(:user_list_item, user_list: @list, repository: repo)
        create(:user_list_item, user_list: other_list, repository: repo)
      end

      counts = UserList.visible_item_counts(
        viewer: nil,
        list_ids: [@list.id, other_list.id],
        cap_filter: cap_authorizing_filter(public_repos + private_repos),
      )
      assert_equal 3, counts[@list.id]
      assert_equal 2, counts[other_list.id]
    end

    test "returns public and visible private repository counts for an authenticated user" do
      other_list = create(:user_list, user: @owner)

      public_repo = create(:repository) do |repo|
        create(:user_list_item, user_list: @list, repository: repo)
      end

      private_repo_accessible, private_repo_inaccessible = create_pair(:private_repository, owner: @owner)
      private_repo_accessible.add_member(@rando)
      create(:user_list_item, user_list: @list, repository: private_repo_accessible)
      create(:user_list_item, user_list: @list, repository: private_repo_inaccessible)
      create(:user_list_item, user_list: other_list, repository: private_repo_accessible)
      create(:user_list_item, user_list: other_list, repository: private_repo_inaccessible)

      counts = UserList.visible_item_counts(
        viewer: @rando,
        list_ids: [@list.id, other_list.id],
        cap_filter: cap_authorizing_filter([public_repo, private_repo_accessible, private_repo_inaccessible])
      )
      assert_equal 2, counts[@list.id]
      assert_equal 1, counts[other_list.id]
    end

    test "does not count repositories hidden by CAP policies" do
      public_repo0, public_repo1 = create_pair(:repository)
      private_repo0, private_repo1 = create_pair(:private_repository, owner: @owner)

      create(:user_list_item, user_list: @list, repository: public_repo0)
      create(:user_list_item, user_list: @list, repository: public_repo1)
      create(:user_list_item, user_list: @list, repository: private_repo0)
      create(:user_list_item, user_list: @list, repository: private_repo1)

      counts = UserList.visible_item_counts(
        viewer: @owner,
        list_ids: [@list.id],
        cap_filter: cap_authorizing_filter([public_repo1, private_repo0])
      )
      assert_equal 2, counts[@list.id]
    end

    # https://github.com/github/lists/issues/87
    test "handles nil repositories" do
      doomed_repo = create(:repository)
      list_item = create(:user_list_item, user_list: @list, repository: doomed_repo)
      doomed_repo.delete

      counts = UserList.visible_item_counts(
        viewer: @owner,
        list_ids: [@list.id],
        cap_filter: cap_authorizing_filter([doomed_repo]),
      )

      assert_equal 0, counts[@list.id]
    end
  end

  context ".replace_all" do
    test "sets the lists that a repository belongs to for a user" do
      olden_time = Time.zone.parse("2021-09-01")
      replacement_time = Time.zone.parse("2021-10-01")

      user, other_user = create_pair(:user)
      repo, other_repo = create_pair(:repository)

      # Two lists owned by the user that already have the repository
      removed_list, kept_list = create_pair(:user_list, user: user)

      # A new list owned by the user to add the repository to
      added_list = create(:user_list, user: user, last_added_at: olden_time)

      # A list owned by a different user that has the same repository
      other_user_list = create(:user_list, user: other_user, item_count: 1)

      # A list owned by the user that does not have the same repository
      other_repo_list = create(:user_list, user: user, item_count: 1)

      travel_to(olden_time) do
        create(:user_list_item, user_list: removed_list, repository: repo)
        create(:user_list_item, user_list: kept_list, repository: repo)
        create(:user_list_item, user_list: other_user_list, repository: repo)
        create(:user_list_item, user_list: other_repo_list, repository: other_repo)
      end

      Timecop.freeze(replacement_time) do
        UserList.replace_all(user_id: user.id, repository_id: repo.id, list_ids: [kept_list.id, added_list.id])
      end

      assert_same_elements [kept_list, added_list], user.lists.with_item(repo)

      # The other lists should not have been touched
      assert_same_elements [other_repo_list], user.lists.with_item(other_repo)
      assert_equal 1, other_repo_list.reload.item_count
      assert_equal olden_time, other_repo_list.last_added_at
      assert_same_elements [other_user_list], other_user.lists.with_item(repo)
      assert_equal 1, other_user_list.reload.item_count
      assert_equal olden_time, other_user_list.reload.last_added_at

      # Item counts and last-added timestamps have been updated
      assert_equal 0, removed_list.reload.item_count
      assert_equal olden_time, removed_list.last_added_at
      assert_equal 1, kept_list.reload.item_count
      assert_equal olden_time, kept_list.last_added_at
      assert_equal 1, added_list.reload.item_count
      assert_equal replacement_time, added_list.last_added_at
    end

    test "with an empty set removes a repository from all of a user's lists" do
      user, other_user = create_pair(:user)
      repo, other_repo = create_pair(:repository)

      list0, list1, list2 = create_list(:user_list, 3, user: user)
      create(:user_list_item, user_list: list0, repository: repo)
      create(:user_list_item, user_list: list1, repository: repo)
      create(:user_list_item, user_list: list2, repository: other_repo)

      other_list = create(:user_list, user: other_user)
      create(:user_list_item, user_list: other_list, repository: repo)

      UserList.replace_all(user_id: user.id, repository_id: repo.id, list_ids: [])

      assert_empty user.lists.with_item(repo)

      # The other lists should not have been touched
      assert_same_elements [list2], user.lists.with_item(other_repo)
      assert_same_elements [other_list], other_user.lists.with_item(repo)
    end

    test "correctly computes item_count and last_added_at for now-empty lists" do
      original_time = Time.zone.parse("2021-10-10")

      user = create(:user)
      repo = create(:repository)

      list_to_empty = create(:user_list, user: user)
      travel_to(original_time) do
        create(:user_list_item, user_list: list_to_empty, repository: repo)
      end

      already_empty = create(:user_list, user: user, last_added_at: original_time)

      UserList.replace_all(user_id: user.id, repository_id: repo.id, list_ids: [])

      assert_equal 0, list_to_empty.reload.item_count
      assert_equal original_time, list_to_empty.last_added_at
      assert_equal 0, already_empty.reload.item_count
      assert_equal original_time, already_empty.last_added_at
    end

    test "preserves a more recent last_added_at timestamp" do
      # This will legitimately happen if a user adds, then removes, an item from a list.
      recent_time = Time.zone.parse("2021-09-09")
      older_time = Time.zone.parse("2021-08-08")

      user = create(:user)
      repo = create(:repository)

      list = create(:user_list, user: user)
      travel_to(older_time) { create(:user_list_item, user_list: list) }
      travel_to(recent_time) { create(:user_list_item, user_list: list, repository: repo) }

      UserList.replace_all(user_id: user.id, repository_id: repo.id, list_ids: [])

      # Even though the repo item has been removed from the list, the last_added_at timestamp should still be preserved
      assert_empty user.lists.with_item(repo)
      assert_equal 1, list.reload.item_count
      assert_equal recent_time, list.last_added_at
    end

    test "emits Hydro event for adding a list item" do
      travel_to(Time.now) do
        repo = create(:repository)
        message = {
          user_list_item: {
            user_list_id: @list.id,
            repository_id: repo.id,
            created_at: Time.now,
          },
          repository: Hydro::EntitySerializer.repository(repo),
          repository_owner: Hydro::EntitySerializer.user(repo.owner),
          user: Hydro::EntitySerializer.user(@owner),
          user_list: Hydro::EntitySerializer.user_list(@list),
        }

        assert_difference(-> { UserListItem.count }) do
          UserList.replace_all(user_id: @owner.id, repository_id: repo.id, list_ids: [@list.id])
        end

        new_list_item = @list.items.last
        refute_nil new_list_item
        message[:user_list_item][:id] = new_list_item.id
        assert_hydro_published(message, schema: "github.user_lists.v1.UserListAddItem")
        assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListAddItem")
      end
    end

    test "does not emit Hydro event for adding a list item that was already on a list" do
      repo = create(:repository)
      create(:user_list_item, user_list: @list, repository: repo)
      reset_hydro

      assert_no_difference(-> { UserListItem.count }) do
        UserList.replace_all(user_id: @owner.id, repository_id: repo.id, list_ids: [@list.id])
      end

      refute_hydro_messages(schema: "github.user_lists.v1.UserListAddItem")
    end

    test "emits Hydro event for removing a list item" do
      repo = create(:repository)
      list_item = create(:user_list_item, user_list: @list, repository: repo)
      message = {
        user_list_item: {
          id: list_item.id,
          user_list_id: @list.id,
          repository_id: repo.id,
          created_at: list_item.created_at,
        },
        repository: Hydro::EntitySerializer.repository(repo),
        repository_owner: Hydro::EntitySerializer.user(repo.owner),
        user: Hydro::EntitySerializer.user(@owner),
        user_list: Hydro::EntitySerializer.user_list(@list),
      }

      UserList.replace_all(user_id: @owner.id, repository_id: repo.id, list_ids: [])

      assert_hydro_published(message, schema: "github.user_lists.v1.UserListRemoveItem")
      assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListRemoveItem")
    end
  end

  context "#instrument_hydro_update" do
    test "emits a Hydro update event" do
      old_list = create(:user_list, user: @owner)
      message = {
        user: Hydro::EntitySerializer.user(@owner),
        old_user_list: Hydro::EntitySerializer.user_list(old_list),
        new_user_list: Hydro::EntitySerializer.user_list(@list),
      }

      @list.instrument_hydro_update(old_list: old_list)

      assert_hydro_published(message, schema: "github.user_lists.v1.UserListUpdate")
      assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListUpdate")
    end
  end

  context "instrumentation" do
    test "instruments an audit log event on creation" do
      actor = create(:user)
      Audit.context.push(actor: actor)

      list = build(:user_list)

      events = assert_performed_audit_entries(count: 1, only: "user_list.create") do
        list.save!
      end

      assert_subset_hash({
        action: "user_list.create",
        actor: actor.display_login,
        actor_id: actor.id,
        user_list_id: list.id,
        user_list_name: list.name,
        user: list.user.display_login,
        user_id: list.user.id,
      }, events.first)
    end

    test "emits a Hydro event on create" do
      message = {
        user: Hydro::EntitySerializer.user(@owner),
        user_list: {
          name: "Fancy list of mine",
          slug: "fancy-list-of-mine",
          description: "A fancy list of mine",
          user_id: @owner.id,
        },
      }

      new_list = create(:user_list, user: @owner, name: "Fancy list of mine", description: "A fancy list of mine")

      message[:user_list][:id] = new_list.id
      assert_hydro_published(message, schema: "github.user_lists.v1.UserListCreate")
      assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListCreate")
    end

    test "instruments an audit log event on update" do
      actor = create(:user)
      Audit.context.push(actor: actor)

      list = create(:user_list)

      events = assert_performed_audit_entries(count: 1, only: "user_list.update") do
        list.update!(name: "Hello")
      end

      assert_subset_hash({
        action: "user_list.update",
        actor: actor.display_login,
        actor_id: actor.id,
        user_list_id: list.id,
        user_list_name: list.name,
        user: list.user.display_login,
        user_id: list.user.id,
      }, events.first)
    end

    test "instruments an audit log event on deletion" do
      actor = create(:user)
      Audit.context.push(actor: actor)

      list = create(:user_list)

      events = assert_performed_audit_entries(count: 1, only: "user_list.destroy") do
        list.destroy!
      end

      assert_subset_hash({
        action: "user_list.destroy",
        actor: actor.display_login,
        actor_id: actor.id,
        user_list_id: list.id,
        user_list_name: list.name,
        user: list.user.display_login,
        user_id: list.user.id,
      }, events.first)
    end

    test "emits a Hydro event on delete" do
      message = {
        user: Hydro::EntitySerializer.user(@owner),
        user_list: {
          name: @list.name,
          slug: @list.slug,
          description: @list.description,
          user_id: @owner.id,
          id: @list.id,
        },
      }

      @list.destroy!

      assert_hydro_published(message, schema: "github.user_lists.v1.UserListDelete")
      assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListDelete")
    end
  end

  context ".applied_to" do
    test "enumerates a user's lists that contain and do not contain a repository" do
      user = create(:user)
      repo0, repo1 = create_pair(:repository)

      list0_has01, list1_has01, list2_has0 = create_list(:user_list, 3, user: user)
      create(:user_list_item, user_list: list0_has01, repository: repo0)
      create(:user_list_item, user_list: list0_has01, repository: repo1)
      create(:user_list_item, user_list: list1_has01, repository: repo0)
      create(:user_list_item, user_list: list1_has01, repository: repo1)
      create(:user_list_item, user_list: list2_has0, repository: repo0)
      [list0_has01, list1_has01, list2_has0].each_with_index do |list, index|
        list.update!(last_added_at: index.days.ago)
      end

      empty_list = create(:user_list, user: user, created_at: 4.days.ago)

      other_user_list = create(:user_list)
      create(:user_list_item, user_list: other_user_list, repository: repo0)

      applied_set = UserList.applied_to(user_id: user.id, repository_ids: [repo0.id, repo1.id])

      assert_equal [list0_has01, list1_has01, list2_has0], applied_set.containing(repo0.id)
      assert_equal [empty_list], applied_set.not_containing(repo0.id)

      assert_equal [list0_has01, list1_has01], applied_set.containing(repo1.id)
      assert_equal [list2_has0, empty_list], applied_set.not_containing(repo1.id)
    end

    test "fails if provided an unprepared repository" do
      user = create(:user)
      repo0, repo1 = create_pair(:repository)

      applied_set = UserList.applied_to(user_id: user.id, repository_ids: [repo0.id])

      assert_raises(KeyError) { applied_set.containing(repo1.id) }
      assert_raises(KeyError) { applied_set.not_containing(repo1.id) }
    end

    test "identifies an empty set without additional queries" do
      user = create(:user)
      repo = create(:repository)

      applied_set = UserList.applied_to(user_id: user.id, repository_ids: [repo.id])

      assert_query_count(1) do
        assert_predicate applied_set, :empty?

        assert_equal [], applied_set.containing(repo.id)
        assert_equal [], applied_set.not_containing(repo.id)
      end
    end

    test "identifies a non-empty set without additional queries" do
      user = create(:user)
      repo = create(:repository)
      list = create(:user_list, user: user)

      applied_set = UserList.applied_to(user_id: user.id, repository_ids: [repo.id])

      assert_query_count(1) do
        refute_predicate applied_set, :empty?

        assert_equal [], applied_set.containing(repo.id)
        assert_equal [list], applied_set.not_containing(repo.id)
      end
    end
  end

  context "#last_added_at" do
    test "defaults to created_at if blank" do
      list = create(:user_list)
      list.last_added_at = nil
      assert_equal list.created_at, list.last_added_at
      refute list.attributes["last_added_at"]
    end
  end

  context "#has_created_lists?" do
    test "returns false if GitHub::KV is unavailable" do
      Stars::Kv.store.stubs(:exists).raises(GitHub::KV::UnavailableError)
      refute UserList.has_created_lists?(@owner.id)
    end

    test "returns true if user has created a list" do
      assert UserList.has_created_lists?(@owner.id)
    end

    test "returns false if user has not created a list" do
      refute UserList.has_created_lists?(@rando.id)
    end
  end
end
