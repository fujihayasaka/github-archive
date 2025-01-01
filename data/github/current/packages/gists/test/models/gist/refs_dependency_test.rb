# typed: true
# frozen_string_literal: true

require "test_helper"

class GistRefsDependencyMethodsTest < GitHub::TestCase
  fixtures do
    Spokesd.enable_spokesd

    @user         = create(:user)
    @user2        = create(:user)
    @contents     = [{ name: "1", value: "random content" }]
    @gist         = GistHelpers.generate(contents: @contents, user: @user, public: true)
    example_repo :simple_default_main, @gist
  end

  setup do
    Spokesd.enable_spokesd
  end

  context "#default_branch" do
    test "returns gist owner's preferred default branch when an error occurs" do
      @user.set_default_new_repo_branch("sample-sample", actor: @user)
      SpokesAPI::Client.any_instance.stubs(:get_default_branch).raises(SpokesAPI::NotFound)

      assert_equal "sample-sample", @gist.default_branch
    end

    test "forked gist returns forker's preferred default branch when an error occurs" do
      @user2.set_default_new_repo_branch("a-different-default", actor: @user2)
      fork = @gist.fork(@user2)

      SpokesAPI::Client.any_instance.stubs(:get_default_branch).raises(SpokesAPI::NotFound)
      assert_equal "a-different-default", fork.default_branch
    end

    test "does not return preferred default when ResourceExhausted raised" do
      @user.set_default_new_repo_branch("sample-sample", actor: @user)
      SpokesAPI::Client.any_instance.stubs(:get_default_branch).raises(SpokesAPI::ResourceExhausted)
      assert_raises(SpokesAPI::ResourceExhausted) { @gist.default_branch }
    end
  end

  context "#ref_to_sha" do
    test "returns nil when the revision is not found" do
      assert_nil @gist.ref_to_sha("not-a-revision")
    end
  end

  context "#sha" do
    test "returns nil when there's an error" do
      GitRPC::Client.any_instance.stubs(:read_head_oid).raises(GitRPC::Error)
      assert_nil @gist.sha
    end
  end
end
