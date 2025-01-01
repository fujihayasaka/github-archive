# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryTopicTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @repo = create(:public_repository)
  end

  test "requires a topic" do
    repo_topic = RepositoryTopic.new(topic: nil)
    refute_predicate repo_topic, :valid?
    assert repo_topic.errors[:topic]
  end

  test "requires a repository" do
    repo_topic = RepositoryTopic.new(repository: nil)
    refute_predicate repo_topic, :valid?
    assert repo_topic.errors[:repository]
  end

  test "requires a user" do
    repo_topic = RepositoryTopic.new(user: nil)
    refute_predicate repo_topic, :valid?
    assert repo_topic.errors[:user]
  end

  test "validates uniqueness of repository-topic combination" do
    existing = create :repository_topic
    duplicate = RepositoryTopic.new(repository: existing.repository, topic: existing.topic, state: :created)
    refute_predicate duplicate, :valid?
    assert_includes duplicate.errors[:repository_id], "has already been taken"
  end

  test "does not validate uniqueness of repository-topic combination when skip_uniqueness_check=true" do
    existing = create(:repository_topic)
    duplicate = build(:repository_topic, repository: existing.repository, topic: existing.topic, state: :created)
    duplicate.skip_uniqueness_check = true
    assert_predicate duplicate, :valid?
  end

  context ".applied_state_values" do
    test "returns values for applied states only" do
      assert_equal RepositoryTopic.applied_state_values, RepositoryTopic::APPLIED_STATE_VALUES
    end
  end

  test "reindexes repository and topic on creation" do
    repo = create(:repository)
    topic = create :topic

    Search.expects(:add_to_search_index).with("repository", repo.id).once
    Search.expects(:add_to_search_index).with("topic", topic.id).once
    reset_job_hash_locks

    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["commit", repo.id] do
      create(:repository_topic, repository: repo, topic: topic)
    end
  end

  test "reindexes repository and topic on update" do
    repo_topic = create(:repository_topic, state: :created)

    Search.expects(:add_to_search_index).with("repository", repo_topic.repository_id).once
    Search.expects(:add_to_search_index).with("topic", repo_topic.topic_id).once
    reset_job_hash_locks

    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["commit", repo_topic.repository_id] do
      repo_topic.state = :suggested
      repo_topic.save
    end
  end

  test "reindexes repository and topic on removing topic from repository" do
    topic = create :topic
    repo_topic = create(:repository_topic, topic: topic)

    # so topic is still in use and does not get deleted, triggering another job to be queued
    create(:repository_topic, topic: topic)

    Search.expects(:add_to_search_index).with("repository", repo_topic.repository_id).once
    Search.expects(:add_to_search_index).with("topic", repo_topic.topic_id).once
    reset_job_hash_locks

    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["commit", repo_topic.repository_id] do
      repo_topic.destroy
    end
  end

  test "does not delete unused flagged topic" do
    topic = create :topic
    repo_topic = create(:repository_topic, topic: topic)

    topic.update(flagged: true)
    assert_predicate topic.reload, :flagged?

    assert_no_difference "Topic.count" do
      repo_topic.destroy
    end
    assert_predicate Topic.where(id: topic.id), :exists?
  end

  test "does not delete still-used topic when removing from a repository" do
    topic = create :topic
    repo_topic1 = create(:repository_topic, topic: topic)
    repo_topic2 = create(:repository_topic, topic: topic)
    assert_no_difference "Topic.count" do
      repo_topic1.destroy
    end
    assert_predicate Topic.where(id: topic.id), :exists?
  end

  test "instruments adding a topic to a repo" do
    user = create(:user)
    org = create :organization, admin: user
    repo = create(:repository, owner: org)
    topic = create :topic, name: "self-driving-cars"

    events = subscribe "repo.add_topic"

    repo_topic = create(:repository_topic,
      topic: topic,
      repository: repo,
      user: user,
      state: :created,
    )

    expected_payload = {
      topic:         "self-driving-cars",
      topic_id:      topic.id,
      state:         "created",
      user:          user.login,
      user_id:       user.id,
      org:           org.to_s,
      org_id:        org.id,
      repository_topic_id: repo_topic.id,
      repo:          repo.name_with_owner,
      repo_id:       repo.id,
      public_repo:   repo.public?,
    }

    assert event = events.pop, "expected an instrumentation event"
    assert_equal expected_payload, event.payload
  end

  # https://github.com/github/github/issues/68074
  test "declining a suggestion is not instrumented" do
    user = create(:user)
    org = create :organization, admin: user
    repo = create(:repository, owner: org)
    topic = create :topic, name: "self-driving-cars"

    events = subscribe "repo.add_topic"

    repo_topic = create(:repository_topic,
      topic: topic,
      repository: repo,
      user: user,
      state: :declined_not_relevant,
    )

    refute events.pop, "did not expect an instrumentation event"
  end

  test "instruments removing a topic from a repo" do
    user = create(:user)
    org = create :organization, admin: user
    repo = create(:repository, owner: org)
    topic = create :topic, name: "self-driving-cars"
    repo_topic = create(:repository_topic,
      topic: topic,
      repository: repo,
      user: user,
      state: :suggested,
    )

    events = subscribe "repo.remove_topic"

    repo_topic.destroy

    expected_payload = {
      topic:         "self-driving-cars",
      topic_id:      topic.id,
      state:         "suggested",
      user:          user.login,
      user_id:       user.id,
      org:           org.to_s,
      org_id:        org.id,
      repository_topic_id: repo_topic.id,
      repo:          repo.name_with_owner,
      repo_id:       repo.id,
      public_repo:   repo.public?,
    }

    assert event = events.pop, "expected an instrumentation event"
    assert_equal expected_payload, event.payload
  end

  test "disallows more than specified limit of applied topics per repository" do
    repo = create(:repository)
    create(:repository_topic, repository: repo, state: :suggested) # reach the limit
    limit = 1
    topic = create(:topic)

    RepositoryTopic.stub_const(:LIMIT_PER_REPOSITORY, limit) do
      repo_topic = build(:repository_topic, repository: repo, state: :created, topic: topic)

      assert_query_count(2) do # uniqueness + topic limit
        refute_predicate repo_topic, :valid?
      end

      assert_includes repo_topic.errors[:repository], "cannot have more than #{limit} topics."
    end
  end

  test "does not validate topic limit per repo when skip_topic_limit_check=true" do
    repo = create(:repository)
    create(:repository_topic, repository: repo, state: :suggested) # reach the limit
    topic = create(:topic)

    RepositoryTopic.stub_const(:LIMIT_PER_REPOSITORY, 1) do
      repo_topic = build(:repository_topic, repository: repo, state: :created, topic: topic)
      repo_topic.skip_topic_limit_check = true

      assert_query_count(1) do # uniqueness
        assert_predicate repo_topic, :valid?
      end
    end
  end

  test "topic is valid even after user deletes account" do
    topic = create(:repository_topic)
    assert_predicate topic, :valid?

    topic.user.destroy!
    assert_nil topic.reload.user
    assert_predicate topic, :valid?
  end

  context ".create_missing" do
    test "creates new records for the repo-topic pairs that don't exist" do
      user = create(:user)
      repo = create(:repository, owner: user)
      topic1, topic2 = create_pair(:topic)
      assert_empty repo.topics

      assert_difference(-> { RepositoryTopic.count }, 2) do
        RepositoryTopic.create_missing(repository: repo, topics: [topic1, topic2], user: user,
          existing_repo_topics: [])
      end

      assert_same_elements [topic1, topic2], repo.topics.reload

      repo_topic1 = RepositoryTopic.where(topic_id: topic1, repository_id: repo.id).first
      repo_topic1 = T.must(repo_topic1)
      refute_nil repo_topic1
      refute_nil repo_topic1.updated_at
      refute_nil repo_topic1.created_at
      assert_equal user, repo_topic1.user
      assert_equal "created", repo_topic1.state

      repo_topic2 = RepositoryTopic.where(topic_id: topic2, repository_id: repo.id).first
      repo_topic2 = T.must(repo_topic2)
      refute_nil repo_topic2
      refute_nil repo_topic2.updated_at
      refute_nil repo_topic2.created_at
      assert_equal user, repo_topic2.user
      assert_equal "created", repo_topic2.state
    end

    test "skips topics that are already applied to the repository" do
      repo = create(:repository)
      old_user = repo.owner
      new_user = create(:user)
      old_state = :created
      existing_repo_topic = create(:repository_topic, repository: repo, user: old_user, state: old_state)
      old_updated_at = existing_repo_topic.updated_at
      old_created_at = existing_repo_topic.created_at
      existing_topic = existing_repo_topic.topic
      new_topic = create(:topic)
      assert_equal [existing_topic], repo.topics

      assert_difference(-> { RepositoryTopic.count }) do
        RepositoryTopic.create_missing(topics: [new_topic, existing_topic], repository: repo, user: new_user,
          existing_repo_topics: [existing_repo_topic])
      end

      assert_same_elements [new_topic, existing_topic], repo.topics.reload

      assert_equal old_updated_at, existing_repo_topic.reload.updated_at,
        "should not have changed existing repo-topic"
      assert_equal old_created_at, existing_repo_topic.created_at
      assert_equal old_state.to_s, existing_repo_topic.state
      assert_equal old_user, existing_repo_topic.user
      assert_equal existing_topic, existing_repo_topic.topic
      assert_equal repo, existing_repo_topic.repository

      new_repo_topic = RepositoryTopic.where(topic_id: new_topic, repository_id: repo.id).first
      new_repo_topic = T.must(new_repo_topic)
      refute_nil new_repo_topic
      refute_nil new_repo_topic.updated_at
      refute_nil new_repo_topic.created_at
      assert_equal "created", new_repo_topic.state
      assert_equal new_user, new_repo_topic.user
    end

    test "skips topics that are already applied to the repository which are detected via database uniqueness validation" do
      repo = create(:repository)
      old_user = repo.owner
      new_user = create(:user)
      new_topic = create(:topic)

      RepositoryTopic.any_instance.stubs(:save!).raises(ActiveRecord::RecordNotUnique, repo)
      assert_nothing_raised do
        RepositoryTopic.create_missing(topics: [new_topic], repository: repo, user: new_user,
          existing_repo_topics: [])
      end

      assert_same_elements [], repo.topics.reload
    end

    test "errors when too many topics are given" do
      limit = 1
      repo = create(:repository)
      topics = create_list(:topic, limit + 1)
      user = repo.owner

      RepositoryTopic.stub_const(:LIMIT_PER_REPOSITORY, limit) do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          RepositoryTopic.create_missing(topics: topics, repository: repo, user: user, existing_repo_topics: [])
        end

        assert_equal "Validation failed: Repository cannot have more than #{limit} topics.", error.message
      end
    end

    test "errors when the combination of given topics and existing topics is too many" do
      limit = 1
      repo = create(:repository)
      user = repo.owner
      existing_repo_topic = create(:repository_topic, repository: repo, state: :created)
      new_topic = create(:topic)

      RepositoryTopic.stub_const(:LIMIT_PER_REPOSITORY, limit) do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          RepositoryTopic.create_missing(topics: [new_topic], repository: repo, user: user,
            existing_repo_topics: [existing_repo_topic])
        end

        assert_equal "Validation failed: Repository cannot have more than #{limit} topics.", error.message
      end
    end
  end

  context ".names_for" do
    test "returns a limited list of topic names for a specific repo id" do
      repository_one = create(:repository)
      repository_two = create(:repository)
      topic_one = create(:topic, name: "superheroes")
      topic_two = create(:topic, name: "villains")
      topic_three = create(:topic, name: "cats")
      create(:repository_topic, repository: repository_one, topic: topic_one)
      create(:repository_topic, repository: repository_one, topic: topic_two)
      create(:repository_topic, repository: repository_two, topic: topic_three)

      result = RepositoryTopic.names_for(
        repository_ids: [repository_one.id, repository_two.id],
        limit_per_repo: 7,
      )

      assert_equal %w[superheroes villains], result[repository_one.id]
      assert_equal ["cats"], result[repository_two.id]
    end
  end

  context ".autocompleted_names" do
    test "returns suggestions" do
      repository_one = create(:repository)
      repository_two = create(:repository)
      topic_one = create(:topic, name: "superheroes", applied_count: 1)
      topic_two = create(:topic, name: "villains", applied_count: 1)
      topic_three = create(:topic, name: "supervillains", applied_count: 1)
      create(:repository_topic, repository: repository_one, topic: topic_one)
      create(:repository_topic, repository: repository_one, topic: topic_two)
      create(:repository_topic, repository: repository_two, topic: topic_three)

      result = RepositoryTopic.autocompleted_names(
        repository: repository_one,
        query: "super",
        viewer: repository_one.owner,
      )

      assert_equal ["supervillains"], result
    end
  end

  context "#remove_omitted" do
    test "removes topics from repo that aren't in given list" do
      repo = create(:public_repository)
      topic1 = create :topic
      topic2 = create :topic

      create(:repository_topic, topic: topic1, repository: repo, state: :created)
      create(:repository_topic, topic: topic2, repository: repo, state: :suggested)

      assert_difference "RepositoryTopic.count", -1 do
        RepositoryTopic.remove_omitted(repo, [topic1.name])
      end

      assert_equal [topic1.name], repo.topics.pluck(:name)
    end

    test "creates hydro event for removed topics" do
      repo = create(:public_repository)
      topics = %w(fun awesome)
      result = repo.update_topics(topics, user: repo.owner)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        repository: Hydro::EntitySerializer.repository(repo),
        repository_owner: Hydro::EntitySerializer.user(repo.owner),
        action: :ACTION_TOPIC_DELETED,
        actor: Hydro::EntitySerializer.user(repo.owner),
        topic: Hydro::EntitySerializer.topic(repo.topics.find_by(name: "awesome")),
      }

      assert_difference "RepositoryTopic.count", -1 do
        repo.update_topics(["fun"], user: repo.owner)
      end

      assert_hydro_published(message, schema: "github.v1.TopicsData")
      assert_hydro_messages(count: 3, schema: "github.v1.TopicsData")
    end
  end

  context ".replace" do
    test "returns true when all topics are applied" do
      assert_difference ["Topic.count", "RepositoryTopic.count"], 3 do
        assert RepositoryTopic.replace(@repo, %w(cat dog log), user: @repo.owner)

        assert_equal 1, @repo.topics.where(name: "cat").count
        assert_equal 1, @repo.topics.where(name: "dog").count
        assert_equal 1, @repo.topics.where(name: "log").count
      end
    end

    test "does not wipe declined topics when given an empty list" do
      declined = create(:repository_topic, repository: @repo, state: :declined_too_specific)
      applied = create(:repository_topic, repository: @repo, state: :created)

      assert_difference "RepositoryTopic.count", -1 do
        assert RepositoryTopic.replace(@repo, [], user: @repo.owner)
      end

      assert RepositoryTopic.exists?(declined.id), "declined topic should not have been removed"
      refute RepositoryTopic.exists?(applied.id), "applied topic should have been removed"
    end

    test "returns false when not all topics are created successfully" do
      RepositoryTopic.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid, @repo)

      assert_no_difference ["RepositoryTopic.count"] do
        refute RepositoryTopic.replace(@repo, %w(cat dog log), user: @repo.owner)
        assert_empty @repo.topics
      end
    end

    test "does not raise when some topics are not unique" do
      RepositoryTopic.any_instance.stubs(:save!).raises(ActiveRecord::RecordNotUnique, @repo)

      assert_no_difference ["RepositoryTopic.count"] do
        assert RepositoryTopic.replace(@repo, %w(cat dog log), user: @repo.owner)
        assert_empty @repo.topics
      end
    end

    test "returns false when not all repo-topics are updated successfully" do
      topic = create(:topic, name: "cat")
      repo_topic = create(:repository_topic, repository: @repo, topic: topic, state: :suggested)
      assert_includes @repo.topics.reload, topic

      RepositoryTopic.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid, @repo)

      assert_no_difference(-> { RepositoryTopic.count }) do
        refute RepositoryTopic.replace(@repo, [topic.name, "dog", "log"], user: @repo.owner)

        assert_equal [topic], @repo.topics.reload
        assert_equal "suggested", repo_topic.reload.state, "should not have changed state to created"
      end
    end

    test "returns false when more topics are given than are allowed" do
      RepositoryTopic.stub_const(:LIMIT_PER_REPOSITORY, 1) do
        topic_names = %w(foo bar)

        assert_no_difference(-> { RepositoryTopic.count }) do
          refute RepositoryTopic.replace(@repo, topic_names, user: @repo.owner)
        end

        assert_empty @repo.topics
      end
    end

    test "removes old topics even when too many new topics are given" do
      old_topic = create(:topic, name: "baz")
      create(:repository_topic, repository: @repo, topic: old_topic)

      RepositoryTopic.stub_const(:LIMIT_PER_REPOSITORY, 1) do
        topic_names = %w(foo bar)

        assert_difference(-> { RepositoryTopic.count }, -1) do
          refute RepositoryTopic.replace(@repo, topic_names, user: @repo.owner)
        end

        assert_empty @repo.topics
      end
    end

    test "removes from the repository existing topics that were omitted from the list" do
      topic = create(:topic, name: "old-faithful")
      repo_topic = create(:repository_topic, topic: topic, repository: @repo)

      assert_no_difference "RepositoryTopic.count" do
        assert RepositoryTopic.replace(@repo, ["new-hotness"], user: @repo.owner)

        assert_equal ["new-hotness"], @repo.topics.pluck(:name)
      end
    end

    test "removes all topics from the repository when empty array is given" do
      topic = create(:topic, name: "old-faithful")
      repo_topic = create(:repository_topic, topic: topic, repository: @repo)

      assert_difference "RepositoryTopic.count", -1 do
        assert RepositoryTopic.replace(@repo, [], user: @repo.owner)

        assert_empty @repo.topics
        refute RepositoryTopic.exists?(repo_topic.id)
      end
    end

    test "removes all topics from the repository when nil is given" do
      topic = create(:topic, name: "old-faithful")
      repo_topic = create(:repository_topic, topic: topic, repository: @repo)

      assert_difference "RepositoryTopic.count", -1 do
        assert RepositoryTopic.replace(@repo, nil, user: @repo.owner)

        assert_empty @repo.topics
        refute RepositoryTopic.exists?(repo_topic.id)
      end
    end

    test "keeps existing topic when unnormalized name is given" do
      topic = create(:topic, name: "summertime")
      repo_topic = create(:repository_topic, topic: topic, repository: @repo)

      assert_no_difference ["Topic.count", "RepositoryTopic.count"] do
        assert RepositoryTopic.replace(@repo, [" SummerTime\t"], user: @repo.owner)

        assert_equal ["summertime"], @repo.topics.pluck(:name)
      end
    end

    test "stores which user applied the changes" do
      topic = create(:topic, name: "summertime")
      user = create(:user)

      assert RepositoryTopic.replace(@repo, ["summertime"], user: user)
      assert_equal user.id, RepositoryTopic.find_by!(topic_id: @repo.topics.first.id).user_id
    end

    test "updates the repository's updated_at" do
      now = Time.zone.local(2017, 2, 9)
      repo = create(:repository, created_at: now, updated_at: now)

      later = Time.zone.local(2017, 2, 12)
      Timecop.freeze(later) do
        RepositoryTopic.replace(repo, ["summertime"], user: repo.owner)
      end

      assert_equal later, repo.updated_at
    end

    test "instruments when replacing topics" do
      expected_changes = {
        old_topics: [],
        topics: ["test"]
      }

      events = subscribe "repo.update"

      RepositoryTopic.replace(@repo, ["test"], user: @repo.owner)

      assert event = events.pop, "an event was expected"
      assert_equal expected_changes, event.payload[:changes]
    end

    test "instruments when replacing topics with no topics" do
      expected_changes = {
        old_topics: ["test"],
        topics: []
      }

      RepositoryTopic.replace(@repo, ["test"], user: @repo.owner)

      events = subscribe "repo.update"

      RepositoryTopic.replace(@repo, [], user: @repo.owner)

      assert event = events.pop, "an event was expected"
      assert_equal expected_changes, event.payload[:changes]
    end
  end
end
