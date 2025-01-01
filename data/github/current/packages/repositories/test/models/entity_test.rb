# typed: true
# frozen_string_literal: true

require "test_helper"

class EntityTest < GitHub::TestCase
  fixtures do
    @org          = create(:organization, login: "github")
    @authed       = create(:user, login: "authed")
    @unauthed     = create(:user, login: "unauthed")
    @random_user  = create(:user)

    @gist = GistHelpers.generate \
      contents: [{ name: "file.md", value: "random content" }],
      user: @random_user

    @repo         = create(:public_repository, owner: @random_user)
    @repo.add_member(@authed)

    @team         = create :team, organization: @org, permission: "push"
    @team.add_member @authed
  end

  context "Repository" do
    test "a repo's entity is the repo" do
      assert_equal @repo, @repo.entity
    end

    test "fulfilling the Entity contract" do
      Entity.public_instance_methods.each do |meth|
        assert @repo.respond_to?(meth)
      end
    end

    test "readable_by?" do
      assert @repo.readable_by?(nil)
      assert @repo.readable_by?(@authed)
    end

    test "writable_by?" do
      assert @repo.writable_by?(@authed)
    end

    test "human_name" do
      assert_equal "repository",      @repo.human_name
    end
  end

  context "Gist" do
    test "a gist's entity is the gist" do
      assert_equal @gist, @gist.entity
    end

    test "fulfills the Entity contract" do
      Entity.public_instance_methods.each do |meth|
        assert @gist.respond_to?(meth)
      end
    end

    test "readable_by?" do
      assert @gist.readable_by?(nil)
      assert @gist.readable_by?(@authed)
      assert @gist.readable_by?(@gist.owner)
    end

    test "readable_by is an alias for pullable_by" do
      assert_equal @gist.method(:pullable_by?), @gist.method(:readable_by?)
    end

    test "writable_by?" do
      assert @gist.writable_by?(@gist.owner)
    end

    test "human_name" do
      assert_equal "gist", @gist.human_name
    end
  end
end
