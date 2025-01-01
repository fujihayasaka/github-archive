# typed: true
# frozen_string_literal: true

require "test_helper"

class TagTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :refs_test)
    example_repo_snapshot
  end

  setup do
    assert @ref = @repo.tags.find("v1.0")
    @tag = @repo.objects.read(@ref.target_oid)
    example_repo_restore
  end

  test "reading a tag object" do
    assert_equal Tag, @tag.class
    assert_equal @ref.target_oid, @tag.oid
    assert_equal "v1.0", @tag.name
    assert_equal "my tag message\n", @tag.message
    assert_equal "my tag message", @tag.short_message
    assert_equal "Scott Chacon", @tag.author_name
    assert_equal "schacon@gmail.com", @tag.author_email
    assert_equal [1306514931, -25200], @tag.authored_date_value
    assert_equal "2011-05-27T16:48:51Z", @tag.authored_date.utc.iso8601
    assert_equal "46291865ba0f6e0c9818b11be799fe2db6964d56", @tag.target_oid
    assert_equal "commit", @tag.target_type
    assert_equal false, @tag.has_signature?
  end

  test "loading a tag's target commit" do
    assert @tag.target.is_a?(Commit)
    assert_equal @tag.target_oid, @tag.target.oid
  end

  test "loading a tag's target object when not a commit" do
    assert ref = @repo.tags.find("RAKE")
    assert tag = @repo.objects.read(ref.target_oid)
    assert_equal Blob, tag.target.class
    assert_equal tag.target_oid, tag.target.oid
  end

  context "#peel_to_commit" do
    test "tag->commit returns the commit target" do
      peel_result = @tag.peel_to_commit
      assert_instance_of(Commit, peel_result)
      assert_equal(@tag.target, peel_result)
    end

    test "tag->tag->commit peels two layers to return the commit target" do
      outer = @repo.objects.read(create_tag("outer", @tag.oid))
      peel_result = outer.peel_to_commit
      assert_instance_of(Commit, peel_result)
      assert_equal(outer.target.target, peel_result)
    end

    test "tag->blob returns nil" do
      blob_oid = @repo.objects.read(@repo.default_branch_ref.target.tree_oid).entries.find(&:blob?)&.oid or fail "no blob"
      blob_tag = @repo.objects.read(create_tag("blob_obj", blob_oid))
      assert_nil(blob_tag.peel_to_commit)
    end

    test "tag->tree returns nil" do
      tree_oid = @repo.default_branch_ref.target.tree_oid
      tree_tag = @repo.objects.read(create_tag("tree_obj", tree_oid))
      assert_nil(tree_tag.peel_to_commit)
    end
  end

  private

  def create_tag(tag_name, target_oid, repository: @repo, user: @user, message: SecureRandom.hex)
    repository.rpc.create_tag_annotation(tag_name, target_oid, message: message, tagger: {
      email: user.git_author_email,
      name: user.git_author_name,
      time: user.time_zone.now.iso8601,
    })
  end
end

class TagGpgSignatureVerificationTest < GitHub::TestCase
  include GpgKeyHelper

  fixtures do
    @repo = create(:repository)
    @signing_key = create_gpg_key
    @user = @signing_key.user
    create(:user_email, :verified, user: @user, email: "mastahyeti@github.com")

    @other_signing_key = create_gpg_key("two")
  end

  setup do
    example_repo :signed_commits, @repo
    @signed_tag = @repo.tags.find("signed").target
    @unsigned_tag = @repo.tags.find("unsigned").target
    @smime_tag = @repo.tags.find("smime_signed").target
  end

  context "#signature" do
    test "parses signature out of tag message" do
      assert_equal <<-HERE.gsub(/^ */, ""), @signed_tag.signature
        -----BEGIN PGP SIGNATURE-----
        Version: GnuPG v1

        iQEcBAABAgAGBQJWvQy0AAoJEDJi7/JboNJw9xYH/2BbgwRCLz9CBolOwaaQ7yRB
        zB4zW9OC8Itma7SxRfyfnPTkNETgbV/EB4zVtyHCCW8H3xxfW3sLfRpnGg8yxEA0
        Bej2bjDqa8u+7/fOiUkizWIiB+PQP00Q97uRYB29f8qmX5t4NaT2B3LJMMrnIh1f
        CUWGjrNdeodxZD1a9ByAZnO0K3YxE2EiHkF9ayNvtEsNVv/y9yMnYGLI1A2UKWix
        nZ8ARbCzeUxYxYJTJ0mP0sP+5kpBfl5fqksuLlcC+5KgWDk8BB5fzpSXnQDrsnEW
        XibfqJQxUE9hVe6C5jfhiDO3mZyRZcE8O7Ee5lQicK+p0gBf0YFoqq1yh9qD50M=
        =wgz0
        -----END PGP SIGNATURE-----
      HERE
    end

    test "doesn't cause a request to gpgverify" do
      # Api::GitTags calls Tag#signature and we gpgverify isn't ready to handle
      # requests in production yet.
      GitHub.gpg.expects(:request).never
      @signed_tag.signature
      @smime_tag.signature
      @unsigned_tag.signature
    end

    test "is nil for unsigned tag" do
      assert_nil @unsigned_tag.signature
    end
  end

  context "#signing_payload" do
    test "parses signing  payload out of signed tag" do
      assert_equal <<-HERE.gsub(/^ */, ""), @signed_tag.signing_payload
        object cb842b3b6e8dc7fdef91b4bc564862fd8af271ea
        type commit
        tag signed
        tagger Some User <someuser@gmail.com> 1455230132 -0700

        my signed commit
      HERE
    end

    test "no signing payload for unsigned tag" do
      assert_nil @unsigned_tag.signing_payload
    end
  end

  context "#has_signature?" do
    test "can detect if tag is signed" do
      assert_predicate @signed_tag, :has_signature?
      assert_predicate @smime_tag, :has_signature?
      refute_predicate @unsigned_tag, :has_signature?
    end

    test "doesn't cause a request to gpgverify" do
      # Api::GitTags calls Tag#signature and we gpgverify isn't ready to handle
      # requests in production yet.
      GitHub.gpg.expects(:request).never
      @signed_tag.has_signature?
      @smime_tag.has_signature?
      @unsigned_tag.has_signature?
    end
  end

  context "#signature_issuer_key_id" do
    test "gets key id from signature" do
      assert_equal @signing_key.key_id, @signed_tag.signature_issuer_key_id
      assert_nil @unsigned_tag.signature_issuer_key_id
    end

    test "is nil if gpg backend is unavailable" do
      GitHub.gpg.instance_variable_set(:@available, false)
      GitHub.gpg.expects(:batch_signature_issuer_key_id).never

      assert_nil @unsigned_tag.signature_issuer_key_id
    end

    test "returns nil for gpgverify errors" do
      GitHub.gpg.stubs(:batch_signature_issuer_key_id).raises(GpgVerify::Unavailable)

      assert_nil @unsigned_tag.signature_issuer_key_id
    end
  end

  context "#signer" do
    test "is loaded from the author email address" do
      assert_equal @user, @signed_tag.signer
      assert_equal @user, @smime_tag.signer
    end
  end

  context "#verified_signature?" do
    test "checks that signature is present and valid" do
      assert_predicate @signed_tag, :verified_signature?
      refute_predicate @signed_tag, :unverified_signature?

      refute_predicate @smime_tag, :verified_signature?
      assert_predicate @smime_tag, :unverified_signature?
      assert_equal GitSigning::BAD_CERT, @smime_tag.signature_verification_reason

      refute_predicate @unsigned_tag, :verified_signature?
      refute_predicate @unsigned_tag, :unverified_signature?
    end
  end

  context "Tag.prefill_verified_signature" do
    test "prefills signature for multiple tags" do
      Tag.prefill_verified_signature([
        @signed_tag,
        @smime_tag,
        @unsigned_tag,
       ], @repo)

      GitRPC::Client.any_instance.expects(:parse_tag_signatures).never
      GitHub.gpg.expects(:batch_signature_issuer_key_id).never

      assert_equal @signing_key.key_id, @signed_tag.signature_issuer_key_id
      assert_nil @smime_tag.signature_issuer_key_id
      assert_nil @unsigned_tag.signature_issuer_key_id

      refute_predicate @smime_tag, :verified_signature?
      assert_predicate @smime_tag, :unverified_signature?
      assert_equal GitSigning::BAD_CERT, @smime_tag.signature_verification_reason

      refute_predicate @unsigned_tag, :verified_signature?
    end
  end

  context "#verification_status" do
    test "returns unsigned if the tag author doesn't have setting enabled and the tag is unsigned" do
      assert_equal :unsigned, @smime_tag.verification_status
      assert_equal :unsigned, @unsigned_tag.verification_status
    end

    test "returns :verified if the tag author doesn't have setting enabled and the tag is signed" do
      assert_equal :verified, @signed_tag.verification_status
    end

    test "returns nil if the tag doesn't have an associated author" do
      @user.destroy
      reloaded_tag = @repo.tags.find("signed").target

      assert_nil reloaded_tag.author
      assert_equal :unsigned, reloaded_tag.verification_status
    end

    test "returns verified signature status if tag author has setting enabled" do
      @user.set_commit_verification_status_state(actor: @user, state: "enabled")

      assert_equal :verified, @signed_tag.verification_status
      assert_equal :unverified, @smime_tag.verification_status
      assert_equal :unverified, @unsigned_tag.verification_status
    end
  end
end
