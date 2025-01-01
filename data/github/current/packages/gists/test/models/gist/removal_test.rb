# typed: true
# frozen_string_literal: true

require "test_helper"

class GistRemovalTest < GitHub::TestCase
  fixtures do
    @user         = create(:user)
    @user2        = create(:user)
    @contents     = [{ name: "1", value: "random content" }]
    @gist         = GistHelpers.generate \
      contents: @contents,
      user: @user, public: false
    @comment      = @gist.comments.create \
      body: "Hello world!",
      user: @user
    @fork         = @gist.fork(@user2)
    @public_gist  = GistHelpers.generate \
      contents: @contents,
      user: @user,
      description: "my gist",
      created_at: 4.hours.ago,
      updated_at: 4.hours.ago
    @deleted_gist = GistHelpers.generate_deleted \
      contents: @contents,
      user: @user,
      public: true
  end

  context "scopes" do
    test "has a deleted gist scope" do
      gists = Gist.deleted.all
      assert gists.include?(@deleted_gist)
      assert !gists.include?(@public_gist)
    end

    test "has an active (not deleted) gist scope" do
      gists = Gist.active.all
      assert !gists.include?(@deleted_gist)
      assert gists.include?(@public_gist)
    end
  end

  context "#remove" do
    test "it hides the gist" do
      assert @gist.active?

      @gist.remove

      refute @gist.active?
    end

    test "instruments gist.destroy" do
      GitHub.context.push(@user.event_context(prefix: :actor))
      events = subscribe "gist.destroy"

      @gist.remove

      expected_payload = {
        visibility: "secret",
        fork: false,
        actor: @user.login,
        actor_id: @user.id,
        user: @user.login,
        user_id: @user.id,
        gist_id: @gist.id,
        gist: @gist.name_with_owner,
      }

      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload
    end
  end

  context "#hide" do
    test "marks the gist delete_flag column" do
      assert @gist.active?
      @gist.hide

      gist = Gist.find(@gist.id)
      refute_nil gist
      assert !gist.active?
    end

    test "touches the parent record to bust caches" do
      @fork.parent.expects(:touch)

      @fork.hide
    end

    test "instruments gist.destroy" do
      GitHub.context.push(@user.event_context(prefix: :actor))
      events = subscribe "gist.destroy"

      @gist.hide

      expected_payload = {
        visibility: "secret",
        fork: false,
        actor: @user.login,
        actor_id: @user.id,
        user: @user.login,
        user_id: @user.id,
        gist_id: @gist.id,
        gist: @gist.name_with_owner,
      }

      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload
    end
  end

  context "#unhide" do
    test "makes the gist active again" do
      refute @deleted_gist.active?
      @deleted_gist.unhide

      assert @deleted_gist.active?
    end

    test "touches the parent record to bust caches" do
      @fork.hide
      refute @fork.active?

      @fork.parent.expects(:touch)
      @fork.unhide
    end
  end

  context ".restore" do
    test "just returns the gist if it is not archived" do
      assert Gist.exists?(@gist.id), "expected gist to not be archived"

      assert_equal @gist, Gist.restore(@gist.id)
    end

    test "restores a soft_deleted gist along with its comments" do
      gist = GistHelpers.generate(
        contents: @contents,
        user: @user,
        public: false
      )
      gist_id = gist.id
      comment = gist.comments.create(
        body: "Hello world!",
        user: @user
      )

      assert_includes gist.comments, comment

      #soft-delete gist
      soft_deleted_gist = gist.remove
      refute soft_deleted_gist.active?
      assert soft_deleted_gist.deleted?

      #restore soft-deleted gist
      restored_record = Gist.restore(gist_id)
      assert_equal Gist.find(gist_id), restored_record

      assert Gist.exists?(id: gist.id)
      assert GistComment.exists?(id: comment.id)

      refute restored_record.deleted?
      assert restored_record.active?
    end

    test "unhides the gist on restore" do
      deleted_gist = GistHelpers.generate_deleted(
        contents: @contents,
        user: @user,
        public: true
      )

      refute deleted_gist.active?

      soft_deleted_gist = deleted_gist.remove

      refute soft_deleted_gist.active?
      assert soft_deleted_gist.delete_flag

      assert restored_gist = Gist.restore(deleted_gist.id)
      refute restored_gist.delete_flag
      assert restored_gist.active?
    end

    test "deletes the repository on disk" do
      gist = GistHelpers.generate(contents: @contents, user: @user)

      assert gist.rpc.exist?
      gist.remove
      gist.remove_from_disk(gist) #remove this if we move `remove_from_disk` to `remove` in `Gist::Removal`
      if GitHub.enterprise?
        assert gist.rpc.exist?
      else
        refute gist.rpc.exist?
      end
    end
  end
end
