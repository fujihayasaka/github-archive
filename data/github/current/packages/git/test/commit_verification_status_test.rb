# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitVerificationStatusTest < GitHub::TestCase
  include GpgKeyHelper
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :signed_commits)
    @committer = create(:user, :verified, email: "nickborromeo@github.com")
    create_gpg_key("three")

    # co-authors
    @co_author1 = create(:user, email: "jdpace@github.com")
    @co_author2 = create(:user, email: "waldnzwrld@github.com")


    @user = create_gpg_key.user
  end

  setup do
    @co_authored_commit_oid = "390f7054b0cfcf85c0c89228725654fc5b920b4f"
    @co_authored_commit = @repo.commits.find(@co_authored_commit_oid)

    @unsigned_commit_oid = "d014786a170b6ef6ed6a1814be8c941db39cd259"
    @unsigned_commit = @repo.commits.find(@unsigned_commit_oid)

    @wrong_key_gpg_commit_oid = "a1b6decaaac768b5e01e1b5dbf5b2cc081bed1eb"
    @wrong_key_gpg_commit = @repo.commits.find(@wrong_key_gpg_commit_oid)

    @gpg_commit_oid = "378718a43decc3471c6a90b8aac95440a4e11152"
    @gpg_commit = @repo.commits.find(@gpg_commit_oid)

    @unsigned_co_authored_commit_oid = "4814986e7069f320e3bda6014603abcbf492a545"
    @unsigned_co_authored_commit = @repo.commits.find(@unsigned_co_authored_commit_oid)

    @author_overridden_signed_commit_oid = "4601ebf6a1f9030b8c39efee844caa5536b7891a"
    @author_overridden_signed_commit = @repo.commits.find(@author_overridden_signed_commit_oid)

    @author_overridden_unsigned_commit_oid = "d184c58b0d57a6a10f3eda68e00787583a319755"
    @author_overridden_unsigned_commit = @repo.commits.find(@author_overridden_unsigned_commit_oid)

    @author_overridden_signed_commit_with_co_author_oid = "a8320cbb1215f9a3f54e9b5d1e76a83c9679eb27"
    @author_overridden_signed_commit_with_co_author_commit = @repo.commits.find(@author_overridden_signed_commit_with_co_author_oid)
  end

  context "async_verification_status" do
    test "does not change expected behavior when no authors have the setting turned on" do
      # this represents falling back to legacy behavior

      # commit with just one author
      assert_equal :verified, @gpg_commit.async_verification_status.sync
      # commit with co-authors
      assert_equal :verified, @co_authored_commit.async_verification_status.sync
      # signed commit with invalid signature
      assert_equal :unverified, @wrong_key_gpg_commit.async_verification_status.sync
    end

    test "returns unsigned if commit is unsigned and author does not have the setting turned on" do
      assert_equal :unsigned,  @unsigned_commit.async_verification_status.sync
      # commit with co-authors
      assert_equal :unsigned,  @unsigned_co_authored_commit.async_verification_status.sync
    end

    test "returns :unverified if commit is unsigned and committer has the setting turned on" do
      committer = @unsigned_commit.committer
      committer.set_commit_verification_status_state(actor: committer, state: "enabled")
      assert_equal :unverified, @unsigned_commit.async_verification_status.sync
    end

    test "returns :unverified if commit signature is invalid and committer has setting turned on" do
      committer = @wrong_key_gpg_commit.committer
      committer.set_commit_verification_status_state(actor: committer, state: "enabled")
      assert_equal :unverified, @wrong_key_gpg_commit.async_verification_status.sync
    end

    test "returns :unverified if commit signature is invalid and committer does not have setting turned on" do
      committer = @wrong_key_gpg_commit.committer
      assert_equal :unverified, @wrong_key_gpg_commit.async_verification_status.sync
    end

    test "return :unverified if commit is unsigned and any co-authors have the setting turned on" do
      @committer.set_commit_verification_status_state(actor: @committer, state: "enabled")
      @co_author1.set_commit_verification_status_state(actor: @co_author1, state: "enabled")
      @co_author2.set_commit_verification_status_state(actor: @co_author2, state: "enabled")

      assert_equal :unverified, @unsigned_co_authored_commit.async_verification_status.sync
    end

    test "return :unverified if commit is unsigned and committer and author are different and committer has setting turned on" do
      @committer.set_commit_verification_status_state(actor: @committer, state: "enabled")
      assert_equal :unverified, @author_overridden_unsigned_commit.async_verification_status.sync
    end

    test "return :partially_verified if signed commit with committer and author are different and author has setting turned on" do
      @co_author1.set_commit_verification_status_state(actor: @co_author1, state: "enabled")
      assert_equal :partially_verified, @author_overridden_signed_commit.async_verification_status.sync
    end

    test "return :unverified if commit is unsigned and committer and author are different and author has setting turned on" do
      @co_author1.set_commit_verification_status_state(actor: @co_author1, state: "enabled")
      assert_equal :unverified, @author_overridden_unsigned_commit.async_verification_status.sync
    end

    test "return :partially_verified if one of the co-authors has the setting turned on" do
      @co_author1.set_commit_verification_status_state(actor: @co_author1, state: "enabled")

      assert_equal :partially_verified, @co_authored_commit.async_verification_status.sync
    end

    test "return :partially_verified if the committer is not one of the authors that have the setting turned on" do
      @co_author1.set_commit_verification_status_state(actor: @co_author1, state: "enabled")

      assert_equal :partially_verified, @author_overridden_signed_commit.async_verification_status.sync
      assert_equal :partially_verified, @author_overridden_signed_commit_with_co_author_commit.async_verification_status.sync

      @co_author1.set_commit_verification_status_state(actor: @co_author1, state: "disabled")
      @co_author2.set_commit_verification_status_state(actor: @co_author2, state: "enabled")
      assert_equal :partially_verified, @author_overridden_signed_commit_with_co_author_commit.async_verification_status.sync
    end

    test "return :partially_verified if all authors have the setting turned on" do
      @committer.set_commit_verification_status_state(actor: @committer, state: "enabled")
      @co_author1.set_commit_verification_status_state(actor: @co_author1, state: "enabled")
      @co_author2.set_commit_verification_status_state(actor: @co_author2, state: "enabled")

      assert_equal :partially_verified, @co_authored_commit.async_verification_status.sync
    end

    test "return :verified if there is only one author and setting is turned on" do
      @user.set_commit_verification_status_state(actor: @user, state: "enabled")

      assert_equal :verified, @gpg_commit.async_verification_status.sync
    end

    test "return :verified if there is only one author and setting is not turned on" do
      refute @user.commit_verification_status_enabled?

      assert_equal :verified, @gpg_commit.async_verification_status.sync
    end

    test "return :verified if committer and author is different and committer has setting turned on" do
      @committer.set_commit_verification_status_state(actor: @committer, state: "enabled")
      assert_equal :verified, @author_overridden_signed_commit.async_verification_status.sync
    end

    test "return :verified for signed commit where author and committer are different with co-authors and committer has setting turned on" do
      @committer.set_commit_verification_status_state(actor: @committer, state: "enabled")
      assert_equal :verified, @author_overridden_signed_commit_with_co_author_commit.async_verification_status.sync
    end
  end
end

class WebCommitVerificationStatusTest < GitHub::TestCase
  # This class tests the behavior of commits created via the web UI
  # we need to mock out the signature of the web committer in order for the commit verification status logic to verify
  # that the signature is valid.
  #
  # These tests will fail on local because of the following line:
  #
  # GitHub.git_signing_smime_cert_store.add_cert(smime_ca.parsed)
  #
  # since GitHub uses the Debian ca-certificates package, and locally we don't have that there is no way to bypass this.
  # Other tests we have for signed commits via the web use the same pattern
  include GpgKeyHelper
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :signed_commits)
    @committer = create(:user, :verified, email: "nickborromeo@github.com")

    @signing_key = create_gpg_key
    @user = @signing_key.user
    smime_ca   = FakeCA.new("/CN=root1")
    smime_cert = smime_ca.issue("/CN=#{@user.login}/emailAddress=#{@user.emails.verified.first.email}")
    GitHub.git_signing_smime_cert_store.add_cert(smime_ca.parsed)
    @smime_commit_oid = smime_cert.create_signed_commit(@repo, @user)

    @commit_info = {
      "oid"       => SecureRandom.hex(20),
      "type"      => "commit",
      "message"   => "some change",
      "author"    => [@committer.login, @committer.email, "2021-02-28T16:20:56Z"],
      "committer" => [GitHub.web_committer_name, GitHub.web_committer_email, "2021-02-28T16:20:56Z"],
    }
  end

  setup do
    WebFlowHelper.setup_webflow

    smime_commit = @repo.commits.find(@smime_commit_oid)
    @signed_signature = Platform::Loaders::GitSignature.load(smime_commit)
  end

  test "return :unsigned if commit is not signed" do
    web_commit = Commit.new(@repo, @commit_info)
    assert_equal :unsigned,  web_commit.async_verification_status.sync
  end

  test "return :unverified if commit is not signed and one of the authors has the setting turned on" do
    @committer.set_commit_verification_status_state(actor: @committer, state: "enabled")

    web_commit = Commit.new(@repo, @commit_info)
    assert_equal :unverified, web_commit.async_verification_status.sync

    # web commit with co-authors
    co_authors = 3.times.map { create(:user) }
    enabled_author = co_authors.last
    enabled_author.set_commit_verification_status_state(actor: enabled_author, state: "enabled")

    co_author_trailer = { "trailers" => { "co-authored-by" => co_authors.map { |a| "#{a.login} <#{a.email}>" } } }
    commit_info = @commit_info.merge(co_author_trailer)

    web_commit = Commit.new(@repo, commit_info)
    assert_equal :unverified, web_commit.async_verification_status.sync
  end

  test "return :partially_verified if commit is signed by GitHub and at least one of the authors has the setting turned on" do
    co_authors = 3.times.map { create(:user) }
    enabled_author = co_authors.first
    enabled_author.set_commit_verification_status_state(actor: enabled_author, state: "enabled")

    co_author_trailer = { "trailers" => { "co-authored-by" => co_authors.map { |a| "#{a.login} <#{a.email}>" } } }
    commit_info = @commit_info.merge(co_author_trailer)

    web_commit = Commit.new(@repo, commit_info)
    Platform::Loaders::GitSignature.expects(:load).with(web_commit).returns(@signed_signature)

    assert_equal 4, web_commit.author_names.size
    assert_equal GitHub.web_committer_email, web_commit.committer_email
    assert_equal :partially_verified, web_commit.async_verification_status.sync
  end

  test "return :verified if commit is signed by GitHub via the web UI" do
    @committer.set_commit_verification_status_state(actor: @committer, state: "enabled")

    web_commit = Commit.new(@repo, @commit_info)
    Platform::Loaders::GitSignature.expects(:load).with(web_commit).returns(@signed_signature)

    assert_equal GitHub.web_committer_email, web_commit.committer_email
    assert_equal :verified, web_commit.async_verification_status.sync
  end
end
