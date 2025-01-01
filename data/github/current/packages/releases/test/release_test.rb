# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"
require "test_helpers/spokesd"

module ReleasesSharedTests
  extend T::Helpers
  include StringFromBinaryTestHelper

  requires_ancestor { GitHub::TestCase }

  def test_builds_release_objects_from_a_collection_of_refs
    tags = [
      @from_tags_repo.tags.find("release"),
      @from_tags_repo.tags.find("light"),
      @from_tags_repo.tags.find("light-with-content"),
      @from_tags_repo.tags.find("annotated"),
      @from_tags_repo.tags.find("annotated-with-content"),
      @from_tags_repo.tags.find("blob-ref"),
    ]

    rel = create :release, name: "RELEASE", tag_name: "release",
      body: "RELEASE IT",
      author: @user, repository: @from_tags_repo

    releases = Release.from_tags(@from_tags_repo, tags)
    assert_equal %w(release light light-with-content annotated annotated-with-content blob-ref),
      releases.map(&:tag_name)

    assert_equal [
      "RELEASE",
      "light",
      "light-with-content: commit",
      "annotated",
      "annotated-with-content: annotated tag",
      "blob-ref",
    ], releases.map(&:name)

    assert_equal [
      "RELEASE IT",
      "initial",
      "now with extra content",
      "annotate this crap",
      "now with extra content",
      "",
    ], releases.map(&:body)

    assert_equal [@user, @committer, @committer, @committer, @committer, nil],
      releases.map(&:author)
  end
end

class ReleasesTest < GitHub::TestCase
  self.these_tests_are_order_dependent_and_yearn_to_be_random

  include ReleasesSharedTests
  include HydroTestHelpers
  include PushTestHelper
  include BackgroundDeletesTestHelpers
  include GitHub::DatabaseQueryWarningsTestHelpers
  include GitHub::DomAssertionTestHelpers
  include UploadableTestHelpers
  include DogstatsTestHelpers
  include RepositoryActionTestHelpers

  fixtures do
    @org = create(:organization)
    @user = @org.admins.first
    @committer = create :user, email: "TECHNOWEENIE@gmail.com"
    @user2 = create :user
    @user3 = create :user

    # `v2` does not have a Release record
    @repo = create :repository, owner: @user, from_example: :repository_test_simple
    # Releases have the same target
    @boring_repo = create(:repository, from_example: :repository_test_simple)
    # Release and Prereleases
    @writable_repo = create :repository, owner: @user, from_example: :repository_test_simple
    # Prerelease only
    @beta_repo = create :repository, owner: @user, from_example: :repository_test_simple
    # Until releases go genpop, release *events* are only enabled for
    # private GitHub-owned repos
    @release_events_repo = create(:private_repository, owner: @org, from_example: :repository_test_simple)

    @from_tags_repo = create :repository, owner: @user, from_example: :branch_and_tag_refs

    @empty_repo = create :repository, owner: @user
    Repository.where(id: @empty_repo.id).update_all(pushed_at: nil)

    @release = create :release, name: "Version One!", tag_name: "v1", author: @user, repository: @repo
    @abandoned_release = create :release, name: "Someone deleted the tag", tag_name: "nonexist", author: @user, repository: @repo, draft: true

    @beta_prerelease = create :release, name: "Beta Prerelease", tag_name: "v2", author: @user, repository: @beta_repo, prerelease: true

    @lambda_release = create :release, name: "Alpha Prerelease", tag_name: "v1.λ.2", author: @user, repository: @repo

    # ["v4", "v3", "v2", "v1", "v0"]
    @paginated_repo = create :repository, owner: @user, from_example: :paginated_tags

    # create a heart reaction
    create :reaction, subject: @release, content: "heart", user: @user

    example_repo_snapshot

    setup_search
  end

  setup do
    example_repo_restore

    DGit.bless @repo, @release_events_repo, @boring_repo, @beta_repo
    DGit.bless @writable_repo, @from_tags_repo, @paginated_repo

    GitHub.stratocaster_store.reset!
  end

  def expected_audit_log_payload(release, repo: @release_events_repo, author: @user, actor: @user)
    payload = {
      release_id: release.id,
      author: author.login,
      author_id: author.id,
      repo: repo.name_with_owner,
      repo_id: repo.id,
      public_repo: repo.public?,
      actor: actor.to_s,
      actor_id: actor.id,
      name: release.name,
      tag_name: release.exposed_tag_name,
      target_commitish: release.target_commitish,
      state: release.state,
      prerelease: release.prerelease,
    }

    # if tag_name ever starts with untagged-, then the wrong tag name is being exposed
    assert payload[:tag_name]
    refute payload[:tag_name].start_with?("untagged-")

    payload
  end

  def expected_webhook_payload(release, repo: @release_events_repo, author: @user, actor: @user)
    {
      spammy: false,
      release_id: release.id,
      author: author.login,
      author_id: author.id,
      repository: repo.name_with_owner,
      repository_id: repo.id,
      public_repo: repo.public?,
      actor: actor.to_s,
      actor_id: actor.id,
    }
  end

  context "author_or_owner" do
    test "with author" do
      rel = Release.new author: @user, repository: @release_events_repo
      assert_equal @user, rel.author_or_owner
    end

    test "with user repository owner" do
      rel = Release.new repository: @repo
      assert_equal @user, rel.author_or_owner
    end

    test "with org repository owner" do
      user = create(:user)
      repo = build :repository, owner: @org
      repo.created_by_user_id = user.id
      repo.save!
      rel = Release.new repository: repo
      assert_equal user, rel.author_or_owner
    end
  end

  test "comparison" do
    @release.target_commitish = "master"
    @release.repository.default_branch = "something_crazy"
    comparison = @release.comparison
    assert_equal({
      "ahead" => 0,
      "behind" => 2,
      "base_branch" => "master",
      "commit_range" => "v1...master" }, comparison)
  end

  test "comparison of release created from target sha" do
    @release.target_commitish = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
    assert_nil @release.comparison
  end

  test "exposed_tag_name for published release" do
    @release.pending_tag = "booya"
    assert_equal "v1", @release.exposed_tag_name
  end

  test "exposed_tag_name for draft release" do
    assert_equal "nonexist", @abandoned_release.pending_tag
    assert_match /^untagged-/, @abandoned_release.tag_name
    assert_equal "nonexist", @abandoned_release.exposed_tag_name
  end

  test "exposed_tag_name for draft release with nil pending_tag" do
    @abandoned_release.pending_tag = nil
    assert_equal "", @abandoned_release.exposed_tag_name
  end

  test "setting tag_name for draft release" do
    @abandoned_release.update!(tag_name: "booya")
    assert_equal "booya", @abandoned_release.pending_tag
    assert_match /^untagged-/, @abandoned_release.tag_name
    assert_equal "booya", @abandoned_release.exposed_tag_name
  end

  test "handles pending_tag with wide multibyte characters" do
    tag_name = "🔥🔥🔥-three-alarm-fire"
    @release.update!(tag_name: tag_name)
    assert_equal tag_name, @release.reload.pending_tag
  end

  test "rejects pending_tag longer than 1024 bytes" do
    tag_name = "🔥" * 300
    rel = build :release, name: "long_pending_tag", tag_name: tag_name,
      author: @user, repository: @repo, state: :draft
    refute_predicate rel, :valid?
    refute_empty rel.errors[:pending_tag]
  end

  test "handles tag_name with wide multibyte characters" do
    tag_name = "🔥🔥🔥-three-alarm-fire"
    release = create :release, name: "Version Two!", tag_name: tag_name, author: @user, repository: @repo
    assert_equal tag_name, release.reload.tag_name
  end

  test "uses repository default branch as default #target_commitish" do
    rel = Release.new repository: @repo
    assert_equal @repo.default_branch, rel.target_commitish
  end

  test "accepts empty #target_commitish as nil" do
    rel = Release.new repository: @repo

    rel.target_commitish = ""
    assert_equal @repo.default_branch, rel.target_commitish

    rel.target_commitish = "a"
    assert_equal "a", rel.target_commitish
  end

  test "associates a tag correctly" do
    assert @release.tagged?
    assert_equal "v1", @release.tag.name
    assert_kind_of Tag, @release.tag_target
  end

  test "rejects bad tag names" do
    %w(abc. a..b).each do |bad|
      rel = build :release, name: "Version #{bad}", tag_name: bad,
        author: @user, repository: @repo
      assert !rel.valid?, "apparently #{bad.inspect} is ok"
      assert rel.errors[:tag_name], "invalid, but #{bad.inspect} is still ok"
    end
  end

  test "rejects invalid tag names" do
    hex_name = "f5a334b5756a7eaceceaab87b3172f7caebc0976"
    rel = build :release, name: "Version #{hex_name}", tag_name: hex_name,
      author: @user, repository: @repo
    assert !rel.valid?, "#{hex_name.inspect} should be invalid but is not."
    assert rel.errors[:pre_receive], "#{hex_name.inspect} should have errors but does not."
  end

  test "rejects bad commitish" do
    rel = build :release, name: "Version 1.0", tag_name: "1.0",
      author: @user, repository: @repo, target_commitish: "booya",
      state: :draft
    assert !rel.valid?
    assert rel.errors[:target_commitish]
  end

  # uses bad git data from test/models/repository_objects_collection_test.rb
  test "rejects bad ref" do
    repo = create :repository, owner: @user, from_example: :refs_test

    rel = build :release, name: "Version 1.0", tag_name: "1.0",
      author: @user, repository: repo, target_commitish: "9999999999999999999999999999999999999999",
      state: :draft

    assert_nil rel.target_commit
  end

  test "rejects large description" do
    rel = build :release, name: "Version 1.0", tag_name: "1.0",
      author: @user, repository: @repo, target_commitish: "master",
      state: :draft, body: "0" * (Release::BODY_CHAR_LIMIT * 2)
    assert !rel.valid?
    assert rel.errors[:body]
  end

  test "finds a tag object from a tag ref" do
    assert @release.tag.target.kind_of?(Tag)
    assert @release.tag_target.kind_of?(Tag)
    assert @release.tag.commit.kind_of?(Commit)
  end

  test "does not associate invalid tags" do
    assert !@abandoned_release.tagged?
    assert_nil @abandoned_release.tag
    assert_nil @abandoned_release.tag_target
  end

  test "ensures name is UTF-8 encoded" do
    @release.name = "ümlaut".b
    assert_equal Encoding::UTF_8, @release.name.encoding
  end

  test "fields support multibyte tracked changes" do
    hyphenated_orig = "we-❤️-emojis"
    hyphenated_bytes = "we-\xE2\x9D\xA4\xEF\xB8\x8F-emojis"

    @release.update!(name: "we ❤️ emojis", tag_name: hyphenated_orig, pending_tag: hyphenated_orig)

    assert_multibyte_tracked_changes(@release, :name)
    assert_multibyte_tracked_changes(@release, :tag_name, hyphenated_orig, hyphenated_bytes, "test-🧪")
    assert_multibyte_tracked_changes(@release, :pending_tag, hyphenated_orig, hyphenated_bytes, "test-🧪")
  end

  test "finds releases and tags together when paging" do
    Spokesd.enable_spokesd

    assert_equal ["1.0.0", "v2", "v1.λ.2", "v1"], Release.page_tags(@repo).collect(&:tag_name)
  end

  test "finds pages of releases and tags together" do
    Spokesd.enable_spokesd

    assert_equal ["1.0.0"], Release.page_tags(@repo, limit: 1).collect(&:tag_name)
    assert_equal ["v2"], Release.page_tags(@repo, limit: 1, after: "1.0.0").collect(&:tag_name)
  end

  test "finds pages of tags when unicode tag" do
    Spokesd.enable_spokesd

    assert_equal ["v1"], Release.page_tags(@repo, limit: 1, after: "v1.λ.2").collect(&:tag_name)
  end

  test "finds releases when querying" do
    with_indexed_releases do
      assert_equal ["v1.λ.2", "v1"], Release.query_releases(@repo, @owner).results.collect { |item| item["_model"].tag_name }
    end
  end

  test "finds queries of releases" do
    with_indexed_releases do
      assert_equal ["v1.λ.2"], Release.query_releases(@repo, @owner, limit: 1).results.collect { |item| item["_model"].tag_name }
      assert_equal ["v1"], Release.query_releases(@repo, @owner, limit: 1, page: 2).results.collect { |item| item["_model"].tag_name }
    end
  end

  test "filter queries of releases" do
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :tags_galore)

    releases = []
    releases << create(:release, name: "Version One!", tag_name: "v1", author: user, repository: repo)
    releases << create(:release, name: "Alpha Prerelease", tag_name: "v1.λ.2", author: user, repository: repo)

    with_indexed_releases(releases) do
      assert_equal ["v1.λ.2", "v1"], Release.query_releases(repo, user, filter_phrase: "v1").results.collect { |item| item["_model"].tag_name }
      assert_equal ["v1.λ.2"], Release.query_releases(repo, user, filter_phrase: "tag:v1.λ").results.collect { |item| item["_model"].tag_name }
      assert_equal ["v1"], Release.query_releases(repo, user, filter_phrase: "One").results.collect { |item| item["_model"].tag_name }
    end
  end

  test "sorts releases alphabetically with non semver tags" do
    repo = create :repository, owner: @user, from_example: :repository_test_simple

    release_69_3 = create :release, name: "Release 69", tag_name: "releases/69.3", author: @user, repository: repo
    release_70_0 = create :release, name: "Release 70", tag_name: "releases/70.0", author: @user, repository: repo

    with_indexed_releases([release_69_3, release_70_0]) do
      assert_equal ["releases/70.0", "releases/69.3"], Release.query_releases(repo, @owner).results.collect { |item| item["_model"].tag_name }
    end
  end

  test "creates a Release object from lightweight tag and simple body" do
    tag = @from_tags_repo.tags.find "light"
    release = Release.from_tag tag
    assert release.tagged?
    assert_equal "light", release.name
    assert_equal "initial", release.body
    assert_equal tag.target.authored_date, release.created_at
    assert_equal "2010-05-13", release.created_at.to_date.to_s
    assert_equal @committer, release.author
  end

  test "release body encoding" do
    release = @writable_repo.releases.build author: @user
    release.with_params title: "Yup", tag_name: "v9000", draft: true
    release.body = "hello"
    release.save!
    release.reload
    assert_equal ::Encoding::UTF_8, release.body.encoding
  end

  test "release body renders HTML links in emails with absolute paths" do
    release = @writable_repo.releases.build author: @user
    release.with_params title: "Yup", tag_name: "v9000"
    release.body = "[link](./README.md)"
    assert_contains_selector "a[href='https://github.com/#{@writable_repo.name_with_owner}/blob/v9000/README.md']", release.body_html_for_email
  end

  test "creates a Release object from lightweight tag and expanded body" do
    tag = @from_tags_repo.tags.find "light-with-content"
    release = Release.from_tag tag
    assert release.tagged?
    assert_equal "light-with-content: commit", release.name
    assert_equal "now with extra content", release.body
    assert_equal tag.target.authored_date, release.created_at
    assert_equal "2014-05-05", release.created_at.to_date.to_s
    assert_equal @committer, release.author
  end

  test "creates a Release object from annotated tag and simple body" do
    tag = @from_tags_repo.tags.find "annotated"
    release = Release.from_tag tag
    assert release.tagged?
    assert_equal "annotated", release.name
    assert_equal "annotate this crap", release.body
    assert_equal tag.target.authored_date, release.created_at
    assert_equal "2010-05-13", release.created_at.to_date.to_s
    assert_equal @committer, release.author
  end

  test "creates a Release object from annotated tag and expanded body" do
    tag = @from_tags_repo.tags.find "annotated-with-content"
    release = Release.from_tag tag
    assert release.tagged?
    assert_equal "annotated-with-content: annotated tag", release.name
    assert_equal "now with extra content", release.body
    assert_equal tag.target.authored_date, release.created_at
    assert_equal "2014-05-05", release.created_at.to_date.to_s
    assert_equal @committer, release.author
  end

  context "latest release" do
    test "#is_latest? respects stored latest release" do
      release = create :release, repository: @repo
      @repo.set_latest_release(release)

      # make sure we aren't taking the fallback for this check
      Release.expects(:query_releases).never
      assert release.is_latest?(@repo.owner)
    end

    test "removes saved latest when setting as draft" do
      RepositoryLatestRelease.destroy_all

      # set intial latest release
      release = create :release, repository: @repo
      @repo.set_latest_release(release)
      assert_equal 1, RepositoryLatestRelease.where(repository_id: @repo.id).count

      # change release to draft
      release.reload.update(state: "draft")
      assert_equal 0, RepositoryLatestRelease.where(repository_id: @repo.id).count
      assert_equal false, release.is_latest?(@repo.owner)
    end

    test "removes saved latest when setting as prerelease" do
      RepositoryLatestRelease.destroy_all

      # set intial latest release
      release = create :release, repository: @repo
      @repo.set_latest_release(release)
      assert_equal 1, RepositoryLatestRelease.where(repository_id: @repo.id).count

      # change release to prerelease
      release.reload.update(prerelease: true)
      assert_equal 0, RepositoryLatestRelease.where(repository_id: @repo.id).count
      assert_equal false, release.is_latest?(@repo.owner)
    end

    test "validates before saving release as latest" do
      draft = create :release, repository: @repo, state: "draft"
      prerelease = create :release, repository: @repo, prerelease: true

      # cannot save a draft as latest
      assert_raises ActiveRecord::RecordInvalid do
        draft.with_params(make_latest: true)
        draft.save!
      end

      # cannot save a prerelease as latest
      assert_raises ActiveRecord::RecordInvalid do
        prerelease.with_params(make_latest: true)
        prerelease.save!
      end

      # validation works when not making latest
      draft.with_params(make_latest: false)
      prerelease.with_params(make_latest: false)
      assert draft.save!
      assert prerelease.save!
    end

    test "respects make_latest param during save" do
      release = create :release, repository: @repo
      release.with_params(make_latest: true)
      release.save!

      # doesn't make latest unless the param is set
      release2 = create :release, repository: @repo
      release2.save!

      refute release2.is_latest?(@repo.owner)
      assert release.is_latest?(@repo.owner)
      assert_equal release, @repo.latest_release(@repo.owner)
    end
  end

  context "#build_tag_ref" do
    test "fails correctly on non-existent git tag" do
      assert_nil Release.build_tag_ref(@repo, "nooope")
    end

    test "build for a repo tag" do
      release = T.cast(Release.build_tag_ref(@repo, "v2"), Release)
      assert release.new_record?
      refute release.notes?
      refute release.viewable?
    end
  end

  context "Release#tag_title" do
    test "for an annotated tag" do
      rel = @from_tags_repo.releases.build tag_name: "annotated"
      assert_equal "annotated", rel.tag_title
    end

    test "for an annotated tag with full content" do
      rel = @from_tags_repo.releases.build tag_name: "annotated-with-content"
      assert_equal "annotated tag", rel.tag_title
    end
  end

  context "Release#tag_body" do
    test "for an annotated tag" do
      rel = @from_tags_repo.releases.build tag_name: "annotated"
      assert_equal "annotate this crap", rel.tag_body
    end

    test "for an annotated tag with full content" do
      rel = @from_tags_repo.releases.build tag_name: "annotated-with-content"
      assert_equal "now with extra content", rel.tag_body
    end
  end

  context "Release#display_name" do
    test "for an annotated tag" do
      rel = @from_tags_repo.releases.build tag_name: "annotated"
      assert_equal "annotated", rel.display_name

      rel.name = "sup"
      assert_equal "sup", rel.display_name
    end

    test "for an annotated tag with full content" do
      rel = @from_tags_repo.releases.build tag_name: "annotated-with-content"
      assert_equal "annotated-with-content: annotated tag", rel.display_name

      rel.name = "sup"
      assert_equal "sup", rel.display_name
    end
  end

  context "Release#display_body" do
    test "for empty frozen string" do
      rel = Release.new
      body = rel.display_body
      assert_equal "", body
    end

    test "for an annotated tag" do
      rel = @from_tags_repo.releases.build tag_name: "annotated"
      assert_equal "annotate this crap", rel.display_body

      rel.name = "sup"
      assert_equal "annotated\n\nannotate this crap", rel.display_body

      rel.name = "annotated!"
      assert_equal "annotate this crap", rel.display_body
    end

    test "for an annotated tag with full content" do
      rel = @from_tags_repo.releases.build tag_name: "annotated-with-content"
      assert_equal "now with extra content", rel.display_body

      rel.name = "sup"
      assert_equal "annotated tag\n\nnow with extra content", rel.display_body

      rel.name = "annotated tag!"
      assert_equal "now with extra content", rel.display_body
    end
  end

  test "builds release objects from tags with releases" do
    tags = [@repo.tags.find("v1")]
    releases = Release.from_tags(@repo, tags)
    assert_equal [@release], releases
  end

  test "handles utf-8 tag lists" do
    tag_name = "🔥🔥🔥-three-alarm-fire"
    @release.update!(tag_name: tag_name)
    tags = [@repo.tags.find(tag_name)]
    assert_no_query_warnings do
      releases = Release.from_tags(@repo, tags)
      assert_equal [@release], releases
    end
  end

  test "uses existing Tag created_at on Release" do
    Release.delete_all
    tag = @repo.tags.find("v1").target
    release = @repo.releases.build(author: @user)
    release.with_params title: "Yup", tag_name: "v1", state: :published
    release.save!

    release.reload
    assert_equal tag.authored_date, release.created_at
    assert_equal 2010, release.created_at.year
  end

  test "setting tag_name does not set pending_tag of draft release" do
    rel = Release.new tag_name: "abc", pending_tag: "def", state: :draft
    rel.tag_name = "v1"
    assert_equal "def", rel.pending_tag
  end

  test "setting tag_name sets pending_tag of published release" do
    rel = Release.new tag_name: "abc", pending_tag: "def", state: :published
    rel.tag_name = "v1"
    assert_equal "v1", rel.pending_tag
  end

  test "changes tag_name of published release" do
    assert !@writable_repo.tags.include?("1.0")
    assert !@writable_repo.tags.include?("v1.0.0")

    rel = create :release, tag_name: "1.0", author: @user, repository: @writable_repo

    assert_equal "1.0", rel.tag_name
    assert_equal "1.0", rel.tag.name
    assert_equal "1.0", rel.pending_tag

    @writable_repo.reset_refs
    assert  @writable_repo.tags.include?("1.0")
    assert !@writable_repo.tags.include?("v1.0.0")

    rel.update!(tag_name: "v1.0.0")
    rel.reload
    assert_equal "v1.0.0", rel.tag_name
    assert_equal "v1.0.0", rel.tag.name
    assert_equal "v1.0.0", rel.pending_tag

    @writable_repo.reset_refs
    assert @writable_repo.tags.include?("1.0")
    assert @writable_repo.tags.include?("v1.0.0")
  end

  test "uses existing tag matching pending tag when publishing release" do
    rel = create :release, name: "Version Two", tag_name: "v2", author: @user, repository: @repo, draft: true
    assert_equal "v2", rel.pending_tag
    refute_equal "v2", rel.tag_name

    rel.update!(draft: false)
    assert_equal "v2", rel.pending_tag
    assert_equal "v2", rel.tag_name
    assert_equal "v2", rel.tag.name
  end

  test "creates a pending tag for drafts" do
    release = @writable_repo.releases.build author: @user
    release.with_params title: "Yup", tag_name: "v9000", draft: true
    assert release.save
    release.reload
    refute_equal "v9000", release.tag_name
    assert_equal "v9000", release.pending_tag
    assert !@writable_repo.tags.include?("v9000")
  end

  test "creates a real tag from default branch on publish" do
    release = @writable_repo.releases.build author: @user, state: :published
    release.with_params title: "Yup", tag_name: "v9001"
    assert release.save!
    release.reload

    tag = @writable_repo.tags.find("v9001").target

    assert_equal "v9001", release.tag_name
    assert_equal "63611721afd41f58f801d66e543d8288b4c5eb44", tag.oid
    assert_equal tag.authored_date, release.created_at
  end

  test "handles error when pre-receive causes hook failure" do
    Git::Ref.any_instance.stubs(:write_ref).raises(Git::Ref::HookFailed.new("bad hook stuff"))

    release = @writable_repo.releases.build author: @user, state: :published
    release.with_params title: "Yup", tag_name: "v9001a"

    refute release.save
    assert_match /bad hook stuff/i, release.errors[:pre_receive].to_s
    refute @writable_repo.tags.find("v9001a")
  end

  test "creates a real tag from commitish branch on publish" do
    release = @writable_repo.releases.build author: @user
    release.with_params title: "Yup", tag_name: "v9002", target_commitish: "hot"
    assert release.save!
    release.reload
    assert_equal "v9002", release.tag_name
    assert_equal "63611721afd41f58f801d66e543d8288b4c5eb44", @writable_repo.tags.find("v9002").target.oid
  end

  test "creates a real tag from absolute commitish branch on publish" do
    release = @writable_repo.releases.build author: @user
    release.with_params title: "Yup", tag_name: "v9003", target_commitish: "refs/heads/special"
    assert release.save!
    release.reload
    assert_equal "v9003", release.tag_name
    assert_equal "63611721afd41f58f801d66e543d8288b4c5eb44", @writable_repo.tags.find("v9003").target.oid
  end

  test "creates a real tag from a commit branch on publish" do
    release = @writable_repo.releases.build author: @user
    release.with_params title: "Yup", tag_name: "v9004", target_commitish: "7fd43660b371e21bc2aa306fad0fbff59829aae3"
    assert release.save!
    release.reload
    assert_equal "v9004", release.tag_name
    assert_equal "7fd43660b371e21bc2aa306fad0fbff59829aae3", @writable_repo.tags.find("v9004").target.oid
  end

  test "creates a real tag on publish normalizing name from refs/tags/" do
    release = @writable_repo.releases.build author: @user, state: :published
    release.with_params title: "Yup", tag_name: "refs/tags/v9005"
    assert release.save!
    release.reload

    assert @writable_repo.tags.find("v9005")
    assert_equal "v9005", release.tag_name
  end

  test "has a permalink" do
    assert_match "/#{@repo.name_with_owner}/releases/tag/v1", @release.permalink
  end

  test "has a correctly URL-encoded permalink" do
    release = create :release, name: "#tag", tag_name: "#tag", author: @user, repository: @from_tags_repo
    assert_match "/#{@from_tags_repo.name_with_owner}/releases/tag/%23tag", release.permalink
  end

  test "gracefully returns a nil permalink for an invalid release" do
    release_without_repo     = Release.new repository: nil, tag_name: "v1"
    release_without_tag_name = Release.new repository: @repo, tag_name: nil

    assert_nil release_without_repo.permalink
    assert_nil release_without_tag_name.permalink
  end

  test "marks published release as draft when tag is deleted" do
    assert @release.published?
    assert @release.tag

    trigger_push_event(
      @repo.shard_path,
      @user.login,
      [["refs/tags/v1", "c1800491d95c42b4e96fb83f31fe8d9230c62907", GitHub::NULL_OID]],
      Time.now,
      perform_hydro_push_jobs: [HydroReleasesOnPushJob]
    )

    rel = Release.find @release.id
    assert rel.untagged_name?
    assert rel.draft?
  end

  test "updates Release#created_at when tag is created" do
    # Rails may detect fields with Unicode characters as having changed even if they didn't, which causes
    # the `release.save` call in HydroReleasesOnPushJob to fire `release.update[_webhook]` events even if nothing changed.
    # This tests that logic by putting Unicode characters in both the body and name and ensuring that no
    # `release.update` or `release.update_webhook` event fires as a result of HydroReleasesOnPushJob running (in addition to
    # ensuring that the `created_at` field is updated correctly).
    @release.update!(body: "🦦 unicode body", name: "🚀 unicode name", tag_name: "🚀-unicode-tag")
    Release.update_all created_at: Time.new(2000, 2, 1)
    assert_equal 2000, @release.reload.created_at.year

    webhook_update_events = subscribe "release.update_webhook"
    update_events = subscribe "release.update"

    trigger_push_event(
      @repo.shard_path,
      @user.login,
      [["refs/tags/🚀-unicode-tag", GitHub::NULL_OID, "c1800491d95c42b4e96fb83f31fe8d9230c62907"]],
      Time.now,
      perform_hydro_push_jobs: [HydroReleasesOnPushJob]
    )

    tag = @repo.tags.find("🚀-unicode-tag").target
    refute_equal 2000, tag.date.year
    assert_equal tag.date.year, @release.reload.created_at.year
    assert webhook_update_events.empty?
    assert update_events.empty?
  end

  context "potential_github_action?" do
    context "new_action_at_root ff off" do
      test "returns true if repo has an Action in the root" do
        disable_feature_flag(:new_action_at_root)
        ["action.yml", "action.yaml"].each do |path|
          action = create(:repository_action, path: path)

          release = build(:release, repository: action.repository)

          assert_predicate release, :potential_github_action?
        end
      end

      test "returns false if Action not in root" do
        disable_feature_flag(:new_action_at_root)
        ["action.yml", "action.yaml"].each do |path|
          action = create(:repository_action, path: "some/sub/dir/#{path}")

          release = build(:release, repository: action.repository)

          refute_predicate release, :potential_github_action?
        end
      end

      test "returns false if repo is private" do
        disable_feature_flag(:new_action_at_root)
        ["action.yml", "action.yaml"].each do |path|
          repo = create(:private_repository)
          action = create(:repository_action, path: path, repository: repo)

          release = build(:release, repository: action.repository)

          refute_predicate release, :potential_github_action?
        end
      end

      test "returns false if repo has no Actions" do
        disable_feature_flag(:new_action_at_root)
        repo = create(:repository)

        release = build(:release, repository: repo)

        refute_predicate release, :potential_github_action?
      end
    end
    context "new_action_at_root ff on" do
      test "returns true if repo has an Action in the root" do
        repo = create(:repository, from_example: :javascript_action)
        enable_feature_flag(:new_action_at_root, repo)
        ["action.yml", "action.yaml"].each do |path|
          action = create(:repository_action, path: path, repository: repo)
          update_action_yml_file(user: repo.owner, repo: repo, path: path)

          release = build(:release, repository: repo)

          assert_predicate release, :potential_github_action?
        end
      end

      test "returns false if Action not in root" do
        repo = create(:repository, from_example: :javascript_action)
        enable_feature_flag(:new_action_at_root, repo)
        ["action.yml", "action.yaml"].each do |path|
          subdir_path = "some/sub/dir/#{path}"
          action = create(:repository_action, path: subdir_path)
          update_action_yml_file(user: repo.owner, repo: repo, path: subdir_path)

          release = build(:release, repository: repo)

          refute_predicate release, :potential_github_action?
        end
      end

      test "returns false if repo is private" do
        repo = create(:private_repository, from_example: :javascript_action)
        enable_feature_flag(:new_action_at_root, repo)
        ["action.yml", "action.yaml"].each do |path|
          action = create(:repository_action, path: path, repository: repo)

          release = build(:release, repository: repo)

          refute_predicate release, :potential_github_action?
        end
      end

    end

  end

  context "events" do
    test "creates an event when creating a published release" do
      perform_enqueued_jobs(only: [ProcessEventJob]) do
        release = create :release, name: "v2", tag_name: "v2",
          author: @user, repository: @release_events_repo,
          state: :published
        refute_nil release.published_at
      end
      assert_equal "ReleaseEvent", GitHub.stratocaster_store.last.event_type
    end

    test "instruments a release.published event when creating a published release with an actor" do
      actor = create(:user)
      events = subscribe "release.published"
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published, actor: actor

      refute_nil release.published_at
      assert event = events.pop, "release.published event expected"
      assert_equal expected_webhook_payload(release, actor: actor), event.payload
    end

    test "instruments a release.published hydro event" do
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published, actor: @user, body: "# Hello, world"

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(release.author),
        repository: Hydro::EntitySerializer.repository(release.repository),
        repository_owner: Hydro::EntitySerializer.user(release.repository.owner),
        release: Hydro::EntitySerializer.release(release),
        body: release.body,
        short_description_html: "#{release.short_description_html}"
      }
      assert_hydro_published_partial(message, schema: "github.v1.ReleasePublish")
    end

    test "instruments a release.published event when creating a published release without an actor" do
      GitHub.context.push(actor_id: @user.id)
      events = subscribe "release.published"
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published

      refute_nil release.published_at
      assert event = events.pop, "release.published event expected"
      assert_equal expected_webhook_payload(release), event.payload
    end

    test "instruments a release.create event when creating a release without an actor" do
      audit_log_events = subscribe "release.create"
      webhook_events = subscribe "release.create_webhook"

      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :draft

      assert_equal 1, audit_log_events.length
      assert_equal 1, webhook_events.length

      assert audit_log_event = audit_log_events.pop, "release.create event expected"
      assert_equal expected_audit_log_payload(release), audit_log_event.payload

      assert webhook_event = webhook_events.pop, "release.create_webhook event expected"
      assert_equal expected_webhook_payload(release), webhook_event.payload
    end

    test "instruments a release.create event when creating a release with an actor" do
      GitHub.context.push(actor_id: @user.id)

      audit_log_events = subscribe "release.create"
      webhook_events = subscribe "release.create_webhook"

      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :draft

      assert_equal 1, audit_log_events.length
      assert_equal 1, webhook_events.length

      assert audit_log_event = audit_log_events.pop, "release.create event expected"
      assert_equal expected_audit_log_payload(release), audit_log_event.payload

      assert webhook_event = webhook_events.pop, "release.create_webhook event expected"
      assert_equal expected_webhook_payload(release), webhook_event.payload
    end

    test "instruments a release.destroy event when destroying a release" do
      GitHub.context.push(actor_id: @user.id)
      events = subscribe "release.destroy"

      # previous target_commitish logic attempted to write the value if it was nil, but destroyed
      # objects are frozen. target_commitish is used in event_payload, so instrumenting release.destroy
      # was throwing an error. leave target_commitish: nil here to test this.
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published, target_commitish: nil

      assert_equal 1, @release_events_repo.releases.count

      release.destroy

      assert_equal 0, @release_events_repo.releases.count
      assert event = events.pop, "release.destroy event expected"
      assert_equal expected_audit_log_payload(release), event.payload
    end

    test "instruments release.update and release.update_webhook events when updating a release" do
      GitHub.context.push(actor_id: @user.id)
      webhook_update_events = subscribe "release.update_webhook"
      update_events = subscribe "release.update"

      release = create :release, name: "My v2 Name", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :draft, prerelease: true

      release.with_params(
        name: "A v2.1 Name",
        draft: false,
        prerelease: false,
        target_commitish: "asdf",
        make_latest: true
      )

      assert release.save!

      assert_equal 1, webhook_update_events.length
      assert_equal 1, update_events.length

      assert webhook_update_event = webhook_update_events.pop, "release.update_webhook event expected"
      assert update_event = update_events.pop, "release.update event expected"

      expected_webhook_payload_full = expected_webhook_payload(release).merge({
        changes: {
          old_name: "My v2 Name",
        }
      })

      expected_audit_log_payload_full = expected_audit_log_payload(release).merge({
        changes: {
          old_name: "My v2 Name",
          old_state: "draft",
          old_prerelease: true,
          old_target_commitish: "master",
          make_latest: true,
        }
      })

      assert_equal expected_webhook_payload_full, webhook_update_event.payload
      assert_equal expected_audit_log_payload_full, update_event.payload
    end

    test "instruments release.update and release.update_webhook properly when tag_name updated" do
      GitHub.context.push(actor_id: @user.id)
      webhook_update_events = subscribe "release.update_webhook"
      update_events = subscribe "release.update"

      release = create :release, name: "My Draft", tag_name: "draft",
        author: @user, repository: @release_events_repo,
        state: :draft

      # need to test updating tag_name in a draft, when going from draft to published, and when published
      release.with_params(tag_name: "draft-new")
      assert release.save!

      assert event = update_events.pop, "release.update event expected when updating draft"
      assert_equal expected_audit_log_payload(release).merge({ changes: { old_tag_name: "draft" } }), event.payload
      assert webhook_event = webhook_update_events.pop, "release.update_webhook event expected when updating draft"
      assert_equal expected_webhook_payload(release).merge({ changes: { old_tag_name: "draft" } }), webhook_event.payload

      release.with_params(tag_name: "i-am-published", draft: false)
      assert release.save!

      assert event = update_events.pop, "release.update event expected when publishing release"
      assert_equal expected_audit_log_payload(release).merge({ changes: { old_tag_name: "draft-new", old_state: "draft" } }), event.payload
      assert webhook_event = webhook_update_events.pop, "release.update_webhook event expected when publishing release"
      assert_equal expected_webhook_payload(release).merge({ changes: { old_tag_name: "draft-new" } }), webhook_event.payload

      release.with_params(tag_name: "still-published")
      assert release.save!

      assert event = update_events.pop, "release.update event expected when updating published release"
      assert_equal expected_audit_log_payload(release).merge({ changes: { old_tag_name: "i-am-published" } }), event.payload
      assert webhook_event = webhook_update_events.pop, "release.update_webhook event expected when updating published release"
      assert_equal expected_webhook_payload(release).merge({ changes: { old_tag_name: "i-am-published" } }), webhook_event.payload

      release.with_params(tag_name: "back-to-draft", draft: true)
      assert release.save!

      assert event = update_events.pop, "release.update event expected when reverting to draft"
      assert_equal expected_audit_log_payload(release).merge({ changes: { old_tag_name: "still-published", old_state: "published" } }), event.payload
      assert webhook_event = webhook_update_events.pop, "release.update_webhook event expected when reverting to draft"
      assert_equal expected_webhook_payload(release).merge({ changes: { old_tag_name: "still-published" } }), webhook_event.payload

      # all events were popped, so ensure none are left
      assert_equal 0, update_events.length
      assert_equal 0, webhook_update_events.length
    end

    test "instruments old_tag_name properly in release.update when unchanged" do
      GitHub.context.push(actor_id: @user.id)
      update_events = subscribe "release.update"

      release = create :release, name: "My Draft", tag_name: "draft",
        author: @user, repository: @release_events_repo,
        state: :draft

      release.with_params(draft: false)
      assert release.save!

      assert event = update_events.pop, "release.update event expected when publishing"
      assert_equal expected_audit_log_payload(release).merge({ changes: { old_state: "draft" } }), event.payload

      release.with_params(draft: true)
      assert release.save!

      assert event = update_events.pop, "release.update event expected when reverting to draft"
      assert_equal expected_audit_log_payload(release).merge({ changes: { old_state: "published" } }), event.payload

      assert_equal 0, update_events.length
    end

    test "instruments body_changed/old_body properly in release.update and release.update_webhook" do
      GitHub.context.push(actor_id: @user.id)
      webhook_update_events = subscribe "release.update_webhook"
      update_events = subscribe "release.update"

      release = create :release, name: "My Release", tag_name: "v1",
        author: @user, repository: @release_events_repo, target_commitish: @release_events_repo.default_branch,
        state: :published, body: "👍 some body"

      release.with_params(body: "👍 some body 👍")
      assert release.save!

      assert webhook_event = webhook_update_events.pop, "release.update_webhook event expected"
      assert event = update_events.pop, "release.update event expected"

      assert_equal expected_webhook_payload(release).merge({ changes: { old_body: "👍 some body" } }), webhook_event.payload
      assert_equal expected_audit_log_payload(release).merge({ changes: { body_changed: true } }), event.payload

      assert_equal 0, webhook_update_events.length
      assert_equal 0, update_events.length
    end

    test "instruments tag_name changed in release.update and release.update_webhook" do
      GitHub.context.push(actor_id: @user.id)
      webhook_update_events = subscribe "release.update_webhook"
      update_events = subscribe "release.update"

      release = create :release, name: "v1", tag_name: "v1",
        author: @user, repository: @release_events_repo, target_commitish: @release_events_repo.default_branch,
        state: :published, body: "somebody once told me"

      release.with_params(tag_name: "v2")
      assert release.save!

      assert webhook_event = webhook_update_events.pop, "release.update_webhook event expected"
      assert event = update_events.pop, "release.update event expected"

      assert_equal expected_webhook_payload(release).merge({ changes: { old_tag_name: "v1" } }), webhook_event.payload

      assert_equal 0, webhook_update_events.length
      assert_equal 0, update_events.length
    end

    test "instruments name changed in release.update and release.update_webhook" do
      GitHub.context.push(actor_id: @user.id)
      webhook_update_events = subscribe "release.update_webhook"
      update_events = subscribe "release.update"

      release = create :release, name: "v1", tag_name: "v1",
        author: @user, repository: @release_events_repo, target_commitish: @release_events_repo.default_branch,
        state: :published, body: "somebody once told me"

      release.with_params(name: "v2")
      assert release.save!

      assert webhook_event = webhook_update_events.pop, "release.update_webhook event expected"
      assert event = update_events.pop, "release.update event expected"

      assert_equal expected_webhook_payload(release).merge({ changes: { old_name: "v1" } }), webhook_event.payload

      assert_equal 0, webhook_update_events.length
      assert_equal 0, update_events.length
    end

    test "does not create a GitHub Feed event when updating a published release" do
      release = nil
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published
      refute_nil release.published_at

      GitHub.stratocaster_store.reset!

      release.name = "v2.1"
      release.save!

      assert_nil GitHub.stratocaster_store.last
    end

    test "does not instrument a release.published event when updating a published release" do
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published
      refute_nil release.published_at

      events = subscribe "release.published"

      release.name = "v2.1"
      release.save!

      assert_nil events.pop, "an event was not expected"
    end

    test "does not instrument a release.first_published event when updating a published release" do
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published
      refute_nil release.published_at

      events = subscribe "release.first_published"

      release.name = "v2.1"
      release.save!

      assert_nil events.pop, "an event was not expected"
    end

    test "does not create an event when creating a draft release" do
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :draft
      assert_nil release.published_at
      assert_nil GitHub.stratocaster_store.last
    end

    test "does not instrument a release.published event when creating a draft release" do
      events = subscribe "release.published"

      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :draft
      assert_nil release.published_at

      assert_nil events.pop, "an event was not expected"
    end

    test "does not instrument a release.first_published event when creating a draft release" do
      GlobalInstrumenter.expects(:instrument).with("release.first_published", anything).never

      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :draft
      assert_nil release.published_at
    end

    test "creates an event when changing a release from draft to published" do
      GlobalInstrumenter.expects(:instrument).with("release.published", anything).once
      GlobalInstrumenter.expects(:instrument).with("release.first_published", anything).once

      release = nil

      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :draft
      assert_nil release.published_at
      assert_nil release.get_notification_summary.value
      assert_nil GitHub.stratocaster_store.last

      only = [Newsies::DeliverNotificationsJob, ProcessEventJob]
      perform_enqueued_jobs(only: only) do
        release.update!(draft: false)
        refute_nil release.published_at
        assert rollup = release.get_notification_summary.value
        assert_equal release.display_name, rollup.title
      end
      assert_equal "ReleaseEvent", GitHub.stratocaster_store.last.event_type
    end

    test "instruments a release.published and release.first_published event when changing a release from draft to published for the first time" do
      GlobalInstrumenter.expects(:instrument).with("release.published", anything).once
      GlobalInstrumenter.expects(:instrument).with("release.first_published", anything).once

      GitHub.context.push(actor_id: @user.id)
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :draft

      assert_nil release.published_at
      assert_nil release.get_notification_summary.value

      events = subscribe "release.published"

      release.update!(draft: false)
      refute_nil release.published_at

      assert event = events.pop, "an event was expected"
      assert_equal expected_webhook_payload(release), event.payload
    end

    test "instruments a release.published but not release.first_published event when changing a release from draft to published for the second time" do
      GlobalInstrumenter.expects(:instrument).with("release.published", anything).twice
      GlobalInstrumenter.expects(:instrument).with("release.first_published", anything).once

      GitHub.context.push(actor_id: @user.id)
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published

      refute_nil release.published_at

      events = subscribe "release.published"

      release.update!(draft: true)
      refute release.published?
      refute_nil release.published_at

      release.update!(draft: false)
      assert release.published?
      refute_nil release.published_at

      assert event = events.pop, "an event was expected"
      assert_equal expected_webhook_payload(release), event.payload
    end

    test "instruments a release.published event when changing a release from draft to published without an actor" do
      GitHub.context.push(actor_id: @user.id)
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :draft

      assert_nil release.published_at
      assert_nil release.get_notification_summary.value

      events = subscribe "release.published"

      release.update!(draft: false)
      refute_nil release.published_at

      assert event = events.pop, "an event was expected"
      assert_equal expected_webhook_payload(release), event.payload
    end

    test "does not instrument a release.published or release.first_published event when importing a release" do
      GlobalInstrumenter.expects(:instrument).with("release.published", anything).never
      GlobalInstrumenter.expects(:instrument).with("release.first_published", anything).never

      release = create :importable_release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published
      refute_nil release.published_at
    end

    test "instruments a release.unpublish event when changing a release from published to draft" do
      GitHub.context.push(actor_id: @user.id)
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published

      events = subscribe "release.unpublish"
      release.update!(draft: true)

      assert_equal expected_webhook_payload(release), events.first.payload
    end

    test "instruments a release.prerelease event when changing a release from not prereleased to prereleased" do
      GitHub.context.push(actor_id: @user.id)
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo, state: :published,
        prerelease: false, actor: @user

      events = subscribe "release.prerelease"
      assert_empty events

      release.update!(prerelease: true)
      assert_equal expected_webhook_payload(release), events.first.payload
    end

    test "instruments a release.prerelease event when creating a new release and marked as prereleased" do
      events = subscribe "release.prerelease"
      assert_empty events

      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo, state: :published,
        prerelease: true, actor: @user

      assert_equal expected_webhook_payload(release), events.first.payload
    end

    test "does not create a stratocaster event when changing a release from published to draft" do
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published
      refute_nil release.published_at

      release.update!(draft: true)
      refute release.published?
      assert_nil GitHub.stratocaster_store.last
    end

    test "does not instrument a release.published event when changing a release from published to draft" do
      release = create :release, name: "v2", tag_name: "v2",
        author: @user, repository: @release_events_repo,
        state: :published
      refute_nil release.published_at

      events = subscribe "release.published"

      release.update!(draft: true)
      refute release.published?

      assert_nil events.pop, "an event was not expected"
    end

    test "truncates body html" do
      release = create :release, name: "test", tag_name: "test",
        author: @user, repository: @release_events_repo,
        state: :draft, actor: @user, body: "* I'm Bruce Wayne\n* I'm also Batman"

      release.save!
      release.reload

      expected = "<ul>\n<li>I'm Bruce W…</li>\n</ul>"
      assert_equal release.short_description_html(length: 15), expected
    end
  end

  context "validations" do
    test "does not allow a name longer than 1024 bytes" do
      rel = Release.new repository: @repo, tag_name: "v2", author: @user
      rel.name = "a" * 1025
      assert rel.invalid?
      assert_includes rel.errors.full_messages, "Name is too long (maximum is 256 characters)"

      rel.name = "this name is not too long"
      assert_valid rel
    end

    test "does not allow multiple releases for the same tag" do
      assert_difference "@repo.releases.count", 1 do
        @repo.releases.create name: "One point two!", tag_name: "v2", author: @user
        @repo.releases.create name: "One point twogain", tag_name: "v2", author: @user
      end
    end

    test "allows non tags for drafts" do
      assert_difference "@repo.releases.count" do
        @repo.releases.create name: "One point oh!", author: @user, state: :draft
      end
    end

    test "does not allow a published release without a real tag" do
      assert_no_difference "@repo.releases.count" do
        @repo.releases.create name: "One point oh!", author: @user
      end

      assert_difference "@repo.releases.count" do
        @repo.releases.create name: "One point oh!", author: @user, tag_name: "v2"
      end
    end

    test "allows a draft release with a default commitish on an empty repository" do
      rel = Release.new repository: @empty_repo, tag_name: "v1", author: @user
      rel.target_commitish = @empty_repo.default_branch
      rel.state = :draft
      assert rel.repository_never_pushed_to?
      assert_valid rel
    end

    test "allows a draft release with a non-default target_commitish on an empty repository" do
      rel = Release.new repository: @empty_repo, tag_name: "v1", author: @user
      rel.target_commitish = "booya"
      rel.state = :draft
      assert rel.repository_never_pushed_to?
      assert !rel.valid?
      assert rel.errors[:target_commitish]
    end

    test "rejects a published release on an empty repository" do
      rel = create :release, repository: @empty_repo, tag_name: "v1",
        author: @user, state: :draft
      rel.state = :published
      assert rel.repository_never_pushed_to?
      assert !rel.valid?
      assert rel.errors[:base]
      assert_match /is empty/i, rel.errors[:base].to_s
    end
  end

  context "#destroy" do
    test "deletes assets in background" do
      asset = ReleaseAsset.new uploader: @release.user, release: @release
      save_file_for_uploadable asset, name: "tater.jpg"

      assert_difference("ReleaseAsset.count", -1) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @release.destroy }
      end

      refute ReleaseAsset.exists?(asset.id)
    end
  end

  context "body_cache_key_prefix" do
    test "adds a releases-specific identifier" do
      cache_key_prefix = @release.body_cache_key_prefix(:test)
      assert cache_key_prefix.end_with?(":pipeline_v1")
    end
  end

  context "notifications" do
    test "notifications_author is the author" do
      assert_equal @release.author, @release.notifications_author
    end

    test "notifications_thread is itself" do
      assert_equal @release, @release.notifications_thread
    end

    test "notifications_list is the repository" do
      assert_equal @release.repository, @release.notifications_list
    end

    test "cleans up newsies data for thread when release is destroyed" do
      GitHub.newsies.expects(:async_delete_all_for_thread).with(@repo, @release)
      @release.destroy
    end
  end

  context "#async_readable_by?" do
    test "resolves to true for a user who can read the repository" do
      rando = create(:user)
      assert @repo.readable_by?(rando)
      assert @release.async_readable_by?(rando).sync
    end

    test "resolves to true for draft releases where the user can write to the repository" do
      @release.draft = false
      @release.save!

      assert @repo.readable_by?(@user)
      assert @release.async_readable_by?(@user).sync
    end

    test "resolves to false for draft releases where the user can not write to the repository" do
      rando = create(:user)
      @release.draft = true
      @release.save!

      assert @repo.readable_by?(rando)
      refute @release.async_readable_by?(rando).sync
    end

    test "resolves to false where a user cannot read the repository" do
      rando = create(:user)
      release = create(:release, tag_name: "v1", repository: @release_events_repo, author: @user)

      refute @release_events_repo.readable_by?(rando)
      refute release.async_readable_by?(rando).sync
    end
  end

  context "#readable_by?" do
    test "resolves to true for a user who can read the repository" do
      assert @repo.readable_by?(@user)
      assert @release.readable_by?(@user)
    end

    test "resolves to false where a user cannot read the repository" do
      rando = create(:user)
      release = create(:release, tag_name: "v1", repository: @release_events_repo, author: @user)

      refute @release_events_repo.readable_by?(rando)
      refute release.readable_by?(rando)
    end
  end

  context "#protected_tag_deletable_by?" do
    test "returns true if the tag is protected" do
      RepositoryTagProtectionState.allow_creation_for_tests do
        collaborator = create(:user)
        @repo.add_member(collaborator)
        RepositoryTagProtectionState.create!(repository: @repo, pattern: "v*", enabled: true)
        assert @release.protected_tag_deletable_by?(collaborator)
      end
    end
  end

  context ".protected_tags_deletable_by?" do
    test "returns the subset of releases that the user can delete" do
      RepositoryTagProtectionState.allow_creation_for_tests do
        RepositoryTagProtectionState.create(repository: @repo, pattern: "v1", enabled: true)
        unprotected_tag = build(:release, name: "Unprotected version", tag_name: "v2",
          author: @user, repository: @repo)

        collaborator = create(:user)
        @repo.add_member(collaborator)

        assert_same_elements [unprotected_tag, @release],
          Release.protected_tags_deletable_by?(collaborator, [@release, unprotected_tag])

        assert_same_elements [unprotected_tag, @release],
          Release.protected_tags_deletable_by?(@user, [@release, unprotected_tag])
      end
    end

    test "returns the subset of releases that the user can delete (rulesets with no bypass)" do
      ruleset = create(:repository_ruleset, :tag_ruleset, source: @repo)
      create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "deletion")
      create(:repository_rule_condition, :targets_tag, repository_ruleset: ruleset, tag_name: "refs/tags/v1")

      unprotected_tag = build(:release, name: "Unprotected version", tag_name: "v2",
        author: @user, repository: @repo)

      collaborator = create(:user)
      @repo.add_member(collaborator)

      assert_same_elements [unprotected_tag],
        Release.protected_tags_deletable_by?(collaborator, [@release, unprotected_tag])
      assert_same_elements [unprotected_tag],
        Release.protected_tags_deletable_by?(@user, [@release, unprotected_tag])
    end

    test "returns the subset of releases that the user can delete (rulesets with bypass)" do
      ruleset = create(:repository_ruleset, :tag_ruleset, source: @repo)
      create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "deletion")
      create(:repository_rule_condition, :targets_tag, repository_ruleset: ruleset, tag_name: "refs/tags/v1")
      create(:repository_ruleset_bypass_actor, :repo_admin, repository_ruleset: ruleset)

      unprotected_tag = build(:release, name: "Unprotected version", tag_name: "v2",
        author: @user, repository: @repo)

      collaborator = create(:user)
      @repo.add_member(collaborator)

      assert_same_elements [unprotected_tag],
        Release.protected_tags_deletable_by?(collaborator, [@release, unprotected_tag])
      assert_same_elements [unprotected_tag, @release],
        Release.protected_tags_deletable_by?(@user, [@release, unprotected_tag])
    end

    test "returns all releases when a ruleset applies but does not block deletion" do
      ruleset = create(:repository_ruleset, :tag_ruleset, source: @repo)
      create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "creation")
      create(:repository_rule_condition, :targets_tag, repository_ruleset: ruleset, tag_name: "refs/tags/v1")

      unprotected_tag = build(:release, name: "Unprotected version", tag_name: "v2",
        author: @user, repository: @repo)

      collaborator = create(:user)
      @repo.add_member(collaborator)

      assert_same_elements [unprotected_tag, @release],
        Release.protected_tags_deletable_by?(collaborator, [@release, unprotected_tag])
      assert_same_elements [unprotected_tag, @release],
        Release.protected_tags_deletable_by?(@user, [@release, unprotected_tag])
    end
  end

  context "#tag_protected?" do
    test "returns false" do
      RepositoryTagProtectionState.allow_creation_for_tests do
        RepositoryTagProtectionState.create(repository: @repo, pattern: "v*", enabled: true)

        refute @release.tag_protected?
      end
    end
  end

  context "#commits" do
    test "finds all commits for the first release" do
      repo = create(:repository, :full_creation)
      commit_metadata = { committer: repo.owner, message: "Adding some files", author: repo.owner }

      first_commit = repo.commits.create(commit_metadata, nil) { |files| files.add("a", "a") }
      main_ref = repo.refs.create("refs/heads/main", first_commit, repo.owner)

      commits = [first_commit] + 9.times.map do |idx|
        main_ref.append_commit(commit_metadata, repo.owner) { |files| files.add("a:#{idx}", "b:#{idx}") }
      end

      release = create(:release,
        name: "New release",
        tag_name: "v1",
        author: repo.owner,
        repository: repo,
        target_commitish: main_ref.name,
      )

      # 10 commits created _after_ the first release was created
      10.times do |idx|
        main_ref.append_commit(commit_metadata, repo.owner) { |files| files.add("a1:#{idx}", "b1:#{idx}") }
      end

      _second_release = create(:release,
        name: "New release",
        tag_name: "v2",
        author: repo.owner,
        repository: repo,
        target_commitish: main_ref.name,
      )

      assert_equal release.commits.count, commits.count
      commits.each do |commit|
        assert_includes release.commits, commit
      end
    end

    test "Returns an empty list when the release tag is nil" do
      commits = assert_nothing_raised { @abandoned_release.commits }
      assert_empty commits
    end

    test "finds commits between releases" do
      repo = create(:repository, :full_creation)
      commit_metadata = { committer: repo.owner, message: "this is commit", author: repo.owner }

      first_commit = repo.commits.create(commit_metadata, nil) { |files| files.add("a", "a") }
      main_ref = repo.refs.create("refs/heads/main", first_commit, repo.owner)

      _first_release = create(:release, name: "Version One!", tag_name: "v1", author: repo.owner, repository: repo, target_commitish: "main")

      second_commit = main_ref.append_commit({
        committer: repo.owner, message: "this is commit", author: repo.owner
      }, repo.owner) { |files| files.add("b", "b") }

      second_release = create(:release, name: "Version Two!", tag_name: "v2", author: repo.owner, repository: repo, target_commitish: "main")
      assert_equal [second_commit], second_release.commits
    end
  end

  context "mentions" do
    test "add mentions" do
      assert_equal 0, @release.mentions.count

      @release.mentions << @user2
      # no need to save here. It happens automatically when mentions are altered.
      # calling save would trigger the parsing/population logic and will override the mentions attribute.

      rel = T.must(Release.find_by(id: @release.id))
      assert_equal 1, rel.mentions.count
      assert_equal @user2, rel.mentions[0]

      @release.mentions = []
      @release.mentions << @user3
      @release.mentions << @committer

      rel = T.must(Release.find_by(id: @release.id))
      assert_equal 2, rel.mentions.count
      assert_same_elements [@user3, @committer], rel.mentions
    end
  end

  context "reactions" do
    test "Test release reaction operations" do
      # @release should have 1 heart reaction already
      assert_equal 1, @release.reactions.count, "Test setup should create 1 reaction"

      # create another reaction and confirm it gets added to our release
      r2 = Reaction.react user: @user,
        subject_id: @release.id,
        subject_type: @release.class.name,
        content: Emotion.find_by_label("+1").content
      assert_predicate r2, :valid?
      @release.reload
      assert_equal 2,  @release.reactions.count

      # confirm the reactions in our release are the ones we created
      r = @release.reactions.find(r2.id)
      assert r.content == r2.content
      assert r.user == r2.user

      # try to add the same reaction.  It should throw an exception
      assert_raises ActiveRecord::RecordNotUnique do
        create :reaction, subject: @release, content: "+1", user: @user
      end

      # delete the reaction
      Reaction.unreact(
        user: @user,
        subject_id: r2.subject_id,
        subject_type: r2.subject_type,
        content: r2.content)
      @release.reload
      assert_equal 1,  @release.reactions.count

      # try to access the record. should throw.
      assert_raises ActiveRecord::RecordNotFound do
        @release.reactions.find(r2.id)
      end

      # try to delete again. should throw
      assert_raises ActiveRecord::RecordNotFound do
        Reaction.destroy(r.id)
      end
    end

    test "releases do not allow negative reactions" do
      positive_only = ["+1", "eyes", "heart", "rocket", "smile", "tada"]
      assert_equal positive_only, @release.class.emotions.map(&:content).sort

      invalid_reaction = Reaction.react user: @user,
        subject_id: @release.id,
        subject_type: @release.class.name,
        content: Emotion.find_by_label("-1").content
      assert invalid_reaction.invalid?
      assert_includes invalid_reaction.errors.full_messages, "Content is not a valid emotion for this subject"
    end
  end

  context "search index" do
    test "is sync'd when a release is created" do
      Search.expects(:add_to_search_index).with("release", instance_of(Integer))

      create :release, tag_name: "v33", author: @user, repository: @repo
    end

    test "is sync'd when a release is updated" do
      Search.expects(:add_to_search_index).with("release", @release.id)

      @release.update! name: "new title"
    end

    test "is sync'd when a release is deleted" do
      release = create :release, repository: @repo

      assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["release", release.id] do
        release.destroy
      end
    end

    test "logs reason when not searchable" do
      release = create :release, repository: @repo
      release.repository = nil

      assert_equal false, release.is_searchable?(log_reason: true)
      assert_dogstats_increment 1, "release.is_searchable", tags: ["value:false", "reason:repository_nil"]
    end
  end

  test "is deleted with repository" do
    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [@release, @abandoned_release, @lambda_release]
      config.expect_not_destroyed = [@beta_prerelease]
    end
  end

  def with_indexed_releases(releases = [@release, @lambda_release, @beta_prerelease], &block)
    # Create releases in a random order to show that they get retrieved in sorted in tag order
    make_searchable *releases

    block.call
  end

  teardown do
    teardown_search
  end
end

class EmuReleasesTest < GitHub::TestCase
  include ReleasesSharedTests

  include GitHub::DatabaseQueryWarningsTestHelpers
  include HydroTestHelpers

  fixtures do
    @user = create :emu, :owner
    @business = @user.enterprise_managed_business

    @org = create(:organization, business: @business, admin: @user)
    @committer = create :emu, business: @business, email: "TECHNOWEENIE@gmail.com"

    @from_tags_repo = create :repository, owner: @user, from_example: :branch_and_tag_refs
  end

  setup do
    DGit.bless @from_tags_repo

    GitHub.stratocaster_store.reset!
  end
end unless GitHub.single_business_environment?
