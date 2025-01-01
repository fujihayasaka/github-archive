# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryStackTest < GitHub::TestCase
  fixtures do
    @user = create(:staff_admin_user)
    @repo = create(:repository, owner: @user)

    @repo_stack = create(:repository_stack, :listed, repository: @repo)

    @bizdev = GitHub.enterprise? ? create(:staff_admin_user) : create(:biztools_user)
    @simple_repo_stack = create(:repository_stack)
    @featured_repo_stack = create(:repository_stack, :featured)
    @listed_repo_stack = create(:repository_stack, :listed)
  end

  context "update repository stack" do
    context "featuring and unfeaturing a stack" do
      test "errors if normal user tries to update" do
        input = {
          stack_id: @simple_repo_stack.id,
          featured: true,
        }

        user = create(:user)
        exception = assert_raises Errors::StackUpdateError do
          RepositoryStack.admin_update(input, current_user: user)
        end

        assert_equal "#{user.login} does not have permission to feature the Stack.", exception.message
      end

      test "features the Stack" do
        input = {
          stack_id: @simple_repo_stack.id,
          featured: true,
        }

        refute_predicate @simple_repo_stack.reload, :featured?

        RepositoryStack.admin_update(input, current_user: @bizdev)
        assert_predicate @simple_repo_stack.reload, :featured?
      end

      test "unfeatures the Stack" do
        input = {
          stack_id: @featured_repo_stack.id,
          featured: false,
        }

        assert_predicate @featured_repo_stack, :featured?

        RepositoryStack.admin_update(input, current_user: @bizdev)
        refute_predicate @featured_repo_stack.reload, :featured?
      end
    end

    context "delisting repository stack" do
      test "errors if normal user tries to delist" do
        input = {
          stack_id: @listed_repo_stack.id,
          delist: true,
        }

        user = create(:user)
        exception = assert_raises Errors::StackUpdateError do
          RepositoryStack.admin_update(input, current_user: user)
        end

        assert_equal "#{user.login} does not have permission to delist the Repository Stack", exception.message
      end

      test "admin delists the Stack" do
        input = {
          stack_id: @listed_repo_stack.id,
          delist: true,
        }

        assert_predicate @listed_repo_stack.reload, :listed?

        RepositoryStack.admin_update(input, current_user: @bizdev)

        refute_predicate @listed_repo_stack.reload, :listed?
      end

      test "owner delists the Stack" do
        listed_repo_stack = create(:repository_stack, :listed)

        input = {
          stack_id: listed_repo_stack.id,
          delist: true,
        }

        assert_predicate listed_repo_stack.reload, :listed?

        RepositoryStack.admin_update(input, current_user: listed_repo_stack.owner)

        refute_predicate listed_repo_stack.reload, :listed?
      end

      test "errors if Stack is not listed" do
        input = {
          stack_id: @simple_repo_stack.id,
          delist: true,
        }

        refute_predicate @simple_repo_stack.reload, :listed?

        exception = assert_raises Errors::StackUpdateError do
          RepositoryStack.admin_update(input, current_user: @simple_repo_stack.owner)
        end

        assert_equal "#{@simple_repo_stack.name} not listed", exception.message
      end

      test "nothing happens on false" do
        listed_repo_stack = create(:repository_stack, :listed)

        input = {
          stack_id: listed_repo_stack.id,
          delist: false,
        }

        assert_predicate listed_repo_stack.reload, :listed?

        RepositoryStack.admin_update(input, current_user: listed_repo_stack.owner)

        assert_predicate listed_repo_stack.reload, :listed?
      end
    end
  end

  context "#published_releases" do
    test "returns releases where each of their stack releases and themselves are published" do
      stack = create(:repository_stack, :with_example_repository, :with_two_factor_enabled, :with_signed_marketplace_agreement)
      draft_release = create(:release, repository: stack.repository, state: :draft, tag_name: "v2.0-beta")
      published_release = create(:release, repository: stack.repository, state: :published, tag_name: "v1")

      create(:repository_stack_release, :published, repository_stack: stack, release: draft_release)
      create(:repository_stack_release, :published, repository_stack: stack, release: published_release)

      assert_equal [published_release], stack.published_releases
    end
  end

  context "#can_viewer_see?" do
    test "returns true for a listed stack" do
      user = create(:user)
      stack = create(:repository_stack, :listed, name: "Apple Stack", repository: create(:repository, owner: user))
      assert stack.can_viewer_see?(nil)
    end

    test "returns false for a stack with no access to the repo to the viewer" do
      stack = create(:repository_stack, :listed, name: "Apple Stack")
      stack.repository.private = true
      stack.repository.save!
      refute stack.can_viewer_see?(nil)
    end

    test "returns true for a stack with access to the repo to the viewer" do
      user = create(:user)
      stack = create(:repository_stack, :listed, name: "Apple Stack", repository: create(:repository, owner: user))
      stack.repository.private = true
      stack.repository.save!
      assert stack.can_viewer_see?(user)
    end
  end

  context "#state" do
    test "default is unlisted" do
      stack = RepositoryStack.new

      assert_predicate stack, :unlisted?
      refute_predicate stack, :listed?
      refute_predicate stack, :delisted?
    end

    test "can be unlisted" do
      @repo_stack.unlisted!
      @repo_stack.reload

      assert_predicate @repo_stack, :unlisted?
      refute_predicate @repo_stack, :listed?
      refute_predicate @repo_stack, :delisted?
      assert_includes RepositoryStack.unlisted, @repo_stack
    end

    test "can be listed" do
      release = create :release, repository: @repo, tag_name: "v1",
        author: @user, state: :published, created_at: 1.month.ago,
        body: "*version 1*"
      @repo_stack.repository_stack_releases << RepositoryStackRelease.new(
        release: release, published_on_marketplace: true,
      )
      @repo_stack.listed!
      @repo_stack.reload

      refute_predicate @repo_stack, :unlisted?
      assert_predicate @repo_stack, :listed?
      refute_predicate @repo_stack, :delisted?
      assert_includes RepositoryStack.listed, @repo_stack
    end

    test "instruments when the stack is listed" do
      events = subscribe "repository_stack.listed"
      stack = create(:repository_stack, :listed)
      expected_payload = {
        repository_stack:     stack.slug,
        repository_stack_id:  stack.id,
        repo:                 stack.repository.name_with_owner,
        repo_id:              stack.repository.id,
        public_repo:          stack.repository.public?,
        user:                 stack.owner.to_s,
        user_id:              stack.owner.id,
      }

      stack.unlisted!
      assert_predicate stack, :unlisted?

      stack.listed!
      listed_event = events.pop

      assert listed_event, "a listed event was expected"
      assert_equal expected_payload, listed_event.payload
      assert_predicate stack.reload, :listed?
    end

    test "can be delisted" do
      @repo_stack.delisted!
      @repo_stack.reload

      refute_predicate @repo_stack, :unlisted?
      refute_predicate @repo_stack, :listed?
      assert_predicate @repo_stack, :delisted?
      assert_includes RepositoryStack.delisted, @repo_stack
    end

    test "instruments when the stack is delisted" do
      events = subscribe "repository_stack.delisted"
      stack = create(:repository_stack, :listed)
      expected_payload = {
        repository_stack:     stack.slug,
        repository_stack_id:  stack.id,
        repo:                 stack.repository.name_with_owner,
        repo_id:              stack.repository.id,
        public_repo:          stack.repository.public?,
        user:                 stack.owner.to_s,
        user_id:              stack.owner.id,
      }

      assert_predicate stack, :listed?

      stack.delisted!
      delist_event = events.pop

      assert delist_event, "a delist event was expected"
      assert_equal expected_payload, delist_event.payload
      assert_predicate stack.reload, :delisted?
    end

    test "remains listed when a release is destroyed and other releases exist" do
      releases = 2.times.map do |i|
        release = create :release, repository: @repo, tag_name: "v#{i}",
          author: @user, state: :published, created_at: 1.month.ago,
          body: "*version #{i}*"
        @repo_stack.repository_stack_releases << RepositoryStackRelease.new(
          release: release, published_on_marketplace: true,
        )
        release
      end
      @repo_stack.listed!

      assert_predicate @repo_stack.reload, :listed?
      releases.first.destroy
      assert_predicate @repo_stack.reload, :listed?
    end

    test "delists when the last remaining release is destroyed" do
      last_remaining_release = create :release, repository: @repo, tag_name: "v1",
        author: @user, state: :published, created_at: 1.month.ago,
        body: "*version 1*"

      @repo_stack.repository_stack_releases << RepositoryStackRelease.new(
        release: last_remaining_release, published_on_marketplace: true,
      )

      assert_predicate @repo_stack.reload, :listed?
      @repo_stack.repository_stack_releases.first.destroy
      assert_predicate @repo_stack.reload, :listed?
      last_remaining_release.destroy
      assert_predicate @repo_stack.reload, :delisted?
    end
  end

end unless GitHub.enterprise?
