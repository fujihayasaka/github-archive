# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class ModelsGistTest < GitHub::TestCase
  include GistTestHelper
  include HydroTestHelpers
  include StringFromBinaryTestHelper

  test "should be able to generate a new random git repo" do
    new_gist = GistHelpers.generate(user: @user, contents: gist_test_content_array, public: false)
    assert @gist.shard_path != new_gist.shard_path
  end

  context ".repo_exists?" do
    test "returns true if a gist with the given repo_name exists" do
      assert Gist.repo_exists?(@public_gist.repo_name)
    end

    test "returns false if a gist with the given repo_name does not exist" do
      refute Gist.repo_exists?("unknown_repo_name")
    end
  end

  test "should be able to generate a single file" do
    gist = GistHelpers.generate(user: @user, contents: gist_test_content_array, public: false)
    assert_equal "random content", gist.raw
  end

  test "should be able to read commit history" do
    gist = GistHelpers.generate(user: @user, contents: gist_test_content_array, public: false)
    assert_equal 1, gist.commits.history(gist.master_oid).size
  end

  test "updating the pushed_at timestamp without running callbacks" do
    Timecop.freeze("2016-07-01 00:00:00") do
      time = 20.days.ago
      @gist.update_pushed_at(time)
      assert_equal time.to_i, @gist.pushed_at.to_i
      assert_equal time.to_i, @gist.reload.pushed_at.to_i
      assert_equal time.to_i, @gist.updated_at.to_i
      assert_equal time.to_i, @gist.reload.updated_at.to_i

      # since this runs an update_all, make sure we dont accidentally update more
      # than intended.
      @public_gist.reload
      refute_equal time.to_i, @public_gist.pushed_at.to_i
      refute_equal time.to_i, @public_gist.updated_at.to_i
    end
  end

  context "#permalink" do

    test "sets permalink (and host) correctly" do
      permalink_uri = URI.parse @gist.permalink

      if GitHub.flipper[:gist_permalink_update].enabled?
        expected_path = "/#{@gist.name_with_owner}"
      else
        expected_path = "/#{@gist.to_param}"
      end

      assert_equal URI.parse(GitHub.gist_url).host, permalink_uri.host
      assert_includes permalink_uri.path, expected_path
    end
  end

  test "should determine its clone url" do
    assert_match /http/, @gist.clone_url
  end

  test "should determine its push url" do
    assert_match /http/, @gist.push_url
  end

  test "should know if its secret or not" do
    assert @gist.secret?
  end

  test "should set target_for_conditional_access correctly" do
    assert_equal @gist.owner,  @gist.target_for_conditional_access
    assert_equal :no_target_for_conditional_access, @anon_gist.target_for_conditional_access
  end

  test "should set async_target_for_conditional_access correctly" do
    assert_equal @gist.owner,  @gist.async_target_for_conditional_access.sync
    assert_equal :no_target_for_conditional_access, @anon_gist.async_target_for_conditional_access.sync
  end

  context "multiple_target_for_conditional_access" do
    test "computes TFCA for multiple gists" do
      result = Gist.multiple_target_for_conditional_access([@gist, @anon_gist, @public_gist, @secret_gist, @other_user_gist])
      expected = { @gist => @user, @anon_gist => :no_target_for_conditional_access, @public_gist => @user, @secret_gist => @user, @other_user_gist => @user2 }
      assert_equal expected, result
    end
  end

  if GitHub.email_verification_enabled?
    test "disallows create from user without a verified email" do
      unverified_user = create(:user)
      refute unverified_user.emails.verified.any?

      # Setup that ensures that a user is forced to verify their email
      # This is a distinct check from GitHub.email_verification_enabled?
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      unverified_user.require_email_verification!

      unverified_gist = Gist::Creator.new(user: unverified_user, contents: [{ name: "1", value: "blah" }])
      refute unverified_gist.create
      assert_includes unverified_gist.errors.full_messages.to_s, "User must have a verified email"
    end

    test "disallows fork from user without a verified email" do
      gist = Gist::Creator.create!(user: create(:verified_user), contents: [{ name: "1", value: "blah" }])
      unverified_user = create(:user)
      refute unverified_user.emails.verified.any?

      # Setup that ensures that a user is forced to verify their email
      # This is a distinct check from GitHub.email_verification_enabled?
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      unverified_user.require_email_verification!

      forked_gist = gist.fork(unverified_user)
      assert_includes forked_gist.errors.full_messages.to_s, "User must have a verified email"
    end
  else
    test "allows create from user without a verified email" do
      unverified_user = create(:user)
      refute unverified_user.emails.verified.any?

      # Setup that ensures that a user is forced to verify their email
      # This is a distinct check from GitHub.email_verification_enabled?
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      unverified_user.require_email_verification!

      unverified_gist = Gist::Creator.new(user: unverified_user, contents: [{ name: "1", value: "blah" }])
      assert unverified_gist.create
    end

    test "allows fork from user without a verified email" do
      gist = Gist::Creator.create!(user: create(:verified_user), contents: [{ name: "1", value: "blah" }])
      unverified_user = create(:user)
      refute unverified_user.emails.verified.any?

      # Setup that ensures that a user is forced to verify their email
      # This is a distinct check from GitHub.email_verification_enabled?
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      unverified_user.require_email_verification!

      forked_gist = gist.fork(unverified_user)
      assert forked_gist.valid?
    end
  end

  test "allows update from user without a verified email" do
    user = create(:verified_user)
    gist = Gist::Creator.create!(user: user, contents: [{ name: "1", value: "blah" }])
    user.emails.each(&:unverify!)

    # Setup that ensures that a user is forced to verify their email
    # This is a distinct check from GitHub.email_verification_enabled?
    GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
    user.require_email_verification!

    gist_oid = gist.files.first.oid
    assert gist.update!(contents: [{ name: "1", value: "an update", oid: gist_oid }])
  end

  test "allows delete from user without a verified email" do
    user = create(:verified_user)
    gist = Gist::Creator.create!(user: user, contents: [{ name: "1", value: "blah" }])
    user.emails.each(&:unverify!)

    # Setup that ensures that a user is forced to verify their email
    # This is a distinct check from GitHub.email_verification_enabled?
    GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
    user.require_email_verification!

    assert gist.destroy!
  end

  test "disallows blank content on create" do
    blank = Gist::Creator.new user: @user, contents: [], public: true
    refute blank.create, "errors expected, but none encountered"

    contents = [
      { name: "file1", value: "" },
      { name: "file2", value: "\n" },
    ]
    blank = Gist::Creator.new(user: @user, contents: contents, public: true)
    refute blank.create, "errors expected, but none encountered"
  end

  context "#assign_upload_container_id_to_user_assets" do
    skip_in_multitenant_mode

    test "backfills user assets upload_container_id on create" do
      assets = create_list(:user_asset, 2, uploader: @user, upload_container_type: Gist.name)
      contents = assets.map { |asset| { name: "file#{asset.id}.md", value: %Q(<img src="#{GitHub.gist_url}/assets/#{asset.user_id}/#{asset.guid}">) } }

      GitHub.stubs(:context).returns({ actor_id: @user.id })

      gist = GistHelpers.generate(contents: contents, user: @user, public: false)

      assets.each do |asset|
        asset.reload
        assert_equal gist.id, asset.upload_container_id
      end
    end

    test "doesn't backfill user assets upload_container_id on create if actor is not the user_asset's owner" do
      random_user = create(:user)
      assets = create_list(:user_asset, 2, uploader: @user, upload_container_type: Gist.name)
      contents = assets.map { |asset| { name: "file#{asset.id}.md", value: %Q(<img src="#{GitHub.gist_url}/assets/#{asset.user_id}/#{asset.guid}">) } }

      GitHub.stubs(:context).returns({ actor_id: random_user.id })

      gist = GistHelpers.generate(contents: contents, user: random_user, public: false)

      assets.each do |asset|
        asset.reload
        assert_nil asset.upload_container_id
      end
    end
  end

  context "#private_asset_url" do
    skip_in_multitenant_mode

    test "generates new-style url if use_new_url is true" do
      gist = Gist::Creator.create!(user: @user, contents: [{ name: "1", value: "blah" }])
      assert_equal "#{GitHub.gist_url}/user-attachments/assets/fake-guid", gist.private_asset_url(@user.id, "fake-guid", true)
    end

    test "generates old-style url if use_new_url is false" do
      gist = Gist::Creator.create!(user: @user, contents: [{ name: "1", value: "blah" }])
      assert_equal "#{GitHub.gist_url}/assets/#{@user.id}/fake-guid", gist.private_asset_url(@user.id, "fake-guid", false)
    end
  end

  test "update with blank content zeroes file" do
    contents = [
      { name: "file1", value: "text" },
      { name: "file2", value: "another" },
    ]
    gist = GistHelpers.generate(user: @user, contents: contents)

    contents = {}
    gist.files.each do |file|
      contents[file.name] = { name: file.name, value: file.data, oid: file.oid }
    end
    assert gist.update!(contents: [{ name: "file1", value: "", oid: contents["file1"][:oid] }])
    assert_equal %w[ file1 file2 ], gist.files.map(&:name)
    file1 = gist.files.detect { |f| f.name == "file1" }
    assert_equal "", file1.data
  end

  test "update with delete flag deletes file" do
    contents = [
      { name: "file1", value: "text" },
      { name: "file2", value: "another" },
    ]
    gist = GistHelpers.generate(user: @user, contents: contents)

    contents = {}
    gist.files.each do |file|
      contents[file.name] = { name: file.name, value: file.data, oid: file.oid }
    end
    assert gist.update!(contents: [{ name: "file1", value: "", oid: contents["file1"][:oid], delete: true }])
    assert_equal %w[ file2 ], gist.files.map(&:name)
  end

  test "renames a file" do
    gist = GistHelpers.generate(user: @user, contents: [{ name: "file1", value: "text" }])

    contents = {}
    gist.files.each do |file|
      contents[file.name] = { name: file.name, value: file.data, oid: file.oid }
    end
    contents["file1"][:name] = "file2"

    assert gist.update!(contents: contents.values)
    assert_equal %w[ file2 ], gist.files.map(&:name)
    assert_equal "text", gist.files[0].data
  end

  test "changes file type" do
    gist = GistHelpers.generate(user: @user, contents: [{ name: "gistfile1.txt", value: "text" }])
    gist_file = gist.files.first
    contents = [
      { name: "gistfile1.rb", value: "text", oid: gist_file.oid },
    ]
    assert gist.update!(contents: contents)
    assert_equal %w[ gistfile1.rb ], gist.files.map(&:name)
    assert_equal "text", gist.files[0].data
  end

  test "refuses an update with a path-traversing name in a .gitmodules file" do
    gitmodules_content = <<-GITMODULES
      [submodule "../../something/evil.git"]
        path = totally-innocent
        url = foo
    GITMODULES
    contents = [{ name: ".gitmodules", value: gitmodules_content }]

    gist = GistHelpers.generate(user: @user, contents: [{ name: "gistfile1.txt", value: "text" }])
    assert_raises(GitRPC::BadGitmodules) do
      gist.update!(contents: contents)
    end
  end

  test "refuses an update with an option-injecting url in a .gitmodules file" do
    gitmodules_content = <<-GITMODULES
      [submodule "evil"]
        path = totally-innocent
        url = -u./payload
    GITMODULES
    contents = [{ name: ".gitmodules", value: gitmodules_content }]

    gist = GistHelpers.generate(user: @user, contents: [{ name: "gistfile1.txt", value: "text" }])
    assert_raises(GitRPC::BadGitmodules) do
      gist.update_attribute(:contents, contents)
    end
  end

  test "refuses an update with an option-injecting path in a .gitmodules file" do
    gitmodules_content = <<-GITMODULES
      [submodule "evil"]
        path = -what
        url = https://example.com/innocent.git
    GITMODULES
    contents = [{ name: ".gitmodules", value: gitmodules_content }]

    gist = GistHelpers.generate(user: @user, contents: [{ name: "gistfile1.txt", value: "text" }])
    assert_raises(GitRPC::BadGitmodules) do
      gist.update_attribute(:contents, contents)
    end
  end

  test "should be able to generate a random handle" do
    sha1 = Gist.random_sha
    sha2 = Gist.random_sha
    assert sha1 != sha2
    assert_equal 32, sha1.size
  end

  test "refuses an update with a url injecting data into the credential helper in a .gitmodules file" do
    gitmodules_content = <<-GITMODULES
      [submodule "evil"]
        path = totally-innocent
        url = https://example.com/evil?%0ahost=github.com
    GITMODULES
    contents = [{ name: ".gitmodules", value: gitmodules_content }]

    gist = GistHelpers.generate(user: @user, contents: [{ name: "gistfile1.txt", value: "text" }])
    assert_raises(GitRPC::BadGitmodules) do
      gist.update_attribute(:contents, contents)
    end
  end

  context "Gist.generate_unique_repo_name" do
    test "doesn't reassign taken repo names" do
      taken = @gist.repo_name
      untaken = Gist.random_sha

      Gist.stubs(:random_sha).returns(taken).then.returns(untaken)

      assert_equal untaken, Gist.generate_unique_repo_name
    end

    test "doesn't reassign taken archived repo names" do
      @deleted_gist.remove(async: false)
      refute Gist.active.exists?(id: @deleted_gist.id)

      taken = @deleted_gist.repo_name
      untaken = Gist.random_sha

      Gist.stubs(:random_sha).returns(taken).then.returns(untaken)

      assert_equal untaken, Gist.generate_unique_repo_name
    end
  end

  test "forking by owner does nothing" do
    assert_equal @public_gist.owner, @user
    fork = @public_gist.fork(@user)
    assert_equal @public_gist, fork
  end

  test "forking when already forked returns the existing fork" do
    assert_equal @public_gist.owner, @user
    fork = @public_gist.fork(@user2)
    attempted_refork = @public_gist.fork(@user2)
    assert_equal fork, attempted_refork
  end

  test "fork inherits parent description" do
    fork = @public_gist.fork(@user2)
    assert !fork.new_record?
    assert fork.public?
    refute_equal fork, @public_gist
    assert_equal "my gist", fork.description
  end

  test "forker can update forked gist when default_new_repo_branch differs from parent gist default_branch" do
    @user2.set_default_new_repo_branch("differentfromparentgist", actor: @user2)
    fork = @public_gist.fork(@user2)
    fork.update_attribute(:contents, [{ name: "1", value: "other random content" }])
    assert_equal fork.files.first.data, "other random content"
  end

  test "forking bumps original timestamp" do
    timestamp = @public_gist.updated_at
    forked_gist = nil

    Timecop.freeze(1.day.from_now) do
      forked_gist = @public_gist.fork(@user2)
    end
    refute_equal forked_gist, @public_gist
    refute_equal timestamp, @public_gist.reload.updated_at
  end

  test "fork inherits parent pushed_at" do
    @public_gist.update_attribute :pushed_at, 1.day.ago
    @public_gist.reload
    fork = @public_gist.fork(@user)
    assert_equal @public_gist.pushed_at, fork.pushed_at
  end

  test "should be able to fork private gists" do
    fork = @gist.fork(@user)
    assert fork.private?
    refute_nil @gist.repo_name
  end

  test "knows what files it contains" do
    gist = Gist::Creator.create!({
      user: @user,
      contents: [
        { name: "blah.rb", value: "blah" },
        { name: "README", value: "please" },
      ],
      public: true,
    })

    expected = %w[ README blah.rb ]
    assert_equal expected, gist.files.map(&:name)
  end

  test "disallows subdirectories" do
    gist = Gist::Creator.new({
      user: @user,
      contents: [
        { name: "some/file.rb", value: "hooray" },
      ],
      public: true,
    })
    refute gist.create
  end

  test "bumps updated_at on Gist update" do
    timestamp = @public_gist.updated_at

    # Ensure we update at a new time in the future
    Timecop.travel(5.minutes.from_now) do
      @public_gist.update_attribute(:contents, gist_test_content_array)
    end

    refute_equal timestamp, @public_gist.updated_at
  end

  test "bumps pushed_at on Gist update" do
    @public_gist.update_attribute :pushed_at, 1.day.ago

    gist = Gist.find(@public_gist.id)
    timestamp = gist.pushed_at
    gist.update_attribute(:contents, gist_test_content_array)
    refute_equal timestamp, gist.pushed_at
  end

  test "gist with multiple revisions without commit messages has a proper SHA" do
    file = { name: "1", value: "initial version" }
    gist = GistHelpers.generate(contents: [file], user: @user)

    file[:value] = "a new version"
    gist.update!(contents: [file])

    file[:value] = "the final version"
    gist.update!(contents: [file])

    assert_equal 40, gist.sha.size
  end

  context ".with_path" do
    test "finds an existing gist by full shard path" do
      assert_equal @gist, Gist.with_path(@gist.shard_path)
    end
  end

  context ".with_name_with_owner" do
    test "returns nil for archived gists" do
      @gist.remove(async: false)
      nwo = "#{@user}/#{@gist}"
      assert_nil Gist.with_name_with_owner(nwo)
    end

    test "returns nil for archived anon gists" do
      @anon_gist.remove(async: false)
      nwo = "anonymous/#{@gist}"
      assert_nil Gist.with_name_with_owner(nwo)
    end

    test "finds an existing owned gist" do
      nwo = "#{@user}/#{@gist}"
      assert_equal @gist, Gist.with_name_with_owner(nwo)
    end

    test "finds an existing anon gist" do
      nwo = "anonymous/#{@anon_gist}"
      assert_equal @anon_gist, Gist.with_name_with_owner(nwo)
    end

    test "returns nil for non-existing owners even if gist exists" do
      nwo = "bad-user/#{@gist}"
      assert_nil Gist.with_name_with_owner(nwo)
    end

    test "returns nil for non-existent gists" do
      nwo = "#{@user}/xxxxxxxxxxxxxxxxxxxx"
      assert_nil Gist.with_name_with_owner(nwo)

      nwo = "anonymous/xxxxxxxxxxxxxxxxxxxx"
      assert_nil Gist.with_name_with_owner(nwo)
    end
  end

  context ".modified" do
    test "it only includes modified gists" do
      included = create :gist,
        created_at: Time.new(2016, 1, 1),
        updated_at: Time.new(2016, 1, 1) + 61.seconds
      excluded = create :gist,
        created_at: Time.new(2016, 1, 1),
        updated_at: Time.new(2016, 1, 1)

      assert_includes Gist.modified, included
      refute_includes Gist.modified, excluded
    end

    test "it excludes gists which were modified in close proximity to creation" do
      included = create :gist,
        created_at: Time.new(2016, 1, 1),
        updated_at: Time.new(2016, 1, 1) + 59.seconds

      refute_includes Gist.modified, included
    end
  end

  context "#empty?" do
    test "is true for new gists" do
      assert Gist.new.empty?
    end

    test "is false for gists committed to disk" do
      refute @public_gist.empty?
    end

    test "is false for anon gists committed to disk" do
      refute @anon_gist.empty?
    end

    test "is true if the gist has never been pushed to and it is not a fork" do
      @public_gist.stubs(:pushed_at).returns(nil)

      assert @public_gist.empty?
    end

    test "is false if the gist has never been pushed to but it is a fork" do
      forked = @public_gist.fork(@user2)

      refute forked.empty?
    end

    test "is true if the gist doesn't have any refs" do
      @public_gist.stubs(:refs).returns([])

      assert @public_gist.empty?
    end
  end

  test "inits repo with daemon serving" do
    # create a new gist so we don't affect @public_gist's git repo
    gist = Gist::Creator.create! contents: gist_test_content_array, user: @user, public: true
    assert_repo_exists gist
  end

  test "inits repo without daemon serving" do
    # create a new gist so we don't affect @public_gist's git repo
    gist = Gist::Creator.create! contents: gist_test_content_array, user: @user, public: false
    assert_repo_exists gist
  end

  test "sets pushed_at" do
    refute_nil @gist.pushed_at
  end

  test "forks repo" do
    fork = Gist::Creator.create! user: @user, parent: @public_gist

    assert_equal @public_gist.revision_list(@public_gist.master_oid),
      fork.revision_list(fork.master_oid)
    assert_repo_exists   fork
  end

  test "rate limited per user when rate-limiting is enabled" do
    enable_content_creation_rate_limiting
    user = create(:user)
    expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]
    limit = 2

    with_cache_enabled do
      Timecop.freeze do
        GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
          limit.times do
            gist = Gist::Creator.create! contents: gist_test_content_array,
              user: user, public: true
          end

          gist = Gist::Creator.new contents: gist_test_content_array,
            user: user, public: true


          refute gist.create
          assert_equal expected_errors, gist.errors.full_messages
        end
      end
    end
  end

  test "there isn't a rate limit error when rate-limiting is disabled" do
    GitHub.stubs(:content_creation_rate_limiting_enabled?).returns(false)
    user = create(:user)
    limit = 2

    with_cache_enabled do
      Timecop.freeze do
        GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
          limit.times do
            gist = Gist::Creator.create! contents: gist_test_content_array,
              user: user, public: true
          end

          gist = Gist::Creator.new contents: gist_test_content_array,
            user: user, public: true


          assert gist.create
          assert_nil gist.errors
        end
      end
    end
  end

  test "instruments gist.create" do
    events = subscribe "gist.create"
    gist = Gist::Creator.create! contents: gist_test_content_array,
      user: @user, public: false

    expected_payload = {
      visibility: "secret",
      fork: false,
      actor: @user.login,
      actor_id: @user.id,
      user: @user.login,
      user_id: @user.id,
      gist_id: gist.id,
      gist: gist.name_with_owner,
    }

    assert event = events.pop, "expected an instrumentation event"
    assert_equal expected_payload, event.payload
  end

  test "gist creation event published to hydro" do
    GitHub.stubs(:hydro_enabled?).returns(true)
    SecretScanning::Instrumentation::GistServiceFlags.any_instance.stubs(:gist_scanning_service_flags).returns([])
    now = Time.now.beginning_of_day

    Timecop.freeze(now) do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub.context.push(user_agent: "test agent")

      actor = create(:verified_user)
      contents = [
        { name: "file1", value: "text" },
        { name: "file2", value: "another" },
      ]
      gist = GistHelpers.generate(contents: contents, user: actor, description: "description")

      message = {
        actor: Hydro::EntitySerializer.user(actor),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        gist: Hydro::EntitySerializer.gist(gist),
        head_sha: gist.sha,
        files: Hydro::EntitySerializer.gist_files(gist, Gist.limit_files(gist.files)),
        specimen_files: Hydro::EntitySerializer.gist_specimen_files(Gist.limit_files(gist.files).first(3)),
        specimen_gist_description: Hydro::EntitySerializer.specimen_data(gist.description),
        specimen_files_path: Hydro::EntitySerializer.gist_specimen_files_path(Gist.limit_files(gist.files).first(3)),
        feature_flags: [],
      }

      with_hydro_publisher(GitHub.hydro_publisher) do
        assert_hydro_published(message, schema: "github.v1.GistCreate")
      end
    end
  end

  test "gist create publishes event when enabled and its a public gist" do
    GitHub.stubs(:hydro_enabled?).returns(true)
    SecretScanning::Instrumentation::GistServiceFlags.any_instance.stubs(:gist_scanning_service_flags).returns([])
    now = Time.now.beginning_of_day

    Timecop.freeze(now) do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub.context.push(user_agent: "test agent")

      actor = create(:verified_user)
      contents = [
        { name: "file1", value: "text" },
        { name: "file2", value: "another" },
      ]
      gist = GistHelpers.generate(contents: contents, user: actor, description: "description")

      message = {
        actor: Hydro::EntitySerializer.user(actor),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        gist: Hydro::EntitySerializer.gist(gist),
        head_sha: gist.sha,
        files: Hydro::EntitySerializer.gist_files(gist, Gist.limit_files(gist.files)),
        specimen_files: Hydro::EntitySerializer.gist_specimen_files(Gist.limit_files(gist.files).first(3)),
        specimen_gist_description: Hydro::EntitySerializer.specimen_data(gist.description),
        specimen_files_path: Hydro::EntitySerializer.gist_specimen_files_path(Gist.limit_files(gist.files).first(3)),
        feature_flags: [],
      }

      with_hydro_publisher(GitHub.hydro_publisher) do
        assert_hydro_published(message, schema: "github.v1.GistCreate")
      end
    end
  end

  test "gist create publishes event when enabled and its a private gist" do
    GitHub.stubs(:hydro_enabled?).returns(true)
    SecretScanning::Instrumentation::GistServiceFlags.any_instance.stubs(:gist_scanning_service_flags).returns([])
    now = Time.now.beginning_of_day

    Timecop.freeze(now) do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub.context.push(user_agent: "test agent")

      actor = create(:verified_user)
      contents = [
        { name: "file1", value: "text" },
        { name: "file2", value: "another" },
      ]
      gist = GistHelpers.generate(contents: contents, user: actor, public: false, description: "description")

      message = {
        actor: Hydro::EntitySerializer.user(actor),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        gist: Hydro::EntitySerializer.gist(gist),
        head_sha: gist.sha,
        files: Hydro::EntitySerializer.gist_files(gist, Gist.limit_files(gist.files)),
        specimen_files: Hydro::EntitySerializer.gist_specimen_files(Gist.limit_files(gist.files).first(3)),
        specimen_gist_description: Hydro::EntitySerializer.specimen_data(gist.description),
        specimen_files_path: Hydro::EntitySerializer.gist_specimen_files_path(Gist.limit_files(gist.files).first(3)),
        feature_flags: [],
      }

      with_hydro_publisher(GitHub.hydro_publisher) do
        assert_hydro_published(message, schema: "github.v1.GistCreate")
      end
    end
  end

  test "Gist create publishes github.platform_health.v1.UserGeneratedContent" do
    freeze_time
    GitHub.stubs(:hydro_enabled?).returns(true)
    SecretScanning::Instrumentation::GistServiceFlags.any_instance.stubs(:gist_scanning_service_flags).returns([])

    actor = create(:verified_user)
    contents = [
      { name: "file1", value: "text" },
      { name: "file2", value: "another" },
    ]
    gist = GistHelpers.generate(contents: contents, user: actor, description: "hello world")

    message = {
      request_context: nil,
      spamurai_form_signals: nil,
      action_type: :CREATE,
      content_type: :GIST,
      actor: Hydro::EntitySerializer.user(actor),
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.GistCreate"),
      content_database_id: gist.id,
      content_global_relay_id: gist.global_relay_id,
      content_created_at: gist.created_at,
      content_updated_at: gist.updated_at,
      title: nil,
      content: Hydro::EntitySerializer.specimen_data(gist.description),
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: Hydro::EntitySerializer.user(actor),
      repository: nil,
      content_visibility: :PUBLIC,
    }

    with_hydro_publisher(GitHub.hydro_publisher) do
      assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
    end

    contents.each do |file|
      message = {
        request_context: nil,
        spamurai_form_signals: nil,
        action_type: :CREATE,
        content_type: :GIST_FILE,
        actor: Hydro::EntitySerializer.user(actor),
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.GistCreate"),
        content_database_id: gist.id,
        content_global_relay_id: gist.global_relay_id,
        content_created_at: gist.created_at,
        content_updated_at: gist.updated_at,
        title: Hydro::EntitySerializer.specimen_data(file[:name]),
        content: Hydro::EntitySerializer.specimen_data(file[:value]),
        parent_content_author: nil,
        parent_content_database_id: nil,
        parent_content_global_relay_id: nil,
        parent_content_created_at: nil,
        parent_content_updated_at: nil,
        owner: Hydro::EntitySerializer.user(actor),
        repository: nil,
        content_visibility: :PUBLIC,
      }

      with_hydro_publisher(GitHub.hydro_publisher) do
        assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end
  end

  test "secret gists cannot be created by trade restricted users" do
    flagged_actor = create(:user, :fully_trade_restricted)

    gist = build(:gist, user: flagged_actor, public: false)

    refute gist.valid?
    errors = gist.errors.messages[:base]
    assert_match(/GitHub and Trade Controls/, errors.first)
  end

  test "public gists can be created by trade restricted users" do
    flagged_actor = create(:user, :fully_trade_restricted)

    gist = build(:gist, user: flagged_actor, public: true)

    assert gist.valid?
  end

  test "anonymous gist creation event published to hydro" do
    SecretScanning::Instrumentation::GistServiceFlags.any_instance.stubs(:gist_scanning_service_flags).returns([])
    GitHub.stubs(:hydro_enabled?).returns(true)
    now = Time.now.beginning_of_day

    Timecop.freeze(now) do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub.context.push(user_agent: "test agent")

      contents = [
        { name: "file1", value: "text" },
        { name: "file2", value: "another" },
      ]
      gist = GistHelpers.generate(contents: contents, description: "description")

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        gist: Hydro::EntitySerializer.gist(gist),
        head_sha: gist.sha,
        files: Hydro::EntitySerializer.gist_files(gist, Gist.limit_files(gist.files)),
        specimen_files: Hydro::EntitySerializer.gist_specimen_files(Gist.limit_files(gist.files).first(3)),
        specimen_gist_description: Hydro::EntitySerializer.specimen_data(gist.description),
        specimen_files_path: Hydro::EntitySerializer.gist_specimen_files_path(Gist.limit_files(gist.files).first(3)),
        feature_flags: [],
      }

      assert_hydro_published(message, schema: "github.v1.GistCreate")
    end
  end

  test "UnroutedError is rescued by raw_title method" do
    GitRPC::Client.any_instance.stubs(:gist_title).raises(GitHub::DGit::UnroutedError)
    assert_equal @gist.raw_title, @gist.send(:default_title)
  end

  test "UnroutedError is rescued by sha method" do
    @gist.stubs(:rpc).raises GitHub::DGit::UnroutedError
    assert_nil @gist.sha
  end

  test "delegates to user for owned gists" do
    assert_equal @gist.owner.to_param, @gist.user_param
  end

  test "returns 'anonymous' for anonymous gists" do
    @gist.update_attribute :user_id, nil
    assert_equal "anonymous", @gist.user_param
  end

  test "the author can admin" do
    assert @public_gist.adminable_by?(@public_gist.user)
  end

  test "a user who isn't the author can't admin" do
    refute_equal @public_gist.user, @user2

    refute @public_gist.adminable_by?(@user2)
  end

  test "staff who isn't the author cannot admin within the general web ui" do
    refute_equal @public_gist.user, @staff

    refute @public_gist.ui_content_adminable_by?(@staff)
  end

  test "a nil user can't admin" do
    refute @public_gist.adminable_by?(nil)
  end
  unless GitHub.enterprise?
    context "enterprise" do
      test "sets a creator's IP for an anonymous Gist" do
        g = GistHelpers.generate contents: gist_test_content_array, public: true, creator_ip: "1.2.3.4"
        gist = Gist.find(g.id)

        assert_equal gist.creator_ip, "1.2.3.4"
      end

      test "doesn't set a creator's IP for Gist owned by a user" do
        g = GistHelpers.generate user: @user, contents: gist_test_content_array, public: true, creator_ip: "1.2.3.4"
        gist = Gist.find(g.id)

        refute gist.creator_ip
      end

      test "doesn't store an IP if KV is unavailable" do
        GitHub.kv.stubs(:set).raises(GitHub::KV::UnavailableError) # rubocop:todo GitHub/DoNotUseGlobalKv
        g = GistHelpers.generate contents: gist_test_content_array, public: true, creator_ip: "4.5.6.7"
        gist = Gist.find(g.id)

        refute gist.creator_ip
      end

      test "false if the Gist belongs to a user" do
        assert @public_gist.user
        refute @public_gist.deletable_by_ip?("1.2.3.4")
      end

      test "false if there isn't an IP stored for the Gist" do
        GitHub.kv.del(@anon_gist.creator_ip_key) # rubocop:todo GitHub/DoNotUseGlobalKv

        refute @anon_gist.creator_ip
        refute @anon_gist.deletable_by_ip?("1.2.3.4")
      end

      test "true if author IP matches request IP" do
        @anon_gist.creator_ip = "1.2.3.4"
        request = ActionDispatch::Request.new("REMOTE_ADDR" => "1.2.3.4")

        assert_equal @anon_gist.creator_ip, request.remote_ip
        assert @anon_gist.deletable_by_ip?(request.remote_ip)
      end

      test "false if author IP does not match request IP" do
        @anon_gist.creator_ip = "1.2.3.4"
        request = ActionDispatch::Request.new("REMOTE_ADDR" => "5.6.7.8")

        refute_equal @anon_gist.creator_ip, request.remote_ip
        refute @anon_gist.deletable_by_ip?(request.remote_ip)
      end
    end # unless GitHub.enterprise?
  end

  test "returns :user_login/:repo_name" do
    expected = "#{@user.login}/#{@gist.repo_name}"
    assert_equal expected, @gist.name_with_owner
  end

  test "returns anonymous/:repo_name for anoymous gists" do
    expected = "anonymous/#{@anon_gist.repo_name}"
    assert_equal expected, @anon_gist.name_with_owner
  end

  test "takes an optional segment separator" do
    expected = "#{@user.login}-#{@gist.repo_name}"
    assert_equal expected, @gist.name_with_owner("-")
  end

  # NOTE: Repository/Gist defines an #empty? method which requires an extra
  #       #blank? method to get bang finders to work.  This test confirms the bang
  #       finder works until we rename those methods.
  test "can find an existing record" do
    assert Gist.find_by_repo_name!(@public_gist.repo_name)
  end

  test "default_branch name is set to the same name as owner settings" do
    gist = Gist::Creator.create! contents: gist_test_content_array,
      user: @user, public: false

    assert_equal gist.default_branch, @user.default_new_repo_branch
  end

  test "instruments the change" do
    refute @secret_gist.public?

    events = subscribe "gist.visibility_change"

    GitHub.context.push(@user.event_context(prefix: :actor))

    @secret_gist.public = true
    @secret_gist.save!

    assert @public_gist.public?

    expected_payload = {
      gist: @secret_gist.name_with_owner,
      gist_id: @secret_gist.id,
      user: @secret_gist.owner.to_s,
      user_id: @secret_gist.owner.id,
      actor: @user.to_s,
      actor_id: @user.id,
      visibility: "public",
      old_visibility: "secret",
      fork: @secret_gist.fork?,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "gist.visibility_change", event.name
    assert_equal expected_payload, event.payload
    assert_nil events.pop, "an event was not expected"
  end

  test "does not allow public gists to become private" do
    assert @public_gist.public?
    @public_gist.public = false
    refute @public_gist.save
    assert_includes @public_gist.errors.full_messages.to_s, "To remove public content, delete the gist instead"
  end

  test "instruments backfill request for secret scanning", skip_enterprise: true do
    expected_flags = %w[flag1 flag2]
    SecretScanning::Instrumentation::GistServiceFlags.any_instance.stubs(:gist_scanning_service_flags).returns(expected_flags)
    refute @secret_gist.public?

    with_hydro_publisher(GitHub.hydro_publisher) do
      @secret_gist.update!(public: true)

      assert @secret_gist.public?

      message = {
        full_scan_type: {},
        actor: Hydro::EntitySerializer.user(@secret_gist.user),
        gist_scope: {
          gist: Hydro::EntitySerializer.gist(@secret_gist),
          owner: Hydro::EntitySerializer.user(@secret_gist.user),
        },
        feature_flags: expected_flags,
        type: :START,
        requested_at: @secret_gist.updated_at,
      }

      assert_hydro_published(message, schema: "token_scanning_service.v0.BackfillRequest")
    end
  end

  test "touches the gist" do
    updated = @public_gist.updated_at
    Timecop.freeze(1.day.from_now) do
      @user.star(@public_gist)
    end
    refute_equal @public_gist.reload.updated_at, updated, "Expected starring to update gist updated_at"

    updated = @public_gist.updated_at
    Timecop.freeze(2.days.from_now) do
      @user.unstar(@public_gist)
    end
    refute_equal @public_gist.reload.updated_at, updated, "Expected unstarring to update gist updated_at"
  end

  test "indexes the Gist on create" do
    Gist.any_instance.stubs(:gist_is_searchable?).returns(true)
    now = Time.now
    timestamp = Timestamp.from_time(now)
    gist = nil
    Timecop.freeze(now) do
      perform_enqueued_jobs(only: [GistSynchronizeSearchIndexJob]) do
        gist = GistHelpers.generate \
          contents: gist_test_content_array,
          user: @user,
          public: false
      end

      guid = AddToSearchIndexJob.guid("gist", gist.id)

      assert_enqueued_with(job: AddToSearchIndexJob, args: ["gist", gist.id, { "submitted_at" => timestamp, "guid" => guid }], queue: "index_high")
    end
  end

  test "re-indexes the Gist on update" do
    now = Time.now
    timestamp = Timestamp.from_time(now)
    guid = AddToSearchIndexJob.guid("gist", @gist.id)
    Timecop.freeze(now) do
      assert_enqueued_with(job: AddToSearchIndexJob, args: ["gist", @gist.id, { "submitted_at" => timestamp, "guid" => guid }], queue: "index_high") do
        perform_enqueued_jobs(only: [GistSynchronizeSearchIndexJob]) do
          @gist.update_pushed_at
          @gist.save!
        end
      end
    end
  end

  test "removes the Gist from the search index on disable" do
    assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["gist", @gist.id], queue: "index_high") do
      perform_enqueued_jobs(only: [GistSynchronizeSearchIndexJob]) do
        @gist.access.disable("size", @staff)
      end
    end
  end

  test "adds the Gist back to the search index on re-enable" do
    @gist.access.disable("size", @staff)

    now = Time.now
    timestamp = Timestamp.from_time(now)
    guid = AddToSearchIndexJob.guid("gist", @gist.id)
    Timecop.freeze(now) do
      assert_enqueued_with(job: AddToSearchIndexJob, args: ["gist", @gist.id, { "submitted_at" => timestamp, "guid" => guid }], queue: "index_high") do
        perform_enqueued_jobs(only: [GistSynchronizeSearchIndexJob]) do
          @gist.access.enable(@staff)
        end
      end
    end
  end

  test "re-indexes the Gist on star" do
    guid = AddToSearchIndexJob.guid("gist", @gist.id)
    freeze_time do
      timestamp = Timestamp.from_time(Time.now)
      assert_enqueued_with(
        job: AddToSearchIndexJob,
        args: ["gist", @gist.id, { "submitted_at" => timestamp, "guid" => guid }],
        queue: "index_high",
      ) do
        perform_enqueued_jobs(only: [GistSynchronizeSearchIndexJob]) do
          assert @user.star(@gist)
        end
      end
    end
  end

  test "re-indexes the Gist on unstar" do
    assert @user.star(@gist)
    guid = AddToSearchIndexJob.guid("gist", @gist.id)

    freeze_time do
      timestamp = Timestamp.from_time(Time.now)
      assert_enqueued_with(
        job: AddToSearchIndexJob,
        args: ["gist", @gist.id, { "submitted_at" => timestamp, "guid" => guid }],
        queue: "index_high",
      ) do
        perform_enqueued_jobs(only: [GistSynchronizeSearchIndexJob]) do
          @user.unstar(@gist)
        end
      end
    end
  end

  test "removes the Gist from the index on delete" do
    assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["gist", @gist.id], queue: "index_high") do
      perform_enqueued_jobs(only: [GistSynchronizeSearchIndexJob]) do
        @gist.remove
      end
    end
  end

  test "#cache_key includes all the useful bits" do
    key = @gist.cache_key

    assert_match /#{@gist.id}/, key
    # Username changes will change the cache key now!
    assert_match /#{@gist.user_param}/, key
    assert_match /#{@gist.updated_at.iso8601}/, key
    assert_match /#{@gist.sha}/, key
  end

  test "#search_engine_indexable?" do
    allowed_anon_gist = GistHelpers.generate(contents: gist_test_content_array, public: true, creator_ip: "1.2.3.4")
    allowed_anon_gist.update(repo_name: Gist::Anonymous::ALLOWLIST.first)

    refute @anon_gist.search_engine_indexable?
    assert allowed_anon_gist.search_engine_indexable?
  end

  context "#files" do
    test "returns an empty array if a GitRPC error is raised" do
      handled_errors = [GitRPC::BadRepositoryState, GitRPC::InvalidRepository, GitRPC::ObjectMissing]

      handled_errors.each do |err_class|
        @gist.stubs(:blobs).raises err_class.new

        assert_equal [], @gist.files
      end
    end
  end

  context "#title" do
    test "truncates titles longer than Gist::MAX_GIST_TITLE_LENGTH" do
      longest_gist_title = "a" * Gist::MAX_GIST_TITLE_LENGTH
      @gist.stubs(:raw_title).returns(longest_gist_title)
      assert_equal longest_gist_title, @gist.title

      @gist.stubs(:raw_title).returns(longest_gist_title + " FOO BAR BAZ")
      assert_equal longest_gist_title, @gist.title
    end
  end

  context "#description" do
    test "supports emoji in UTF-8" do
      gist = GistHelpers.generate(user: @user, contents: gist_test_content_array, description: "we ❤️ emojis")

      assert_multibyte_tracked_changes(gist, :description)
    end

    test "lazily scrubs invalid UTF-8 descriptions" do
      @gist.update_column :description, "1\xC0\u0000xa7\xC0\xA2".b
      @gist.reload
      refute @gist.description.valid_encoding?

      @gist.update! pushed_at: Time.zone.now # make unrelated change
      @gist.reload
      assert @gist.description.valid_encoding?, "expected description to be valid UTF-8"
      assert_equal "1�\u0000xa7��", @gist.description
    end
  end

  context "#failbot_context" do
    test "includes all required keys" do
      ["gh.gist.id", "git.commit.oid", "gh.spokes.spec"].each do |required_key|
        assert @gist.failbot_context.has_key?(required_key.to_sym)
      end
    end
  end

  test "returns public and secret forks when the parent is secret" do
    secret_parent = create(:gist, public: false)
    public_fork   = create(:gist, public: true, parent: secret_parent)
    secret_fork   = create(:gist, public: false, parent: secret_parent)

    assert_equal [public_fork, secret_fork],
      secret_parent.visible_forks.order(:id)
  end

  test "only returns public forks when the parent is public" do
    public_parent = create(:gist, public: true)
    public_fork   = create(:gist, public: true, parent: public_parent)
    secret_fork   = create(:gist, public: false, parent: public_parent)

    assert_equal [public_fork],
      public_parent.visible_forks.order(:id)
  end

  context "auto subscriptions" do
    test "automatically subscribes the author with the feature enabled" do
      GitHub.flipper[:notifyd_primary_gist].disable
      gist = GistHelpers.generate(contents: gist_test_content_array, user: @user)

      subscription_status = gist.subscription_status(@user)
      assert_predicate subscription_status, :subscribed?
      assert_equal "author", subscription_status.reason
    end

    # Apprently there are 55577940 gists without a `user_id`:
    # SELECT count(*) FROM gists where user_id IS NULL;
    # +----------+
    # | count(*) |
    # +----------+
    # | 55577940 |
    # +----------+
    # See https://gist.github.com/0efca69c721f1cea0c49 as an example.
    test "gracefully handles gists without an author" do
      assert GistHelpers.generate(contents: gist_test_content_array, user: nil)
    end
  end

  context "SubscribableThread" do
    context "#notifications_list" do
      test "returns the author of the gist" do
        assert_equal @user, @public_gist.notifications_list
      end

      test "returns the ghost user for anonymous gists" do
        gist = GistHelpers.generate(contents: gist_test_content_array, user: nil)
        assert_equal User.ghost, gist.notifications_list
      end
    end

    context "#notifications_thread" do
      test "returns the gist" do
        assert_equal @public_gist, @public_gist.notifications_thread
      end
    end

    context "#notifications_author" do
      test "returns the author of the gist" do
        assert_equal @user, @public_gist.notifications_author
      end

      test "returns the ghost user for anonymous gists" do
        gist = GistHelpers.generate(contents: gist_test_content_array, user: nil)
        assert_equal User.ghost, gist.notifications_author
      end
    end

    context "#subscribe" do
      test "subscribes a user in Newsies" do
        GitHub.flipper[:notifyd_primary_gist].disable

        refute @public_gist.subscribed?(@user2)

        @public_gist.subscribe(@user2, :author)

        assert @public_gist.subscribed?(@user2)
      end
    end
  end

  test "cleans up newsies data for thread when gist is destroyed" do
    GitHub.newsies.expects(:async_delete_all_for_thread).with(@gist.user, @gist)

    @gist.destroy
  end

  test "filters disabled gists if viewer is not staff admin" do
    viewer = create(:user)
    refute_includes Gist.filter_spam_and_disabled_for(viewer), @disabled_gist
  end

  test "keeps disabled gists if viewer is staff admin" do
    assert_includes Gist.filter_spam_and_disabled_for(@staff), @disabled_gist
  end

  if GitHub.spamminess_check_enabled?
    test "filters spam gists if the viewer is not staff or the spammer" do
      viewer = create(:user)
      refute_includes Gist.filter_spam_and_disabled_for(viewer), @spam_gist
    end

    test "keeps spam gists if the viewer is the spammer" do
      assert_includes Gist.filter_spam_and_disabled_for(@spammer), @spam_gist
    end

    test "keeps spam gists if the viewer is a staff admin" do
      assert_includes Gist.filter_spam_and_disabled_for(@staff), @spam_gist
    end
  end

  test "keeps non-spam, non-disabled gists for random viewer" do
    viewer = create(:user)
    assert_includes Gist.filter_spam_and_disabled_for(viewer), @gist
  end

  test "keeps non-spam, non-disabled gists for anonymous viewer" do
    assert_includes Gist.filter_spam_and_disabled_for(nil), @gist
  end

  test "timeline_for returns all gist comments with spam filtered out" do
    spammy_comment = create(:gist_comment, gist: @gist, user: @spammer)
    non_spammy_comment = create(:gist_comment, gist: @gist, user: @user)
    assert_equal [*(spammy_comment unless GitHub.spamminess_check_enabled?), non_spammy_comment], @gist.timeline_for(@user)
  end

  test "timeline_for with :since option returns all comments since the given time" do
    gist_comment = create(:gist_comment, gist: @gist, user: @user, created_at: 1.day.ago)
    spammy_comment = create(:gist_comment, gist: @gist, user: @spammer, created_at: 1.day.ago)

    assert_equal [gist_comment, *(spammy_comment unless GitHub.spamminess_check_enabled?)], @gist.timeline_for(@user, since: 2.days.ago)
    assert_equal [], @gist.timeline_for(@user, since: 30.minutes.ago)
  end

  test "timeline_for returns all comments if there are fewer than #{Gist::COMMENTS_PER_PAGE}" do
    gist_comment = create(:gist_comment, gist: @gist, user: @user, created_at: 1.day.ago)
    assert_equal [gist_comment], @gist.timeline_for(@user)
  end

  test "timeline_for with :permalink_comment_id option returns all comments since permalinked comment" do
    gist_comment = create(:gist_comment, gist: @gist, user: @user)
    permalink_comment = create(:gist_comment, gist: @gist, user: @user)
    Gist::COMMENTS_PER_PAGE.times do |i|
      create :gist_comment, gist: @gist, user: @user, created_at: i.hours.ago, updated_at: i.hours.ago
    end

    @gist.reload

    timeline = @gist.timeline_for(@user, permalink_comment_id: permalink_comment.id)

    refute_includes timeline, gist_comment
    assert_equal timeline.first.id, permalink_comment.id
    assert_equal timeline.last.id, @gist.comments.last.id
  end

  test "timeline_for returns truncated comments page if there are more than #{Gist::COMMENTS_PER_PAGE}" do
    total_comments = Gist::COMMENTS_PER_PAGE + 1
    total_comments.times do |i|
      create :gist_comment, gist: @gist, user: @user, created_at: i.hours.ago, updated_at: i.hours.ago
    end

    @gist.reload

    timeline_comments = @gist.timeline_for(@user)

    assert_equal Gist::COMMENTS_PER_PAGE, timeline_comments.count
    refute_includes timeline_comments, @gist.comments.first
  end

  test "timeline_for with :before_comment_id" do
    gist_comment = create(:gist_comment, gist: @gist, user: @user)
    assert_equal [gist_comment], @gist.timeline_for(@user, before_comment_id: gist_comment.id + 1)
    assert_empty @gist.timeline_for(@user, before_comment_id: gist_comment.id)

    refute_error_reported do # Prevent a query warning regression
      assert_empty @gist.timeline_for(@user, before_comment_id: "invalid id")
    end
  end

  test "timeline_for with :after_comment_id" do
    gist_comments = create_list(:gist_comment, 2, gist: @gist, user: @user)
    assert_equal gist_comments.last(1), @gist.timeline_for(@user, after_comment_id: gist_comments.last.id, forward_in_time_pagination: true)
    assert_empty @gist.timeline_for(@user, after_comment_id: gist_comments.last.id + 1, forward_in_time_pagination: true)
  end

  test "allow fork gist with mixed file contents" do
    gist = GistHelpers.generate_with_example_repo(:gist_with_mixed_file_contents)

    new_user = create(:user)

    forked_gist = gist.fork(new_user)
    assert forked_gist
  end

  test "allow fork gist with only binary files" do
    gist = GistHelpers.generate_with_example_repo(:gist_with_only_binary_files)

    assert gist.sorted_files.all?(&:binary?)

    new_user = create(:user)

    forked_gist = gist.fork(new_user)
    assert forked_gist
  end
end

module SoftDeletedGistTestHelper
  def gist_test_content_array
    [
      { name: "1", value: "random content" },
    ]
  end
end

class SoftDeletedGistTest < GitHub::TestCase
  include SoftDeletedGistTestHelper

  fixtures do
    @user = create(:user)
  end

  setup do
    @gist = Gist::Creator.create!(user: @user,
                                  contents: [{ name: "1", value: "blah" }])
  end

  context ".with_name_with_owner" do
    test "returns nil for soft_deleted gists" do
      @gist.remove
      nwo = "#{@user}/#{@gist}"
      assert_nil Gist.with_name_with_owner(nwo)
    end

    test "returns nil for soft_deleted anon gists" do
      @gist.remove
      nwo = "anonymous/#{@gist}"
      assert_nil Gist.with_name_with_owner(nwo)
    end
  end

  test "soft_delete and restore a gist" do
    gist_id = @gist.id
    if GitHub.enterprise?
      assert_equal GitHub.dgit_default_copies, GitHub::DGit::Routing.all_gist_replicas(gist_id).size
    end

    assert_equal @user.id, @gist.user_id

    # sanity check: does rpc work for the non-archived repo?
    assert_match /[a-f0-9]{40}/, @gist.rpc.read_refs["refs/heads/main"]

    hosts = GitHub::DGit::Routing.hosts_for_gist(gist_id) if GitHub.enterprise?

    soft_deleted_record = @gist.remove
    assert soft_deleted_record.deleted?
    refute soft_deleted_record.active?

    perform_enqueued_jobs only: [SpokesCreateGistReplicaJob] do
      restored_record = Gist.restore(gist_id)
      assert_equal Gist.find(gist_id), restored_record
      refute restored_record.deleted?
      assert restored_record.active?
    end
    assert Gist.exists?(gist_id)

    assert_equal 3, GitHub::DGit::Routing.all_gist_replicas(gist_id).size

    gist = Gist.find(gist_id)
    assert_equal @user.id, gist.user_id
    assert_match /[a-f0-9]{40}/, @gist.rpc.read_refs["refs/heads/main"] if GitHub.enterprise?
  end

  test "can purge soft_deleted gists", skip_enterprise: true do
    comment = @gist.comments.create(body: "Hello world!", user: @user)

    gist_id = @gist.id
    soft_deleted_record = @gist.remove
    assert soft_deleted_record.deleted?
    refute soft_deleted_record.active?
    assert_equal gist_id, soft_deleted_record.id

    soft_deleted_record.purge

    refute Gist.exists?(gist_id)
    refute GistComment.exists?(comment.id)
    assert @gist.destroyed?
  end
end
