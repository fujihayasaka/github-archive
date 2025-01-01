# typed: false
# frozen_string_literal: true

require "test_helper"

class RepositoryActionReleaseTest < GitHub::TestCase
  fixtures do
    @owner = create(:credit_card_user)

    @action = create :repository_action, :with_example_repository, :with_two_factor_enabled, :with_signed_marketplace_agreement

    @repo = create :repository, owner: @owner, from_example: :repository_test_simple
  end

  # https://github.zendesk.com/agent/tickets/349143
  test "delists old Dockerfile Action if present so it can be replaced" do
    ["action.yml", "action.yaml"].each_with_index do |path, i|
      name = "superaction-#{i}"
      old_action = create :repository_action, :listed, path: "Dockerfile", name: name
      assert_predicate old_action.reload, :listed?

      new_action = create :repository_action, path: path, repository: old_action.repository, name: old_action.name

      release = create(:release, tag_name: "v2", author: new_action.repository.owner, repository: new_action.repository)
      action_release = RepositoryActionRelease.create(repository_action: new_action, release: release, published_on_marketplace: true)

      refute_predicate old_action.reload, :listed?
      assert_predicate new_action.reload, :listed?

      assert old_action.slug.nil?
      refute new_action.slug.nil?

      assert_equal new_action.name, name
      assert_equal new_action.slug, name
      assert_predicate action_release, :valid?
    end
  end

  context "validations" do
    test "disallows release if Action is not owned by the Repo" do
      release = create(:release, tag_name: "v1", author: @owner, repository: @repo)

      action_release = RepositoryActionRelease.create(repository_action: @action, release: release)

      refute_predicate action_release, :valid?
    end

    test "valid if the Action belongs to the Repo" do
      release = create(:release, tag_name: "v1", author: @action.repository.owner, repository: @action.repository)

      action_release = RepositoryActionRelease.create(repository_action: @action, release: release)

      assert_predicate action_release, :valid?
    end

    test "publishing to Marketplace requires 2FA" do
      release = create(:release, tag_name: "v1", author: @action.repository.owner, repository: @action.repository)
      release.author.two_factor_credential.destroy
      release.author.reload

      action_release = RepositoryActionRelease.create(repository_action: @action, release: release, published_on_marketplace: true)

      refute_predicate action_release, :valid?
      action_release.errors.full_messages.include? "must have 2FA enabled to publish an Action"
    end

    test "publishing to Marketplace requires signing the developer agreement" do
      release = create(:release, tag_name: "v1", author: @action.repository.owner, repository: @action.repository)
      Marketplace::AgreementSignature.find_by(signatory: release.author).destroy

      action_release = RepositoryActionRelease.create(repository_action: @action, release: release, published_on_marketplace: true)

      refute_predicate action_release, :valid?
      assert(action_release.errors.full_messages.include? "must sign latest developer agreement before publishing an Action")
    end

    test "publishing org owned actions to Marketplace requires the org to sign the developer agreement" do
      org_owner = create(:organization)
      repo = create :repository, owner: org_owner
      repo.add_member(@owner, action: :write)
      action = create :repository_action, :with_example_repository, :with_two_factor_enabled, repository: repo
      release = create(:release, tag_name: "v1", author: @owner, repository: repo)

      create(
        :marketplace_agreement_signature,
        signatory: @owner,
        agreement: create(:marketplace_agreement)
      )

      @owner.two_factor_credential = create(:two_factor_credential)

      action_release = RepositoryActionRelease.create(repository_action: action, release: release, published_on_marketplace: true)

      refute_predicate action_release, :valid?
      assert(action_release.errors.full_messages.include? "organization must sign latest developer agreement before publishing an Action")
    end

    if GitHub.spamminess_check_enabled?
      test "disallows release if action owner is spammy" do
        release_author = create(:user)
        @action.repository.add_member(release_author, action: :write)
        release = create(:release, tag_name: "v1", author: release_author, repository: @action.repository)
        @action.owner.mark_as_spammy


        action_release = RepositoryActionRelease.create(
          repository_action:        @action,
          release:                  release,
          published_on_marketplace: true,
        )

        refute_predicate action_release, :valid?
      end

      test "disallows release if release author is spammy" do
        release_author = create(:user)
        @action.repository.add_member(release_author, action: :write)
        release = create(:release, tag_name: "v1", author: release_author, repository: @action.repository)
        release_author.mark_as_spammy

        action_release = RepositoryActionRelease.create(
          repository_action:        @action,
          release:                  release,
          published_on_marketplace: true,
        )

        refute_predicate action_release, :valid?
      end
    end
  end

  context ".published" do
    test "returns only releases that have been published on Marketplace" do
      action = create(:repository_action,
                      :with_example_repository,
                      :with_signed_marketplace_agreement,
                      :with_two_factor_enabled)

      published_release = create(:repository_action_release, :published, repository_action: action)
      unpublished_release = create(:repository_action_release, :unpublished, repository_action: action)

      assert_equal 2, RepositoryActionRelease.count
      assert_equal 1, RepositoryActionRelease.published.count
      assert_includes action.repository_action_releases.published, published_release
      refute_includes action.repository_action_releases.published, unpublished_release
    end
  end
end
