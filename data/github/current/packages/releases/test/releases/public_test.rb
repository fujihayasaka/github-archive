# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"
class Releases::PublicTest < Api::TestCase
  include PerformanceTestHelpers
  include UploadableTestHelpers

  fixtures do
    setup_search
  end

  teardown do
    teardown_search
  end

  setup do
    # TODO: this setup should be done via the public interface once it exists
    @org = create :organization
    @user = create(:user)
    @repo = create :repository, owner: @user, from_example: :repository_test_simple
    @org_repo = create(:private_repository, owner: @org)
    @release = create :release, tag_name: "example-release", repository: @repo, author: @user
    @release_asset = ReleaseAsset.new uploader: @user, release: @release, size: 123
    save_file_for_uploadable @release_asset, name: "tater_one.jpg"
    # Repo with v1.0 v2.0 v3.0 etc for creating versioned releases
    @version_tags_repo = create :repository, owner: @user, from_example: :tags_galore
  end

  context ".latest_for_repository" do
    test "returns release for nil user" do
      with_indexed_releases(@repo.releases) do
        assert_equal @release, Releases::Public.latest_for_repository(@repo, nil)
      end
    end

    test "returns the latest published release for the repository" do
      latest_release = create :release, repository: @repo
      with_indexed_releases(@repo.releases) do
        assert_equal latest_release, Releases::Public.latest_for_repository(@repo, @repo.owner)
      end
    end

    test "ignores drafts" do
      release = create :release, repository: @repo, state: :draft
      with_indexed_releases([release, @release]) do
        assert_equal @release, Releases::Public.latest_for_repository(@repo, @repo.owner)
      end
    end

    test "ignores prereleases" do
      release = create :release, repository: @repo, prerelease: true
      with_indexed_releases([release, @release]) do
        assert_equal @release, Releases::Public.latest_for_repository(@repo, @repo.owner)
      end
    end
  end

  context ".published_releases_for_repository?" do
    test "does not return prereleases or drafts" do
      repo = create :repository, from_example: :repository_test_simple
      draft = create :release, repository: repo, state: :draft
      prerelease = create :release, tag_name: "v1", repository: repo, prerelease: true
      refute Releases::Public.published_releases_for_repository?(repo.id)
      prerelease = create :release, tag_name: "v2", repository: repo
      assert Releases::Public.published_releases_for_repository?(repo.id)
    end
  end

  context ".load_release" do
    test "returns the expected record" do
      release = Releases::Public.load_release(@release.id)
      assert_equal @release.name, T.must(release).name
    end

    test "returns nil when the record does not exist" do
      release = Releases::Public.load_release(999999999)
      assert_nil release
    end
  end

  context ".load_releases" do
    test "return the expected records" do
      another_release = create :release, repository: @repo
      releases = Releases::Public.load_releases([@release.id, another_release.id])

      assert_same_elements [@release.name, another_release.name], releases.map(&:name)
    end

    test "returns the expected records when passing a record that does not exist" do
      releases = Releases::Public.load_releases([@release.id, 999999999])

      assert_equal [@release.name], releases.map(&:name)
    end

    test "returns empty when the records do not exist" do
      releases = Releases::Public.load_releases([888888, 999999999])

      assert_empty releases
    end

    test "relationships are applied to query" do
      release_ids = create_list(:release, 10, repository: @repo).map(&:id)
      releases = T.unsafe(Releases::Public.load_releases(release_ids, relationships: { repository: :owner }))

      assert releases.first.association(:repository).loaded?
      assert releases.first.repository.association(:owner).loaded?
    end
  end

  context ".load_releases_for_repository" do
    test "prefill repository on loaded releases" do
      another_release = create :release, repository: @repo

      assert_query_count_per_table({ repositories: 0 }) do
        releases = Releases::Public.load_releases_for_repository([@release.id, another_release.id], @repo)

        assert_equal @repo.name, releases.map { |r| r.repository.name }.uniq.first
      end
    end
  end

  context ".load_releases_and_prefill_tags" do
    test "prefill tags when requested via options" do
      releases = create_list :release, 10, repository: @repo

      # Forget cached tags so we can measure new requests
      # TODO: mesaure Spokes API calls instead
      @repo.reload
      assert_git_rpc_calls(count: 0) do
        releases = Releases::Public.load_releases_and_prefill_tags(releases, @repo)

        assert_equal [true], T.unsafe(releases).map(&:tagged?).uniq
      end
    end
  end

  context ".load_by_tag" do
    test "returns the expected release for the tag" do
      release = Releases::Public.load_by_tag(@release.repository_id, @release.tag_name)
      assert_equal @release.id, T.must(release).id
    end

    test "doesn't find the release when the tag is right and the repo is wrong" do
      assert_nil Releases::Public.load_by_tag(@release.repository_id + 1, @release.tag_name)
    end

    test "doesn't find the release when the tag is wrong and the repo is right" do
      assert_nil Releases::Public.load_by_tag(@release.repository_id, "another-name")
    end

    test "doesn't find draft releases unless allowed" do
      draft = create :release, repository: @release.repository, state: "draft", tag_name: "special"
      assert_nil Releases::Public.load_by_tag(draft.repository_id, draft.tag_name)
      assert_equal draft.id, T.must(
        Releases::Public.load_by_tag(draft.repository_id, draft.tag_name, include_drafts: true)
      ).id
    end
  end

  context ".load_by_author" do
    test "loads nothing for wrong author" do
      nobody = create :user
      result = Releases::Public.load_by_author(nobody.id)
      assert_equal 0, result.count
    end

    test "load releases for author" do
      another_user = create :user
      @repo.add_member another_user

      create :release, tag_name: "second-from-user", repository: @repo, author: @user
      create :release, tag_name: "another-author", repository: @repo, author: another_user

      result = Releases::Public.load_by_author(@user.id)
      assert_same_elements %w[example-release second-from-user], result.map(&:tag_name)
    end
  end

  context ".build_from_tag" do
    test "build for an non-existent git tag" do
      assert_nil Releases::Public.build_from_tag(@repo, "nooope")
    end

    test "build for a repo tag" do
      release = Releases::Public.build_from_tag(@repo, "v2")
      assert T.must(release).new_record?
      refute T.must(release).notes?
      refute T.must(release).viewable?
    end
  end

  context ".create" do
    test "creates a release" do
      release = T.unsafe(Releases::Public).create_release(
        repository_id: @repo.id,
        author_id: @repo.owner_id,
        tag_name: "special-release",
        name: "Special Release",
        body: "the body",
        target_commitish: "special"
      )

      assert_empty release.errors
      release = T.must(Releases::Public.load_release(release.id))
      refute_nil release

      assert_equal @repo.id, release.repository_id
      assert_equal @repo.owner_id, release.author_id
      assert_equal "special-release", release.tag_name
      assert_equal "Special Release", release.name
      assert_equal "the body", release.body
      assert_equal "special", release.target_commitish
    end

    test "creates a release with generated release notes" do
      release = T.unsafe(Releases::Public).create_release(
        repository_id: @repo.id,
        author_id: @repo.owner_id,
        tag_name: "special-release",
        target_commitish: "special",
        generate_release_notes: true
      )

      assert_empty T.unsafe(release).errors
      release = T.must(Releases::Public.load_release(release.id))
      refute_nil release

      assert_equal @repo.id, release.repository_id
      assert_equal @repo.owner_id, release.author_id
      assert_equal "special-release", release.tag_name
      assert_equal "special-release", release.name
      assert_includes release.body, "**Full Changelog**: "
      assert_includes release.body, "special-release"
      assert_equal "special", release.target_commitish
    end

    test "creates a release with generated release notes does not overwrite name and appends to body" do
      release = T.unsafe(Releases::Public).create_release(
        repository_id: @repo.id,
        author_id: @repo.owner_id,
        tag_name: "special-release",
        target_commitish: "special",
        name: "Second Release",
        body: "Enjoy it.",
        generate_release_notes: true
      )

      assert_empty release.errors
      release = T.unsafe(Releases::Public.load_release(release.id))
      refute_nil release

      assert_equal @repo.id, release.repository_id
      assert_equal @repo.owner_id, release.author_id
      assert_equal "special-release", release.tag_name
      assert_equal "Second Release", release.name
      assert release.body.starts_with? "Enjoy it.\n\n"
      assert_includes release.body, "**Full Changelog**: "
      assert_includes release.body, "special-release"
      assert_equal "special", release.target_commitish
    end

    test "returns a release public model with errors" do
      release = T.unsafe(Releases::Public).create_release(
        repository_id: @repo.id,
        author_id: @repo.owner_id,
        tag_name: "secret-release",
        name: "Secret Release",
        body: "",
        target_commitish: "fake-ref"
      )

      assert_nil release.id
      assert_equal ["is invalid"], T.unsafe(release).errors[:target_commitish]

      release = T.unsafe(Releases::Public).create_release(repository_id: @repo.id, author_id: @repo.owner_id)
      assert_nil release.id
      assert_equal ["can't be blank"], T.unsafe(release).errors[:tag_name]
    end
  end

  context ".tags_as_releases" do
    test "finds releases and tags together when paging" do
      Spokesd.enable_spokesd

      create :release, repository: @release.repository, state: "published", tag_name: "v2"
      assert_equal @repo.sorted_tags.map(&:name), Releases::Public.tags_as_releases(@repo).collect(&:tag_name)
    end

    test "finds pages of releases and tags together" do
      Spokesd.enable_spokesd

      repo_tags = @repo.sorted_tags.map(&:name)
      assert_equal repo_tags.first, Releases::Public.tags_as_releases(@repo).collect(&:tag_name).first
      assert_equal repo_tags[1..-1], Releases::Public.tags_as_releases(@repo, after: "1.0.0").collect(&:tag_name)
    end

    test "finds pages of tags when unicode tag" do
      create :release, name: "Alpha Prerelease", tag_name: "v1.λ.2", repository: @repo, prerelease: true, created_at: DateTime.new(2017, 01, 03)
      Spokesd.enable_spokesd
      assert_equal "v1", Releases::Public.tags_as_releases(@repo, after: "v1.λ.2").collect(&:tag_name).first
    end
  end

  context ".tags_as_releases-decouple_tags" do
    test "finds only tags that are releases when paging" do
      with_indexed_releases do
        tag_names = Releases::Public.query_releases(@version_tags_repo, @user).models.collect(&:tag_name)
        assert_equal 3, tag_names.size
        assert_equal "v4.0", tag_names.first
      end
    end

    test "finds pages of releases and tags together" do
      with_indexed_releases do
        assert_equal ["v4.0"], Releases::Public.query_releases(@version_tags_repo, @user, limit: 1).models.collect(&:tag_name)
        tag_names = Releases::Public.query_releases(@version_tags_repo, @user, limit: 2, page: 2).models.collect(&:tag_name)
        assert_equal ["v1.0"], tag_names
      end
    end
  end

  context ".load_asset" do
    test "returns the expected asset release record" do
      asset = ReleaseAsset.new uploader: @user, release: @release, size: 123
      save_file_for_uploadable asset, name: "tater.jpg"

      assert_equal asset, Releases::Public.load_asset(T.unsafe(asset).id)
    end

    test "returns a non-existent release asset" do
      assert_nil Releases::Public.load_asset(123456)
    end
  end

  context ".load_assets" do
    test "returns the expected release asset records" do
      another_release_asset = ReleaseAsset.new uploader: @user, release: @release, size: 234
      save_file_for_uploadable another_release_asset, name: "tater_two.jpg"

      assert_same_elements [@release_asset, another_release_asset], Releases::Public.load_assets([@release_asset.id, another_release_asset.id])
    end

    test "returns the expected records when passing an asset id that does not exist" do
      assert_same_elements [@release_asset], Releases::Public.load_assets([@release_asset.id, 999999999])
    end

    test "returns an empty array for non-existent release assets" do
      assert_empty Releases::Public.load_assets([888888, 999999999])
    end
  end

  context ".generate_release_notes" do
    test "Default notes generation - default target_commitish, no previous tag" do
      Timecop.freeze(Time.local(2000, 1, 1, 0, 0, 0)) do
        title, body = Releases::Public.generate_release_notes(@version_tags_repo, "v1.0")

        expected_body = <<~EOS.chomp
          **Full Changelog**: https://github.com/#{@user}/#{@version_tags_repo}/commits/v1.0
        EOS

        assert_equal "v1.0", title
        assert_equal expected_body, body
      end
    end

    test "Default notes generation - Previous semver tag exists" do
      Timecop.freeze(Time.local(2000, 1, 1, 0, 0, 0)) do
        title, body = Releases::Public.generate_release_notes(@version_tags_repo, "v4.1.0", target_commitish: "master")

        expected_body = <<~EOS.chomp
          **Full Changelog**: https://github.com/#{@user}/#{@version_tags_repo}/compare/v3.0.3...v4.1.0
        EOS

        assert_equal "v4.1.0", title
        assert_equal expected_body, body
      end
    end

    test "Default notes generation - Existing tags v3.0.3 and v3.0.1, release for existing tag v3.0.2" do
      Timecop.freeze(Time.local(2000, 1, 1, 0, 0, 0)) do
        # If tags v3.0.3 and v3.0.1 exist, and we go back to make a release for a v3.0.2 tag that's in between those existing tags
        # make sure that the compare point will be between v3.0.1 and v3.0.2, as opposed to the latest tag (v4.0) and v3.0.2
        title, body = Releases::Public.generate_release_notes(@version_tags_repo, "v3.0.2", target_commitish: "v3.0.2")

        expected_body = <<~EOS.chomp
          **Full Changelog**: https://github.com/#{@user}/#{@version_tags_repo}/compare/v3.0.1...v3.0.2
        EOS

        assert_equal "v3.0.2", title
        assert_equal expected_body, body
      end
    end

    test "Default notes generation - no previous valid semver tag, but previous Release" do
      # previous release on tag v3.0, which is not valid semver
      create :release, name: "Version 1.0!", tag_name: "v3.0", author: @user, repository: @version_tags_repo
      title, body = Releases::Public.generate_release_notes(@version_tags_repo, "v3.0.1", target_commitish: "v3.0.1")

      # make sure the compare point is the tag with the previous release associated
      expected_body = <<~EOS.chomp
        **Full Changelog**: https://github.com/#{@user}/#{@version_tags_repo}/compare/v3.0...v3.0.1
      EOS

      assert_equal "v3.0.1", title
      assert_equal expected_body, body
    end

    test "Default notes generation - should select previous tag, not latest release" do
      # If using the `Previous tag: auto` option, the previous tag returned should be the previous release tag
      # NOT the release marked as "Latest"
      releases = [
        create(:release, repository: @version_tags_repo, name: "v1.0 release", tag_name: "v1.0", author: @user),
        create(:release, repository: @version_tags_repo, name: "v2.0 release", tag_name: "v2.0", author: @user),
        create(:release, repository: @version_tags_repo, name: "v3.0 release", tag_name: "v3.0", author: @user),
      ]

      # Manually set a latest release
      @version_tags_repo.set_latest_release releases[0]
      assert_equal @version_tags_repo.repository_latest_release&.release&.tag_name, releases[0].tag_name

      # When a user chooses "Previous tag: auto" in the UI, `previous_tag_name` comes as an empty string
      title, body = Releases::Public.generate_release_notes(@version_tags_repo, "v3.0", target_commitish: "v3.0", previous_tag_name: "")

      # make sure the compare point is the tag with the previous release associated
      expected_body = <<~EOS.chomp
        **Full Changelog**: https://github.com/#{@user}/#{@version_tags_repo}/compare/v2.0...v3.0
      EOS

      assert_equal "v3.0", title
      assert_equal expected_body, body

      # make sure the compare point is NOT the tag from the release marked as "latest"
      unexpected_body = <<~EOS.chomp
        **Full Changelog**: https://github.com/#{@user}/#{@version_tags_repo}/compare/v1.0...v3.0
      EOS

      refute_equal unexpected_body, body
    end

    test "Release notes API returns error for invalid commitish" do
      assert_raises Releases::Error do
        Releases::Public.generate_release_notes(@version_tags_repo, "v1.0", target_commitish: "invalid_commitish_value_3")
      end
    end

    test "generate_release_notes respects yaml config" do
      release_note_config = {
        "title" => "This will be ignored since we can't override title yet",
        "changelog" => {
          "categories" => [{ "title" => "All changes", "labels" => ["*"] }]
        }
      }

      create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", release_note_config.to_yaml)
      })

      pr = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo)
      merge = create(:commit, repository: @version_tags_repo)
      pr.update(merge_commit_sha: merge.oid)

      title, body = Releases::Public.generate_release_notes(@version_tags_repo, "v3.1")

      expected_section = <<~EOS.chomp
        ### All changes
        * #{pr.title} by @#{pr.user} in #{pr.permalink}

      EOS

      assert_equal "v3.1", title
      assert_includes body, expected_section

      # Test that custom config file overrides default repository config
      custom_release_note_config = {
        "changelog" => {
          "categories" => [{ "title" => "Custom all changes", "labels" => ["*"] }]
        }
      }

      create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add("index/custom_release.yml", custom_release_note_config.to_yaml)
      })

      title, body = Releases::Public.generate_release_notes(@version_tags_repo, "v3.1", configuration_file_path: "index/custom_release.yml")

      expected_section = <<~EOS.chomp
        ### Custom all changes
        * #{pr.title} by @#{pr.user} in #{pr.permalink}
      EOS

      assert_equal "v3.1", title
      assert_includes body, expected_section
    end

    test "generate_release_notes returns error for non-existant configuration_file_path" do
      assert_raises Releases::Error do
        Releases::Public.generate_release_notes(@version_tags_repo, "v3.1", configuration_file_path: "foo-bar.yaml")
      end
    end
  end

  context ".published_release_count_for_repository" do
    test "count published releases" do
      repo_with_tags = create :repository, owner: @user, from_example: :tags_galore
      create :release, name: "Version 1.0!", tag_name: "v1.0", author: @user, repository: repo_with_tags, target_commitish: "master"
      create :release, name: "Version 3.0!", tag_name: "v3.0", author: @user, repository: repo_with_tags, target_commitish: "master", draft: true
      assert_equal 1, Releases::Public::published_release_count_for_repository(repo_with_tags.id)
    end
  end

  context ".unpublish_unsearchable_releases" do
    test "does unpublish unsearchable release" do
      # arrange
      repo = create :repository, from_example: :tags_galore
      create :release, tag_name: "v0.0.1", repository: repo, draft: true
      create :release, tag_name: "v1.0", repository: repo
      create :release, tag_name: "v3.0", repository: repo
      unsearchable = create :release, :skip_validation, tag_name: "v1.0.1", repository: repo

      # act
      result = assert_query_count_per_table({ repositories: 2 }) do
        Releases::Public.unpublish_unsearchable_releases(repo_id: repo.id, dry_run: false, perform_validations: true)
      end

      # assert
      assert_equal 4, result[:all]
      assert_equal 3, result[:searchable]
      assert_equal 1, result[:unsearchable]
      assert_equal [unsearchable.id], result[:unpublished_ids]
    end

    test "does not unpublish unsearchable release when dry_run=true" do
      # arrange
      repo = create :repository, from_example: :tags_galore
      create :release, tag_name: "v0.0.1", repository: repo, draft: true
      create :release, tag_name: "v1.0", repository: repo
      create :release, tag_name: "v3.0", repository: repo
      create :release, :skip_validation, tag_name: "v1.0.1", repository: repo

      # act
      result = assert_query_count_per_table({ repositories: 1 }) do
        Releases::Public.unpublish_unsearchable_releases(repo_id: repo.id, dry_run: true, perform_validations: true)
      end

      # assert
      assert_equal 4, result[:all]
      assert_equal 3, result[:searchable]
      assert_equal 1, result[:unsearchable]
      assert_equal [], result[:unpublished_ids]
    end

    test "does unpublish unsearchable invalid release" do
      # arrange
      repo = create :repository, from_example: :tags_galore
      create :release, tag_name: "v0.0.1", repository: repo, draft: true
      create :release, tag_name: "v1.0", repository: repo
      create :release, tag_name: "v3.0", repository: repo
      unsearchable = create :release, :skip_validation, tag_name: "v1.0.1", repository: repo, target_commitish: "non-existing"

      # act
      result = assert_query_count_per_table({ repositories: 2 }) do
        Releases::Public.unpublish_unsearchable_releases(repo_id: repo.id, dry_run: false, perform_validations: false)
      end

      # assert
      assert_equal 4, result[:all]
      assert_equal 3, result[:searchable]
      assert_equal 1, result[:unsearchable]
      assert_equal [unsearchable.id], result[:unpublished_ids]
    end

    test "does not unpublish unsearchable invalid release when perform_validations=true" do
      # arrange
      repo = create :repository, from_example: :tags_galore
      create :release, tag_name: "v0.0.1", repository: repo, draft: true
      create :release, tag_name: "v1.0", repository: repo
      create :release, tag_name: "v3.0", repository: repo
      create :release, :skip_validation, tag_name: "v1.0.1", repository: repo, target_commitish: "non-existing"

      # act/assert
      assert_query_count_per_table({ repositories: 1 }) do
        assert_raises ActiveRecord::RecordInvalid do
          Releases::Public.unpublish_unsearchable_releases(repo_id: repo.id, dry_run: false, perform_validations: true)
        end
      end
    end
  end

  def with_indexed_releases(releases = nil, &block)
    # Create releases in a random order to show that they get retrieved in sorted in tag order
    releases ||= [
      create(:release, repository: @version_tags_repo, state: "published", tag_name: "v1.0"),
      create(:release, repository: @version_tags_repo, state: "published", tag_name: "v4.0"),
      create(:release, repository: @version_tags_repo, state: "published", tag_name: "v3.0"),
    ]

    make_searchable *releases

    block.call
  end
end
