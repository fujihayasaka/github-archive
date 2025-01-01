# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class SpokesAPIClientTest < GitHub::TestCase
  include PushTestHelper
  include DogstatsTestHelpers

  fixtures do
    @repo = create :repository, from_example: :repository_test_simple

    @master_oid = @repo.spokes_api.resolve_object(object_name: "refs/heads/master")
    @annotated_oid = @repo.spokes_api.resolve_object(object_name: "refs/tags/v1")
    @tag_oid = @repo.spokes_api.resolve_object(object_name: "refs/tags/v2")

    example_repo_snapshot
  end

  setup do
    Spokesd.enable_spokesd
    example_repo_restore

    # These connection objects are memoized, which can keep around stale references to instances of GitHub.dogstats.
    # We need a fresh one each time, since DogstatsTestHelpers uses a different instance for GitHub.dogstats in each test.
    SpokesAPI::Connection.instance_variable_set(:@client, nil) # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods
    SpokesAPI::Connection.instance_variable_set(:@connection, nil) # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods
    SpokesAPI::Connection.instance_variable_set(:@connection_for_streaming, nil)# rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods

    @client = SpokesAPI::Client.for_repository(@repo.id, network_id: @repo.network_id, context: @repo.spokes_api_context)
  end

  context "resolve_object" do
    test "raises for missing object_name" do
      assert_raises TypeError do
        @client.resolve_object(object_name: nil)
      end
    end

    test "returns nil on .." do
      @client.client.objects.expects(:resolve_object).never
      assert_nil @client.resolve_object(object_name: "..")
    end

    test "returns the oid when .. is in the path" do
      @client.client.objects.stubs(resolve_object: stub("response", error: nil, data: stub("ResolveObjectResponse", oid: stub("types.ObjectID", id: "success"))))
      assert_equal "success", @client.resolve_object(object_name: "main:dir/file..txt")
    end

    test "returns the oid on a valid oid" do
      oid = "bb7f9d7da836d8a0839ecf4b0dd7add0b7ebe131"

      assert_equal oid, @client.resolve_object(object_name: oid)
    end

    test "returns a resolved oid for a valid ref" do
      oid = @client.resolve_object(object_name: "refs/heads/master")
      assert_equal "63611721afd41f58f801d66e543d8288b4c5eb44", oid
    end

    test "returns nil for an unknown revision" do
      assert_nil @client.resolve_object(object_name: "refs/heads/not_found")
    end
  end

  context "read_objects" do
    test "empty list of oids" do
      assert_raises SpokesAPI::InvalidArgument do
        @client.read_objects(oids: [], types: [])
      end
    end

    test "retrieve a commit" do
      resp = @client.read_objects(oids: ["c1800491d95c42b4e96fb83f31fe8d9230c62907"], types: ["commit"])
      assert_equal 1, resp.objects.size
      o = resp.objects[0]
      assert_equal "c1800491d95c42b4e96fb83f31fe8d9230c62907", o.object.oid.id
      assert_equal :TYPE_COMMIT, o.object.type
      assert_equal "496d6428b9cf92981dc9495211e6e1120fb6f2ba", o.commit_object.tree_oid.id
      assert_equal "rick", o.commit_object.committer.name
      assert_equal "technoweenie@gmail.com", o.commit_object.committer.email
      assert_equal "rick", o.commit_object.author.name
      assert_equal "technoweenie@gmail.com", o.commit_object.author.email
      assert_equal "initial\n", o.commit_object.message

      assert_dogstats_distribution(1, "gh.faraday_client.dist_time", tags: ["path:/twirp/github.spokes.objects.v1.ObjectsAPI/ReadObjects"])
    end

    test "retrieve a tag" do
      resp = @client.read_objects(oids: [@annotated_oid], types: ["tag"])
      assert_equal 1, resp.objects.size
      o = resp.objects[0]
      assert_equal @annotated_oid, o.object.oid.id
      assert_equal :TYPE_TAG, o.object.type
      assert_equal "rick", o.tag_object.tagger.name
      assert_equal "technoweenie@gmail.com", o.tag_object.tagger.email
      assert_equal "v1", o.tag_object.name
      assert_equal "initial release\n", o.tag_object.message
      assert_equal :TYPE_COMMIT, o.tag_object.target.type
    end

    test "retrieve a blob" do
      resp = @client.read_objects(oids: ["78981922613b2afb6025042ff6bd878ac1994e85"], types: ["blob"])
      assert_equal 1, resp.objects.size
      o = resp.objects[0]
      assert_equal "78981922613b2afb6025042ff6bd878ac1994e85", o.object.oid.id
      assert_equal :TYPE_BLOB, o.object.type
      assert_equal 2, o.object.size
      assert_equal "a\n", o.blob_object.data
    end

    test "retrieve a tree" do
      resp = @client.read_objects(oids: ["a38e8ab7e857af7a7ac6f49fa3d3821f26fedca8"], types: ["tree"])
      assert_equal 1, resp.objects.size
      o = resp.objects[0]
      assert_equal "a38e8ab7e857af7a7ac6f49fa3d3821f26fedca8", o.object.oid.id
      assert_equal :TYPE_TREE, o.object.type
      assert_equal 1, o.tree_object.entries.size
      te = o.tree_object.entries[0]
      assert_equal "422c2b7ab3b3c668038da977e4e93a5fc623169c", te.object.oid.id
      assert_equal :TYPE_BLOB, te.object.type
      assert_equal "a", te.path.name
      assert_equal 33188, te.mode.mode
    end

    test "retrieve a tree with no tree entries" do
      resp = @client.read_objects(
        oids: ["a38e8ab7e857af7a7ac6f49fa3d3821f26fedca8"],
        types: ["tree"],
        tree_object_options: GitHub::Spokes::Proto::Objects::V1::TreeObjectOptions.new(max_tree_entries: 0))

      assert_equal 1, resp.objects.size
      o = resp.objects[0]
      assert_equal "a38e8ab7e857af7a7ac6f49fa3d3821f26fedca8", o.object.oid.id
      assert_equal :TYPE_TREE, o.object.type
      assert_equal 0, o.tree_object.entries.size
    end
  end

  test "returns all blobs for a repository based on a list of ref updates" do
    default_ref_update = push_change(@repo, "blob1")
    new_ref_update = push_change(@repo, "blob2", "develop", create_branch: true)

    ref_updates = [{
      ref_name: new_ref_update[:ref_name],
      previous_ref_oid: default_ref_update[:previous_ref_oid],
      current_ref_oid: new_ref_update[:current_ref_oid],
    }]

    result = @client.list_historical_reachable_blobs(reference_updates: ref_updates, cursor: nil)

    assert_equal 2, result.reachable_blobs.size
    assert_equal "blob2", result.reachable_blobs[0].path.name
    assert_equal "blob1", result.reachable_blobs[1].path.name
    refute result.next_cursor
  end

  test "returns newly reachable blobs for a fork repository based on a list of ref updates" do
    default_ref_update = push_change(@repo, "blob1")

    forker = create(:user)
    fork_repo = create(:fork_repository, forker: forker, fork_repo: @repo)
    fork_client = SpokesAPI::Client.for_repository(fork_repo.id, network_id: fork_repo.network_id, context: fork_repo.spokes_api_context)

    new_ref_update = push_change(fork_repo, "blob2", "develop", create_branch: true)

    ref_updates = [{
      ref_name: new_ref_update[:ref_name],
      previous_ref_oid: default_ref_update[:previous_ref_oid],
      current_ref_oid: new_ref_update[:current_ref_oid],
    }]

    result = fork_client.list_newly_reachable_blobs(reference_updates: ref_updates, cursor: nil, base_repository_id: @repo.id)

    assert_equal 1, result.reachable_blobs.size
    assert_equal "blob2", result.reachable_blobs[0].path.name
    refute result.next_cursor
  end

  test "returns commits for a repository based on a list of ids" do
    ref_update = push_change(@repo, "blob1")

    result = @client.list_commits_for_ids(oids: [ref_update[:current_ref_oid]], cursor: nil)

    assert_equal 1, result.commits.size
    assert_equal ref_update[:current_ref_oid], result.commits[0].oid.id
    refute result.next_cursor
  end

  test "returns commits for a repository based on a single revision" do
    ref_update = push_change(@repo, "blob1")
    ref_update2 = push_change(@repo, "blob2")
    ref_update3 = push_change(@repo, "blob3", "develop", create_branch: true)
    ref_update4 = push_change(@repo, "blob4", "develop")
    ref_update5 = push_change(@repo, "blob5")

    result = @client.list_commits_for_revisions(revisions: ["#{ref_update[:current_ref_oid]}..#{ref_update4[:current_ref_oid]}"], cursor: nil)

    assert_equal 3, result.commits.size
    assert_equal ref_update4[:current_ref_oid], result.commits[0].oid.id
    assert_equal ref_update3[:current_ref_oid], result.commits[1].oid.id
    assert_equal ref_update2[:current_ref_oid], result.commits[2].oid.id
    refute result.next_cursor

    result = @client.list_commits_for_revisions(revisions: ["#{ref_update[:current_ref_oid]}..#{ref_update5[:current_ref_oid]}"], cursor: nil)

    assert_equal 2, result.commits.size
    assert_equal ref_update5[:current_ref_oid], result.commits[0].oid.id
    assert_equal ref_update2[:current_ref_oid], result.commits[1].oid.id
    refute result.next_cursor
  end

  test "returns commits for a repository based on a list of revisions" do
    ref_updates = [
      push_change(@repo, "blob1"),
      push_change(@repo, "blob2"),
      push_change(@repo, "blob3", "develop", create_branch: true),
      push_change(@repo, "blob4", "develop"),
      push_change(@repo, "blob5")
    ]

    result = @client.list_commits_for_revisions(
      revisions: [
        "#{ref_updates[0][:current_ref_oid]}..#{ref_updates[3][:current_ref_oid]}",
        "#{ref_updates[0][:current_ref_oid]}..#{ref_updates[4][:current_ref_oid]}"
      ],
      cursor: nil
    )

    assert_equal 4, result.commits.size
    result_commit_oids = result.commits.map { |commit| commit.oid.id }
    ref_update_commit_oids = ref_updates.map { |ref_update| ref_update[:current_ref_oid] }
    assert (result_commit_oids - ref_update_commit_oids).empty?
    refute result.next_cursor
  end

  test "returns all reachable commits for a repository based on a list of ref updates" do
    default_ref_update = push_change(@repo, "blob1")
    new_ref_update = push_change(@repo, "blob2", "develop", create_branch: true)

    ref_updates = [{
      ref_name: new_ref_update[:ref_name],
      previous_ref_oid: default_ref_update[:previous_ref_oid],
      current_ref_oid: new_ref_update[:current_ref_oid],
    }]

    result = @client.list_historical_commits(reference_updates: ref_updates, cursor: nil)

    assert_equal 2, result.commits.size
    assert_equal new_ref_update[:current_ref_oid], result.commits[0].oid.id
    assert_equal default_ref_update[:current_ref_oid], result.commits[1].oid.id
    refute result.next_cursor
  end

  test "returns newly reachable commits for a fork repository based on a list of ref updates" do
    default_ref_update = push_change(@repo, "blob1")

    forker = create(:user)
    fork_repo = create(:fork_repository, forker: forker, fork_repo: @repo)
    fork_client = SpokesAPI::Client.for_repository(fork_repo.id, network_id: fork_repo.network_id, context: fork_repo.spokes_api_context)

    new_ref_update = push_change(fork_repo, "blob2", "develop", create_branch: true)

    ref_updates = [{
      ref_name: new_ref_update[:ref_name],
      previous_ref_oid: default_ref_update[:previous_ref_oid],
      current_ref_oid: new_ref_update[:current_ref_oid],
    }]

    result = fork_client.list_newly_reachable_commits(reference_updates: ref_updates, cursor: nil, base_repository_id: @repo.id)

    assert_equal 1, result.commits.size
    assert_equal ref_updates.first[:current_ref_oid], result.commits[0].oid.id
    refute result.next_cursor
  end

  test "gets default branch of the repository" do
    result = @client.get_default_branch
    assert_equal "refs/heads/master", result

    non_utf_branch = String.new("\xBE\xC8\xB3\xE7\xC7\xCF\xBC\xBC\xBF\xE4", encoding: Encoding.find("ASCII-8BIT")) # 안녕하세요 (annyeonghaseyo) = hello (in Korean)
    push_change(@repo, "blob2", non_utf_branch, create_branch: true)
    @repo.update_default_branch_spokes("refs/heads/#{non_utf_branch}")

    result = @client.get_default_branch
    assert_equal "refs/heads/#{non_utf_branch.dup.force_encoding("UTF-8")}", result
  end

  context "create_tag" do
    test "creates tag" do
      tagger = {
        name: "A U Thor",
        email: "test@example.com",
        time: Time.now
      }
      tag_oid = @client.with_transaction do
        @client.create_tag(name: "test-tag", target: @master_oid, message: "This is my tag\n", tagger:)
      end
      refute_nil tag_oid

      # Read the data back again
      tag_data = @client.read_objects(oids: [tag_oid], types: ["tag"]).objects[0]
      assert_equal "A U Thor", tag_data.tag_object.tagger.name
      assert_equal "test@example.com", tag_data.tag_object.tagger.email
      assert_equal "test-tag", tag_data.tag_object.name
      assert_equal "This is my tag\n", tag_data.tag_object.message
      assert_equal @master_oid, tag_data.tag_object.target.oid.id
      assert_equal :TYPE_COMMIT, tag_data.tag_object.target.type
    end

    test "with invalid Git timestamp" do
      tagger = {
        name: "A U Thor",
        email: "test@example.com",
        time: Time.new(1969, 7, 20, 12, 17, 0, "-07:00")
      }
      assert_raises SpokesAPI::InvalidArgument do
        @client.with_transaction do
          @client.create_tag(name: "test-tag", target: @master_oid, message: "This is my tag\n", tagger:)
        end
      end
    end

    test "with bad target OID" do
      tagger = {
        name: "A U Thor",
        email: "test@example.com",
        time: Time.now
      }
      assert_raises SpokesAPI::NotFound do
        @client.with_transaction do
          @client.create_tag(name: "test-tag", target: "0000000000000000000000000000000000000000", message: "This is my tag\n", tagger:)
        end
      end
    end

    test "with missing target OID" do
      tagger = {
        name: "A U Thor",
        email: "test@example.com",
        time: Time.now
      }
      assert_raises SpokesAPI::NotFound do
        @client.with_transaction do
          @client.create_tag(name: "test-tag", target: "0123456789012345678901234567890123456789", message: "This is my tag\n", tagger:)
        end
      end
    end

    test "with nil message" do
      tagger = {
        name: "A U Thor",
        email: "test@example.com",
        time: Time.now
      }
      tag_oid = @client.with_transaction do
        @client.create_tag(name: "test-tag", target: @master_oid, message: nil, tagger:)
      end

      # Read the data back again
      tag_data = @client.read_objects(oids: [tag_oid], types: ["tag"]).objects[0]
      assert_equal "A U Thor", tag_data.tag_object.tagger.name
      assert_equal "test@example.com", tag_data.tag_object.tagger.email
      assert_equal "test-tag", tag_data.tag_object.name
      assert_equal "", tag_data.tag_object.message
      assert_equal @master_oid, tag_data.tag_object.target.oid.id
      assert_equal :TYPE_COMMIT, tag_data.tag_object.target.type
    end

    test "with non-ASCII characters" do
      tagger = {
        name: "A U Thor 😄",
        email: "test@example.com",
        time: Time.now
      }
      tag_oid = @client.with_transaction do
        @client.create_tag(name: "test-tag", target: @master_oid, message: "👋 안녕하세요\n", tagger:) # 안녕하세요 (annyeonghaseyo) = hello (in Korean)
      end

      # Read the data back again
      tag_data = @client.read_objects(oids: [tag_oid], types: ["tag"]).objects[0]
      assert_equal "A U Thor 😄".b, tag_data.tag_object.tagger.name
      assert_equal "test@example.com", tag_data.tag_object.tagger.email
      assert_equal "test-tag", tag_data.tag_object.name
      assert_equal "👋 안녕하세요\n".b, tag_data.tag_object.message
      assert_equal @master_oid, tag_data.tag_object.target.oid.id
      assert_equal :TYPE_COMMIT, tag_data.tag_object.target.type
    end
  end

  context "resolve_references" do
    test "with valid references" do
      result = @client.resolve_references(%w[refs/heads/master refs/tags/v1])
      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs/tags/v1", @annotated_oid]
        ],
        result
      )

      assert_dogstats_distribution(1, "gh.faraday_client.dist_time", tags: ["path:/twirp/github.spokes.references.v1.ReferencesAPI/ResolveReferences"])
    end

    test "with missing ref" do
      assert_equal [["refs/heads/foobar", nil]], @client.resolve_references(%w[refs/heads/foobar])
    end

    test "with duplicate slashes" do
      @repo.heads.create("branch/with/so/many/slashes", @tag_oid, @repo.owner)
      result = @client.resolve_references(%w[
        refs/heads/master
        refs//heads/master
        refs/heads//master
        refs/heads////master
        refs////heads////master
        refs/tags/v1
        refs/tags////v1
        refs////tags////v1
        refs/heads/branch/with/so/many/slashes
        refs//heads/branch/with/so/many/slashes
        refs/heads/branch//with/so/many/slashes
        refs///heads/branch///with/so/many///slashes
      ])

      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs//heads/master", @master_oid],
          ["refs/heads//master", @master_oid],
          ["refs/heads////master", @master_oid],
          ["refs////heads////master", @master_oid],
          ["refs/tags/v1", @annotated_oid],
          ["refs/tags////v1", @annotated_oid],
          ["refs////tags////v1", @annotated_oid],
          ["refs/heads/branch/with/so/many/slashes", @tag_oid],
          ["refs//heads/branch/with/so/many/slashes", @tag_oid],
          ["refs/heads/branch//with/so/many/slashes", @tag_oid],
          ["refs///heads/branch///with/so/many///slashes", @tag_oid],
        ],
        result,
        "failed to match libgit2's slash compression behavior"
      )
    end

    test "with partial success" do
      result = @client.resolve_references(%w[
        refs/heads/master
        refs/heads/foobar
        refs/tags/v1
      ])
      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs/heads/foobar", nil],
          ["refs/tags/v1", @annotated_oid]
        ],
        result
      )
      assert_equal [["refs/heads/foobar", nil]], @client.resolve_references(%w[refs/heads/foobar])
    end

    test "can see hidden refs" do
      @repo.refs.create("refs/__gh__/hidden", @tag_oid, @repo.owner)
      assert_equal [["refs/__gh__/hidden", @tag_oid]], @client.resolve_references(%w[refs/__gh__/hidden])
    end

    test "can handle multibyte refs" do
      @repo.refs.create("refs/tags/１", @tag_oid, @repo.owner)
      result = @client.resolve_references(%w[refs/heads/master refs/tags/１])
      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs/tags/１", @tag_oid]
        ],
        result
      )
    end

    test "never mutates args" do
      refs = %w[
        refs/heads/some-branch
        20211028_リリ
        refs/special/////foo
      ]
      backup = refs.map(&:dup) # deep_dup
      @client.resolve_references(refs)
      assert_equal(backup, refs, "`refs` was modified by the call to `resolve_references`!")
    end

    test "can handle inputs with newlines" do
      refs = [
        "refs/tags/v1",
        "refs/heads/master\nrefs/tags/v2"
      ]
      result = @client.resolve_references(refs)
      assert_equal(
        [
          ["refs/tags/v1", @annotated_oid],
          ["refs/heads/master\nrefs/tags/v2", nil]
        ],
        result
      )
    end
  end

  context "transaction state" do
    test "uses Spokes API context" do
      @repo.spokes_api_context.stubs(:transaction_state).returns("123")

      GitHub::Spokes::Proto::References::V1::ReferencesAPIClient.any_instance
        .expects(:get_default_branch)
        .with do |req, _|
          assert_equal "123", req.dig(:request_context, :transaction_state)
          true
        end
        .twice.returns(Twirp::ClientResp.new(
          data: GitHub::Spokes::Proto::References::V1::GetDefaultBranchResponse.new(
            reference: GitHub::Spokes::Proto::Types::V1::Reference.new(name: "refs/heads/some/branch"),
          ),
          error: nil)
        )

      @repo.spokes_api.get_default_branch
      @repo.spokes_api(timeout: 10).get_default_branch # Context preserved across client instances
    end

    test "defaults to nil" do
      @repo.spokes_api_context.stubs(:transaction_state).returns(nil)

      GitHub::Spokes::Proto::References::V1::ReferencesAPIClient.any_instance
        .stubs(:get_default_branch)
        .with do |req, _|
          assert_nil req.dig(:request_context, :transaction_state)
          true
        end
        .returns(Twirp::ClientResp.new(
          data: GitHub::Spokes::Proto::References::V1::GetDefaultBranchResponse.new(
            reference: GitHub::Spokes::Proto::Types::V1::Reference.new(name: "refs/heads/some/branch"),
          ),
          error: nil)
        )

      @repo.spokes_api.get_default_branch
    end
  end

  context "get_blob_contents_streaming"  do
    test "returns the blob contents" do
      result = @client.get_blob_contents_streaming("422c2b7ab3b3c668038da977e4e93a5fc623169c")
      assert_equal "a\nb\n", result

      assert_dogstats_distribution(1, "gh.faraday_client.dist_time", tags: ["path:/streaming/v1/repositories/:repository_id/blobs/:oid"])
    end

    test "raises expected error when the response is a string error message" do
      assert_equal SpokesAPI::Connection.connection_for_streaming.get("/streaming/v1/repositories/#{@repo.id}/blobs/").body.strip, "404 page not found"

      assert_raises SpokesAPI::NotFound do
        @client.get_blob_contents_streaming("")
      end

      assert_dogstats_distribution(2, "gh.faraday_client.dist_time", tags: ["path:/streaming/v1/repositories/:repository_id/blobs/:oid"])
    end

    test "raises expected error when the response is a JSON twirp error" do
      bad_oid = "123foo"
      assert_equal SpokesAPI::Connection.connection_for_streaming.get("/streaming/v1/repositories/#{@repo.id}/blobs/#{bad_oid}").body, "{\"code\":\"invalid_argument\",\"msg\":\"blobID must provide a valid blob ID\",\"meta\":{\"argument\":\"blobID\"}}"

      assert_raises SpokesAPI::InvalidArgument do
        @client.get_blob_contents_streaming(bad_oid)
      end

      assert_dogstats_distribution(2, "gh.faraday_client.dist_time", tags: ["path:/streaming/v1/repositories/:repository_id/blobs/:oid"])
    end
  end

  context "transactions api" do
    context "begin_transaction" do
      test "updates transaction_state" do
        old_transaction_state = @repo.spokes_api_context.transaction_state

        @client.begin_transaction

        new_transaction_state = @repo.spokes_api_context.transaction_state
        refute_nil new_transaction_state
        refute_equal old_transaction_state, new_transaction_state
      end

      test "refuses to begin nested transaction" do
        @client.begin_transaction

        assert_raises SpokesAPI::InvalidArgument do
          @client.begin_transaction
        end
      end
    end

    context "commit_transaction" do
      test "updates transaction_state" do
        # Begin a transaction
        @client.begin_transaction
        old_transaction_state = @repo.spokes_api_context.transaction_state

        @client.commit_transaction

        new_transaction_state = @repo.spokes_api_context.transaction_state
        refute_nil new_transaction_state
        refute_equal old_transaction_state, new_transaction_state
      end

      test "refuses to commit with no transaction" do
        assert_raises SpokesAPI::InvalidArgument do
          @client.commit_transaction
        end
      end
    end

    context "rollback_transaction" do
      test "updates transaction_state" do
        @client.begin_transaction
        old_transaction_state = @repo.spokes_api_context.transaction_state

        @client.rollback_transaction

        new_transaction_state = @repo.spokes_api_context.transaction_state
        refute_nil new_transaction_state
        refute_equal old_transaction_state, new_transaction_state
      end

      test "refuses to roll back with no transaction" do
        assert_raises SpokesAPI::InvalidArgument do
          @client.rollback_transaction
        end
      end
    end

    context "with_transaction" do
      test "executes transaction" do
        @client.expects(:begin_transaction).once
        @client.expects(:commit_transaction).once
        @client.expects(:rollback_transaction).never

        @client.with_transaction {}
      end

      test "rolls back on error" do
        @client.expects(:begin_transaction).once
        @client.expects(:commit_transaction).never
        @client.expects(:rollback_transaction).once

        assert_raises "boom" do
          @client.with_transaction { raise "boom" }
        end
      end

      test "fails if transaction already exists" do
        @client.begin_transaction

        @client.expects(:commit_transaction).never
        @client.expects(:rollback_transaction).never

        assert_raises SpokesAPI::InvalidArgument do
          @client.with_transaction {}
        end
      end

      test "fails commit if transaction committed in block" do
        @client.expects(:rollback_transaction).never

        assert_raises SpokesAPI::InvalidArgument do
          @client.with_transaction { @client.commit_transaction }
        end
      end

      test "fails rollback if transaction rolled back in block with error" do
        @client.expects(:commit_transaction).never

        assert_raises SpokesAPI::InvalidArgument do
          @client.with_transaction do
            @client.rollback_transaction
            raise "boom"
          end
        end
      end
    end
  end

  def push_change(repository, path, branch_name = repository.default_branch, create_branch: false)
    push = push_changes(repository: repository, branch_name: branch_name, create_branch: create_branch, changes: [
      { path: path, content: "" }
    ])

    {
      ref_name: push.ref,
      previous_ref_oid: push.before,
      current_ref_oid: push.after,
    }
  end
end
