# typed: false
# frozen_string_literal: true

require "test_helper"

class RepositoryStackReleaseTest < GitHub::TestCase
  fixtures do
    @owner = create(:credit_card_user)

    @stack = create :repository_stack, :with_example_repository, :with_two_factor_enabled, :with_signed_marketplace_agreement

    @repo = create :repository, owner: @owner, from_example: :repository_test_simple
  end


  context "validations" do
    test "disallows release if Stack is not owned by the Repo" do
      release = create(:release, tag_name: "v1", author: @owner, repository: @repo)

      stack_release = RepositoryStackRelease.create(repository_stack: @stack, release: release)

      refute_predicate stack_release, :valid?
    end

    test "valid if the Stack belongs to the Repo" do
      release = create(:release, tag_name: "v1", author: @stack.repository.owner, repository: @stack.repository)

      stack_release = RepositoryStackRelease.create(repository_stack: @stack, release: release)

      assert_predicate stack_release, :valid?
    end

    test "publishing to Marketplace requires 2FA" do
      release = create(:release, tag_name: "v1", author: @stack.repository.owner, repository: @stack.repository)
      release.author.two_factor_credential.destroy
      release.author.reload

      stack_release = RepositoryStackRelease.create(repository_stack: @stack, release: release, published_on_marketplace: true)

      refute_predicate stack_release, :valid?
      stack_release.errors.full_messages.include? "must have 2FA enabled to publish a stack"
    end

    test "publishing to Marketplace requires signing the developer agreement" do
      release = create(:release, tag_name: "v1", author: @stack.repository.owner, repository: @stack.repository)
      Marketplace::AgreementSignature.find_by(signatory: release.author).destroy

      stack_release = RepositoryStackRelease.create(repository_stack: @stack, release: release, published_on_marketplace: true)

      refute_predicate stack_release, :valid?
      assert(stack_release.errors.full_messages.include? "must sign latest developer agreement before publishing a stack")
    end

    test "publishing org owned stacks to Marketplace requires the org to sign the developer agreement" do
      org_owner = create(:organization)
      repo = create :repository, owner: org_owner
      repo.add_member(@owner, action: :write)
      stack = create :repository_stack, :with_example_repository, :with_two_factor_enabled, repository: repo
      release = create(:release, tag_name: "v1", author: @owner, repository: repo)

      create(
        :marketplace_agreement_signature,
        signatory: @owner,
        agreement: create(:marketplace_agreement)
      )

      @owner.two_factor_credential = create(:two_factor_credential)

      stack_release = RepositoryStackRelease.create(repository_stack: stack, release: release, published_on_marketplace: true)

      refute_predicate stack_release, :valid?
      assert(stack_release.errors.full_messages.include? "organization must sign latest developer agreement before publishing a stack")
    end

    if GitHub.spamminess_check_enabled?
      test "disallows release if stack owner is spammy" do
        release_author = create(:user)
        @stack.repository.add_member(release_author, action: :write)
        release = create(:release, tag_name: "v1", author: release_author, repository: @stack.repository)
        @stack.owner.mark_as_spammy


        stack_release = RepositoryStackRelease.create(
          repository_stack:        @stack,
          release:                 release,
          published_on_marketplace: true,
        )

        refute_predicate stack_release, :valid?
      end

      test "disallows release if release author is spammy" do
        release_author = create(:user)
        @stack.repository.add_member(release_author, action: :write)
        release = create(:release, tag_name: "v1", author: release_author, repository: @stack.repository)
        release_author.mark_as_spammy

        stack_release = RepositoryStackRelease.create(
          repository_stack:        @stack,
          release:                 release,
          published_on_marketplace: true,
        )

        refute_predicate stack_release, :valid?
      end
    end
  end

  context ".published" do
    test "returns only releases that have been published on Marketplace" do

      stack = create(:repository_stack,
                      :with_example_repository,
                      :with_signed_marketplace_agreement,
                      :with_two_factor_enabled)

      published_release = create(:repository_stack_release, :published, repository_stack: stack)
      unpublished_release = create(:repository_stack_release, :unpublished, repository_stack: stack)

      assert_equal 2, RepositoryStackRelease.count
      assert_equal 1, RepositoryStackRelease.published.count
      assert_includes stack.repository_stack_releases.published, published_release
      refute_includes stack.repository_stack_releases.published, unpublished_release
    end
  end
end
