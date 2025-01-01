# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadPushPayloadTest < GitHub::TestCase
  fixtures do
    @holman  = create(:user, login: "holman", email: "holman@github.com")
    @defunkt = create(:user, login: "defunkt", email: "defunkt@github.com")

    @repo = create :repository, owner: @holman
    @diff_repo = create :repository, owner: @holman
    @tag_blob_repo = create :repository, owner: @holman
  end

  setup do
    example_repo :post_receive_job_test, @repo
    example_repo :smart_diff_test, @diff_repo
    example_repo :tag_point_to_blob, @tag_blob_repo

    @event = Hook::Event::PushEvent.new({
        repo: @repo,
        before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
        after: "63611721afd41f58f801d66e543d8288b4c5eb44",
        ref: "refs/heads/master",
        pusher: @defunkt,
      })
  end

  context "v3" do
    context "when creating a ref" do
      test "generates the expected payload" do
        @event.before = GitHub::NULL_OID
        payload = Hook::Payload::PushPayload.new @event

        assert payload.created?
        refute payload.deleted?

        version = payload.to_hash

        assert_equal "0000000000000000000000000000000000000000", version[:before]
        assert_equal "63611721afd41f58f801d66e543d8288b4c5eb44", version[:after]
        assert_equal "refs/heads/master", version[:ref]
        assert_equal true, version[:created]
        assert_equal false, version[:deleted]

        assert_equal "63611721afd41f58f801d66e543d8288b4c5eb44", version[:head_commit][:id]
        assert_equal "a38e8ab7e857af7a7ac6f49fa3d3821f26fedca8", version[:head_commit][:tree_id]
        assert_equal true, version[:head_commit][:distinct]

        assert_handle_match "defunkt", version[:pusher][:name]
        assert_equal "defunkt@github.com", version[:pusher][:email]
      end
    end

    context "when the push event is the creation of a lightweight tag ref pointing to an annotated tag" do
      test "generates a payload including head_commit for the tag's target commit" do
        commit_oid = @repo.default_oid
        annotated_tag_oid = @repo.rpc.create_tag_annotation("annotated_tag", commit_oid, message: "hello", tagger: {
          email: @holman.git_author_email,
          name: @holman.git_author_name,
          time: @holman.time_zone.now.iso8601,
        })

        payload = Hook::Payload::PushPayload.new(
          Hook::Event::PushEvent.new({
            repo: @repo,
            before: GitHub::NULL_OID,
            after: annotated_tag_oid,
            ref: "refs/tags/lightweight_tag",
            pusher: @holman
          })
        ).to_hash

        assert_equal(annotated_tag_oid, payload.fetch(:after))
        # This is a case where after != head_commit id
        refute_equal(payload.fetch(:after), payload.fetch(:head_commit).fetch(:id))

        assert_equal({
          id: "3c2644823caa63b9de90e80872d6c6ab0fd13c01",
          tree_id: "2ea594ee98a5e27c3eb23fedac46be83772ed38c",
          distinct: true,
          message: "Update ruby hello world output",
          timestamp: "2022-08-25T13:23:42-09:00",
          url: "https://github.com/#{@repo.nwo}/commit/3c2644823caa63b9de90e80872d6c6ab0fd13c01",
          author: {
            name: "rnkaufman",
            email: "="
          },
          committer: {
            name: "GitHub",
            email: "noreply@github.com"
          },
          added: [],
          removed: [],
          modified: ["ruby_file.rb"]
        }, payload.fetch(:head_commit))
      end
    end

    context "when deleting a ref" do
      test "generates the expected payload" do
        @event.after = GitHub::NULL_OID
        payload = Hook::Payload::PushPayload.new @event

        assert payload.deleted?
        refute payload.created?

        version = payload.to_hash

        assert_equal "c1800491d95c42b4e96fb83f31fe8d9230c62907", version[:before]
        assert_equal "0000000000000000000000000000000000000000", version[:after]
        assert_equal "refs/heads/master", version[:ref]
        assert_equal false, version[:created]
        assert_equal true, version[:deleted]

        assert_handle_match "defunkt", version[:pusher][:name]
        assert_equal "defunkt@github.com", version[:pusher][:email]
      end
    end

    context "when pushing commits to an existing ref" do
      test "generates the expected payload" do
        payload = Hook::Payload::PushPayload.new @event

        refute payload.created?
        refute payload.deleted?

        version = payload.to_hash

        assert_equal "c1800491d95c42b4e96fb83f31fe8d9230c62907", version[:before]
        assert_equal "63611721afd41f58f801d66e543d8288b4c5eb44", version[:after]
        assert_equal "refs/heads/master", version[:ref]
        assert_equal false, version[:created]
        assert_equal false, version[:deleted]
        assert_equal 2, version[:commits].count

        assert_equal %w(7fd43660b371e21bc2aa306fad0fbff59829aae3 63611721afd41f58f801d66e543d8288b4c5eb44),
          version[:commits].map { |c| c[:id] }
        assert_equal %w(aaff74984cccd156a469afa7d9ab10e4777beb24 a38e8ab7e857af7a7ac6f49fa3d3821f26fedca8),
          version[:commits].map { |c| c[:tree_id] }
        assert_equal ["add a", "add b"], version[:commits].map { |c| c[:message] }

        assert_handle_match "defunkt", version[:pusher][:name]
        assert_equal "defunkt@github.com", version[:pusher][:email]
      end

      context "generates the correct diffs" do
        test "for diff with addition, removal and modification" do
          push_event = Hook::Event::PushEvent.new({
            repo: @repo,
            before: "7fd43660b371e21bc2aa306fad0fbff59829aae3",
            after: "e5d54f3fd3a8d7bf301a8c07f9ec579fc5457214",
            ref: "refs/heads/topic-fast-forward",
            pusher: @defunkt,
          })
          payload = Hook::Payload::PushPayload.new push_event
          version = payload.to_hash

          assert_equal 3, version[:commits].count

          commit = version[:commits].shift
          assert_equal 0, commit[:added].size
          assert_equal 0, commit[:removed].size
          assert_equal 1, commit[:modified].size
          assert_equal "a", commit[:modified].first

          commit = version[:commits].shift
          assert_equal 1, commit[:added].size
          assert_equal 0, commit[:removed].size
          assert_equal 0, commit[:modified].size
          assert_equal "c", commit[:added].first

          commit = version[:commits].shift
          assert_equal 0, commit[:added].size
          assert_equal 1, commit[:removed].size
          assert_equal 0, commit[:modified].size
          assert_equal "a", commit[:removed].first
        end
      end

      test "for diff with rename" do
        parent = "a270ea0fdfba2bd5a33934e5184784cddce87f38"
        head_commit = @diff_repo.commits.find(parent)
        head_commit_tree = @diff_repo.rpc.read_trees([head_commit.tree_oid]).first
        blob_hash = head_commit_tree["entries"].values.find { |e| e["type"] == "blob" }
        blob_name = blob_hash["name"]
        blob_oid = blob_hash["oid"]
        blob_data = @diff_repo.rpc.read_blobs([blob_oid]).first["data"]

        metadata = {
          message: "test",
          committer: { name: "Jake Boxer", email: "jake@github.com" },
        }
        new_head = @diff_repo.commits.create(metadata, parent) do |files|
          files.remove(blob_name)
          files.add("moved/#{blob_name}", blob_data)
        end

        push_event = Hook::Event::PushEvent.new({
          repo: @diff_repo,
          before: "a270ea0fdfba2bd5a33934e5184784cddce87f38",
          after: new_head.oid,
          ref: "refs/heads/master",
          pusher: @defunkt,
        })
        payload = Hook::Payload::PushPayload.new push_event
        version = payload.to_hash

        assert_equal 1, version[:commits].count

        commit = version[:commits].shift
        assert_equal 1, commit[:added].size
        assert_equal 1, commit[:removed].size
        assert_equal 0, commit[:modified].size
        assert_equal "big-one", commit[:removed].first
        assert_equal "moved/big-one", commit[:added].first
      end
    end

    context "when the push is forced" do
      test "generates the expected payload" do
        @event.ref    = "refs/heads/topic-force-push"
        @event.before = "63611721afd41f58f801d66e543d8288b4c5eb44"
        @event.after  = "02d44624a600ee7afd17785327a5cbc59b2e0571"

        payload = Hook::Payload::PushPayload.new @event

        refute payload.created?
        refute payload.deleted?
        assert payload.non_fast_forward?

        version = payload.to_hash

        assert_equal "63611721afd41f58f801d66e543d8288b4c5eb44", version[:before]
        assert_equal "02d44624a600ee7afd17785327a5cbc59b2e0571", version[:after]
        assert_equal "refs/heads/topic-force-push", version[:ref]
        assert_equal false, version[:created]
        assert_equal false, version[:deleted]
        assert_equal true, version[:forced]
        assert_equal 3, version[:commits].count

        expected_commits = %w(
          7131329d0834e23c2e1c7e73234b1c8381af9a80
          db1296776ed3577724033671af8b10ef8b402ef1
          02d44624a600ee7afd17785327a5cbc59b2e0571
        )
        assert_equal expected_commits, version[:commits].map { |c| c[:id] }
      end
    end

    context "when the pusher is unknown" do
      test "generates the expected payload" do
        unknown_pusher_event = Hook::Event::PushEvent.new(@event.attributes)
        unknown_pusher_event.pusher = nil
        payload = Hook::Payload::PushPayload.new unknown_pusher_event

        version = payload.to_hash

        assert_equal "none", version[:pusher][:name]
        refute version[:pusher].key?(:email)
      end
    end

    context "when pushing a tag that points to a blob" do
      test "generates the expected payload without a head commit" do
        event = Hook::Event::PushEvent.new({
            repo: @tag_blob_repo,
            before: "0000000000000000000000000000000000000000",
            after: "5cb01161bb4c37b7ff88da8423bf74c4b36d0b2f",
            ref: "refs/tags/my-blog-tag",
            pusher: @defunkt,
          })

        payload = Hook::Payload::PushPayload.new event

        version = payload.to_hash
        assert_equal "0000000000000000000000000000000000000000", version[:before]
        assert_equal "5cb01161bb4c37b7ff88da8423bf74c4b36d0b2f", version[:after]
        assert_equal "refs/tags/my-blog-tag", version[:ref]
        assert_equal true, version[:created]
        assert_equal false, version[:deleted]

        assert_nil   version[:head_commit]

        assert_handle_match "defunkt", version[:pusher][:name]
        assert_equal "defunkt@github.com", version[:pusher][:email]
      end
    end

    context "when include_git_data is false" do
      test "generates payload with only mysql data" do
        payload = Hook::Payload::PushPayload.new @event, include_git_data: false

        version = payload.to_hash

        assert version.has_key?(:repository)
        assert version.has_key?(:pusher)
        assert version.has_key?(:sender)

        refute version.has_key?(:created)
        refute version.has_key?(:deleted)
        refute version.has_key?(:forced)
        refute version.has_key?(:base_ref)
        refute version.has_key?(:compare)
        refute version.has_key?(:commits)
        refute version.has_key?(:head_commit)
      end
    end
  end

  test "returns a full user object and legacy fields for repository owner" do
    payload = Hook::Payload::PushPayload.new @event
    version = payload.to_hash

    # Assert the fields provided in a standard v3 user object
    assert_equal @holman.id, version[:repository][:owner][:id]
    assert_equal "holman", version[:repository][:owner][:login]
    assert_equal "User", version[:repository][:owner][:type]

    # Assert the legacy user fields provided in the repository owner object
    assert_equal "holman", version[:repository][:owner][:name]
    assert_equal "holman@github.com", version[:repository][:owner][:email]
  end

  test "returns repo pushed_at and created_at in unix time" do
    now = Time.now
    @repo.update(pushed_at: now, created_at: now)

    payload = Hook::Payload::PushPayload.new @event
    version = payload.to_hash

    assert_equal now.to_i, version[:repository][:pushed_at]
    assert_equal now.to_i, version[:repository][:created_at]
  end

  test "custom properties are part of the payload" do
    org = create :organization
    repo = create :repository, owner: org
    admin = org.admins.first

    env_definition = create :custom_property_definition, source: org, property_name: "env"
    create :custom_property_definition, source: org, property_name: "language", required: true, default_value: "ruby"
    create :custom_property_value, definition: env_definition, target: repo, value: "prod"

    event = Hook::Event::PushEvent.new({
      repo: repo,
      before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
      after: "63611721afd41f58f801d66e543d8288b4c5eb44",
      ref: "refs/heads/master",
      pusher: admin,
    })

    payload = Hook::Payload::PushPayload.new event
    version = payload.to_hash

    assert_equal repo.id, version[:repository][:id]
    assert_equal version[:repository][:custom_properties], { env: "prod", language: "ruby" }
  end

  context "git_only" do
    context "when include_git_data is false" do
      test "returns empty payload" do
        payload = Hook::Payload::PushPayload.new @event, include_git_data: false

        git_only = payload.git_only

        assert_empty git_only
      end
    end

    context "when include_git_data is true" do
      test "returns payload with only git data" do
        payload = Hook::Payload::PushPayload.new @event, include_git_data: true

        git_only = payload.git_only

        refute git_only.has_key?(:repository)
        refute git_only.has_key?(:pusher)
        refute git_only.has_key?(:sender)

        assert git_only.has_key?(:created)
        assert git_only.has_key?(:deleted)
        assert git_only.has_key?(:forced)
        assert git_only.has_key?(:base_ref)
        assert git_only.has_key?(:compare)
        assert git_only.has_key?(:commits)
        assert git_only.has_key?(:head_commit)
      end
    end

    context "when the GitRPC call times out" do
      test "returns empty payload" do
        GitHub::Diff.any_instance.stubs(:load_deltas).raises(GitRPC::Timeout)

        payload = Hook::Payload::PushPayload.new @event, include_git_data: true
        git_only = payload.git_only

        assert_empty git_only[:commits].map { |commit| [commit[:added], commit[:removed]] }.flatten
      end
    end

    context "prefill_users" do
      test "calls Commit.prefill_users" do
        repo = create(:repository, from_example: :simple)

        payload = Hook::Payload::PushPayload.new @event, include_git_data: true

        Commit.expects(:prefill_users)
          .returns([
            create(:commit, repository: repo),
            create(:commit, repository: repo)
          ]).once

        payload.git_only
      end

      test "EMU user is properly returned when users with matching email exist", skip_enterprise: true do
        email = "emutest@enterprise.org"
        emu = create(:emu, email: email)
        emu_business = emu.enterprise_managed_business
        emu_business_org = create :enterprise_linked_organization, business: emu_business, admin: emu

        # Create a duplicate user that has the same email as the enterprise user
        user = create(:user, email: email)

        # Create a webflow user for web authored commit test case
        webflow = create(:user, login: "web-flow", email: GitHub.web_committer_email, name: GitHub.web_committer_name)

        # Verify that user emails are in the expected state
        assert_equal emu.profile.email, email
        assert_equal emu.email, emu_business.add_emu_shortcode_to_emails(email)
        assert_equal user.email, email

        # Ensure we can find the two different users with the same email
        assert_equal user.id, User.find_by_email(email).id
        assert_equal emu.id, User.find_by_email(email, business: emu_business).id

        emu_repo = create(:private_repository, owner: emu_business_org, from_example: :post_receive_job_test)

        event = Hook::Event::PushEvent.new({
          repo: emu_repo,
          before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
          after: "63611721afd41f58f801d66e543d8288b4c5eb44",
          ref: "refs/heads/master",
          pusher: emu,
        })

        payload = Hook::Payload::PushPayload.new event, include_git_data: true

        # We will use the web commit user for committer to set up a web authored commit test case
        payload.stubs(:commits_pushed).returns([
          create(:commit, repository: emu_repo, author_name: emu.name, author_email: email,
            committer_name: GitHub.web_committer_name, committer_email: GitHub.web_committer_email),
          create(:commit, repository: emu_repo, author_name: emu.name, author_email: email,
            committer_name: GitHub.web_committer_name, committer_email: GitHub.web_committer_email)
        ])

        git_only = payload.git_only

        assert git_only.has_key?(:commits)
        assert_equal 2, git_only[:commits].count

        git_only[:commits].each do |commit|
          assert_equal emu.name, commit[:author][:name]
          assert_equal emu.profile.email, commit[:author][:email]
          assert_equal emu.login, commit[:author][:username]
          assert_equal GitHub.web_committer_name, commit[:committer][:name]
          assert_equal GitHub.web_committer_email, commit[:committer][:email]
          assert_equal webflow.login, commit[:committer][:username]
        end
      end

      test "return correct distinct value for commits that are part of a PR merge" do
        ref = @repo.refs.find("topic")
        before = @repo.refs.find("master").target_oid

        commit = ref.append_commit({
          message: "a commit",
          committer: @repo.owner,
        }, @repo.owner)

        pr = create(:pull_request, repository: @repo, head_ref: "topic", base_ref: "master")
        pr.merge

        event = Hook::Event::PushEvent.new({
          repo: @repo,
          before: before,
          after: pr.merge_commit_sha,
          ref: "refs/heads/master",
          pusher: @repo.owner,
        })

        payload = Hook::Payload::PushPayload.new(event, include_git_data: true, merge: true)

        # stub the rpc distinct_commits_pushed call to say the commits are all distinct.
        # this can occurr due to a race condition between pushes and ref deletions.
        payload.stubs(:distinct_commits_pushed).returns(@repo.commits.find([pr.merge_commit_sha, commit.sha]))

        git_only = payload.git_only

        assert git_only.has_key?(:commits)
        assert_equal 2, git_only[:commits].count

        merge_commit = git_only[:commits].find { |c| c[:id] == pr.merge_commit_sha }
        other_commit = git_only[:commits].find { |c| c[:id] != pr.merge_commit_sha }
        assert merge_commit[:distinct]
        refute other_commit[:distinct]
      end
    end
  end

  context "enterprise" do
    test "limits number of commits processed on large push" do
      push_event = Hook::Event::PushEvent.new({
        repo: @repo,
        before: "7fd43660b371e21bc2aa306fad0fbff59829aae3",
        after: "e5d54f3fd3a8d7bf301a8c07f9ec579fc5457214",
        ref: "refs/heads/topic-fast-forward",
        pusher: @defunkt,
      })
      payload_generator = Hook::Payload::PushPayload.new(push_event)
      payload = payload_generator.to_hash

      assert_equal 3, payload[:commits].count

      # stub the LARGE_PUSH_THRESHOLD so we'll be forced to exclude some commits
      Pushes::CommitsHelper.stub_const(:LARGE_PUSH_THRESHOLD, 1) do
        payload_generator = Hook::Payload::PushPayload.new(push_event)
        diff = payload_generator.commits_pushed.first.init_diff

        # PushPayload will call this one for the head commit, but that's it.
        Commit.any_instance.expects(:init_diff).once.returns(diff)

        payload = payload_generator.to_hash
        assert_equal 0, payload[:commits].count
      end
    end
  end
end
