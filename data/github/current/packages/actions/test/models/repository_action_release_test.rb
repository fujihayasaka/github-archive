# typed: false
# frozen_string_literal: true

require "test_helper"

class RepositoryActionReleaseTest < GitHub::TestCase
  include RepositoryActionTestHelpers
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

  context "list_action_on_marketplace"  do
    context "new_action_at_root ff off" do
      test "lists action on marketplace after create if not already listed" do
        disable_feature_flag(:new_action_at_root, @action.repository)
        refute_predicate @action, :listed?

        release = create(:release, tag_name: "v2", author: @action.repository.owner, repository: @action.repository)
        RepositoryActionRelease.create(repository_action: @action, release: release, published_on_marketplace: true)

        assert_predicate @action.reload, :listed?
        assert @action.slug.present?
      end

      test "errors out if you try to list a RepositoryAction while there is another RepositoryAction for the same repository that exists with a different action path" do
        repo = create(:repository, from_example: :javascript_action, owner: @owner)
        disable_feature_flag(:new_action_at_root, repo)

        update_action_yml_file(user: @owner, repo: repo, name: "actionfiles", path: "action.yaml")
        yaml_repo_action = create(:repository_action, :with_two_factor_enabled, :with_signed_marketplace_agreement, repository: repo, name: "bobs", path: "action.yaml")

        release = create(:release, tag_name: "v1", author: repo.owner, repository: repo)
        RepositoryActionRelease.create(repository_action: yaml_repo_action, release: release, published_on_marketplace: true)

        assert_predicate yaml_repo_action.reload, :listed?
        assert yaml_repo_action.slug.present?
        # update yml file on main to be yml instead of yaml
        update_action_yml_file(user: @owner, repo: repo, name: "actionfiles", path: "action.yml")
        ref = repo.heads.find(repo.default_branch)
        ref.append_commit({ committer: repo.owner, message: "deleting action.yaml" }, repo.owner) do |changes|
          changes.remove("action.yaml")
        end

        yml_repo_action = create(:repository_action, repository: repo, path: "action.yml", name: yaml_repo_action.name)

        yml_repo_action = yml_repo_action.reload
        refute_predicate yml_repo_action, :listed?

        release_2 = create(:release, tag_name: "v2", author: repo.owner, repository: repo)
        assert_raises(ActiveRecord::RecordNotUnique) do
          RepositoryActionRelease.create(repository_action: yml_repo_action, release: release_2, published_on_marketplace: true)
        end

        refute_predicate yml_repo_action.reload, :listed?
        refute yml_repo_action.slug.present?
        assert_predicate yaml_repo_action.reload, :listed?
        assert yaml_repo_action.slug.present?
      end
    end

    context "new_action_at_root ff on" do
      test "lists action on marketplace after create if not already listed" do
        enable_feature_flag(:new_action_at_root, @action.repository)
        refute_predicate @action, :listed?

        release = create(:release, tag_name: "v2", author: @action.repository.owner, repository: @action.repository)
        repo_action_release = RepositoryActionRelease.create(repository_action: @action, release: release, published_on_marketplace: true)

        assert_predicate @action.reload, :listed?
        assert @action.slug.present?
        assert_predicate repo_action_release.reload, :published_on_marketplace
      end

      test "does nothing if already listed" do
        enable_feature_flag(:new_action_at_root, @action.repository)
        release_v1 = create(:release, tag_name: "v1", author: @action.repository.owner, repository: @action.repository)
        repo_action_release_v1 = RepositoryActionRelease.create(repository_action: @action, release: release_v1, published_on_marketplace: true)

        assert_predicate @action.reload, :listed?
        assert @action.slug.present?

        release = create(:release, tag_name: "v2", author: @action.repository.owner, repository: @action.repository)
        repo_action_release_v2 = RepositoryActionRelease.create(repository_action: @action, release: release, published_on_marketplace: true)

        assert_predicate @action.reload, :listed?
        assert @action.slug.present?
        assert_predicate repo_action_release_v1.reload, :published_on_marketplace
        assert_predicate repo_action_release_v2.reload, :published_on_marketplace
      end

      test "does not error out if you try to list a RepositoryAction while there is another RepositoryAction for the same repository that exists with a different action path" do
        repo = create(:repository, from_example: :javascript_action, owner: @owner)
        enable_feature_flag(:new_action_at_root, repo)

        update_action_yml_file(user: @owner, repo: repo, name: "actionfiles", path: "action.yaml")
        yaml_repo_action = create(:repository_action, :with_two_factor_enabled, :with_signed_marketplace_agreement, repository: repo, name: "bobs", path: "action.yaml")

        release = create(:release, tag_name: "v1", author: repo.owner, repository: repo)
        yaml_repo_action_release = RepositoryActionRelease.create(repository_action: yaml_repo_action, release: release, published_on_marketplace: true)

        assert_predicate yaml_repo_action.reload, :listed?
        assert yaml_repo_action.slug.present?

        # release yml action
        repo.reload
        update_action_yml_file(user: @owner, repo: repo, name: "actionfiles", path: "action.yml")
        ref = repo.heads.find(repo.default_branch)
        ref.append_commit({ committer: repo.owner, message: "deleting action.yaml" }, repo.owner) do |changes|
          changes.remove("action.yaml")
        end

        yml_repo_action = create(:repository_action, repository: repo, name: "actionfiles", path: "action.yml")
        refute_predicate yml_repo_action, :listed?

        release_2 = create(:release, tag_name: "v2", author: repo.owner, repository: repo)
        yml_repo_action_release = RepositoryActionRelease.create(repository_action: yml_repo_action, release: release_2, published_on_marketplace: true)
        assert_predicate yml_repo_action.reload, :listed?
        assert yml_repo_action.reload.slug.present?

        refute_predicate yaml_repo_action_release.reload, :published_on_marketplace
        refute_predicate yaml_repo_action.reload, :listed?
        refute yaml_repo_action.slug.present?
      end
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
