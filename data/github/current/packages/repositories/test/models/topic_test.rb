# typed: strict
# frozen_string_literal: true

require "test_helper"
require "munger/client"

class TopicTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include AuditLog::IntegrationTestHelpers

  context ".ensure_names_exist" do
    test "creates topics that don't exist with the given names" do
      names = %w(foo bar)
      assert_empty Topic.where(name: names)

      assert_difference(-> { Topic.count }, names.size) do
        Topic.ensure_names_exist(names)
      end

      new_topics = Topic.where(name: names)
      assert_equal names.size, new_topics.size
      new_topics.each do |topic|
        refute_nil topic.updated_at, "should have set updated_at on new topic"
        refute_nil topic.created_at, "should have set created_at on new topic"
      end
    end

    test "creates topics that don't yet exist while leaving existing topics alone" do
      existing_topic = create(:topic, name: "foo")
      old_updated_at = existing_topic.updated_at
      old_created_at = existing_topic.created_at
      names = [existing_topic.name, "bar"]
      assert_equal 1, Topic.where(name: names).count

      assert_difference(-> { Topic.count }) do
        Topic.ensure_names_exist(names)
      end

      assert_equal 2, Topic.where(name: names).count
      new_topic = Topic.find_by_name("bar")
      refute_nil new_topic, "should have made a topic for the missing name"
      refute_nil new_topic.created_at
      refute_nil new_topic.updated_at
      assert_equal old_updated_at, existing_topic.reload.updated_at
      assert_equal old_created_at, existing_topic.created_at
    end

    test "no-op when all given names exist as topics" do
      topic1, topic2 = create_pair(:topic)
      names = [topic1.name, topic2.name]
      old_updated_at1 = topic1.updated_at
      old_updated_at2 = topic2.updated_at
      old_created_at1 = topic1.created_at
      old_created_at2 = topic2.created_at

      assert_no_difference(-> { Topic.count }) do
        Topic.ensure_names_exist(names)
      end

      assert_equal old_updated_at1, topic1.reload.updated_at
      assert_equal old_updated_at2, topic2.reload.updated_at
      assert_equal old_created_at1, topic1.created_at
      assert_equal old_created_at2, topic2.created_at
      assert_equal names, [topic1.name, topic2.name], "should not have changed the names"
    end

    test "no-op when no names are given" do
      assert_no_difference(-> { Topic.count }) do
        Topic.ensure_names_exist([])
      end
    end
  end

  context "#unapplied?" do
    test "returns true when topic is not connected to any repository" do
      topic = create :topic

      assert_predicate topic, :unapplied?
    end

    test "returns true when topic has only been rejected for a repository" do
      topic = create :topic
      create(:repository_topic, topic: topic, state: :declined_not_relevant)

      assert_predicate topic, :unapplied?
    end

    test "returns false when topic has been applied to a repository" do
      topic = create :topic
      create(:repository_topic, topic: topic, state: :created)

      refute_predicate topic, :unapplied?
    end
  end

  context "#is_an_alias?" do
    test "returns true if the topic is an alias of another topic" do
      source_topic = create :topic
      topic_relation = create(:topic_relation, topic: source_topic, name: "peppers",
                                          relation_type: :alias)
      topic = create(:topic, name: "peppers")

      assert_predicate topic, :is_an_alias?
    end

    test "returns false if the topic is a related topic of another topic" do
      source_topic = create :topic
      topic_relation = create(:topic_relation, topic: source_topic, name: "banana-peppers",
                                          relation_type: :related)
      topic = create(:topic, name: "banana-peppers")

      refute_predicate topic, :is_an_alias?
    end

    test "returns false if the topic has some aliases of its own" do
      source_topic = create :topic
      topic_relation = create(:topic_relation, topic: source_topic, name: "cucumbers",
                                          relation_type: :alias)
      topic = create(:topic, name: "cucumbers")

      refute_predicate source_topic, :is_an_alias?
    end

    test "returns false if the topic has no topic relations" do
      refute_predicate (create :topic), :is_an_alias?
    end
  end

  context "#alias_source_topic_relation" do
    test "returns alias relation tying the topic back to its source topic" do
      source_topic = create :topic
      topic_relation = create(:topic_relation, topic: source_topic, name: "pickles",
                                          relation_type: :alias)
      topic = create(:topic, name: "pickles")

      assert_equal topic_relation, topic.alias_source_topic_relation
    end

    test "returns nil when no topic has this topic as an alias" do
      topic = create :topic

      assert_nil topic.alias_source_topic_relation
    end
  end

  context "#alias_source_topic" do
    test "returns topic that has this topic as an alias" do
      source_topic = create :topic
      create(:topic_relation, topic: source_topic, name: "pickles", relation_type: :alias)
      topic = create(:topic, name: "pickles")

      assert_equal source_topic, topic.alias_source_topic
    end

    test "returns nil when no topic has this topic as an alias" do
      topic = create :topic

      assert_nil topic.alias_source_topic
    end
  end

  context ".featured_names" do
    test "includes name of a featured topic" do
      featured_topic = create :featured_topic

      assert_includes Topic.featured_names, featured_topic.name
    end

    test "includes name of an alias of a featured topic" do
      featured_topic = create :featured_topic
      relation = create(:topic_relation, topic: featured_topic, relation_type: :alias)

      assert_includes Topic.featured_names, relation.name
    end

    test "does not include name of a topic related to a featured topic" do
      featured_topic = create :featured_topic
      relation = create(:topic_relation, topic: featured_topic, relation_type: :related)

      refute_includes Topic.featured_names, relation.name
    end

    test "excludes name of a non-featured topic" do
      topic = create :topic

      refute_includes Topic.featured_names, topic.name
    end
  end

  test "with_logo scope includes only topics with a logo_url" do
    logo_topic = create(:topic, logo_url: "http://example.com/photo.png")
    non_logo_topic = create(:topic, logo_url: nil)

    results = Topic.with_logo

    assert_includes results, logo_topic
    refute_includes results, non_logo_topic
  end

  test "featured scope includes only featured topics" do
    featured_topic = create :featured_topic
    non_featured_topic = create(:topic, name: "some-junk")

    results = Topic.featured

    assert_includes results, featured_topic
    refute_includes results, non_featured_topic
  end

  context ".find_or_build_from_names" do
    test "returns a list of topics even when some aren't saved" do
      names = %w[cat hat rat cats]
      create(:topic, name: "cat")

      results = Topic.find_or_build_from_names(names, scope: Topic)

      assert results.all? { |result| result.is_a?(Topic) }
      assert_same_elements names, results.map(&:name)
    end
  end

  context ".find_or_build_by_name" do
    test "returns an existing topic" do
      existing = create(:topic, name: "something")
      assert_equal existing, Topic.find_or_build_by_name("SomeThing")
    end

    test "builds, but does not persist, a new topic" do
      built = Topic.find_or_build_by_name("some STUFF")
      assert_equal "some-stuff", built.name
      refute_predicate built, :persisted?
    end

    test "returns nil if the topic is invalid" do
      assert_nil Topic.find_or_build_by_name("Invalid! Characters?")
    end
  end

  test "curated scope includes only topics for which we have curated content" do
    curated_topic = create :curated_topic
    non_curated_topic = create(:topic, name: "some-junk")

    results = Topic.curated

    assert_includes results, curated_topic
    refute_includes results, non_curated_topic
  end

  test "validates length of short_description" do
    text = "a" * (Topic::MAX_SHORT_DESCRIPTION_LENGTH + 1)
    topic = build(:topic, short_description: text)

    refute_predicate topic, :valid?
    assert_predicate topic.errors[:short_description], :any?
  end

  test "validates length of created_by" do
    text = "a" * (Topic::MAX_CREATED_BY_LENGTH + 1)
    topic = build(:topic, created_by: text)

    refute_predicate topic, :valid?
    assert_predicate topic.errors[:created_by], :any?
  end

  test "validates length of display_name" do
    text = "a" * (Topic::MAX_DISPLAY_NAME_LENGTH + 1)
    topic = build(:topic, display_name: text)

    refute_predicate topic, :valid?
    assert_predicate topic.errors[:display_name], :any?
  end

  test "validates length of released" do
    text = "a" * (Topic::MAX_RELEASED_LENGTH + 1)
    topic = build(:topic, released: text)

    refute_predicate topic, :valid?
    assert_predicate topic.errors[:released], :any?
  end

  test "requires name" do
    topic = Topic.new(name: nil)
    refute_predicate topic, :valid?
    assert topic.errors[:name]
  end

  test "validates length of name" do
    topic = Topic.new(name: "a" * 51)
    refute_predicate topic, :valid?
    assert topic.errors[:name]
  end

  test "allows single-character names" do
    topic = Topic.new(name: "c")
    assert topic.save, "should allow single-character name"
    assert_equal "c", topic.reload.name
  end

  test "allows some symbols, numbers, and hyphens in name" do
    name = "cats-are-cool-mmkay4-2"
    topic = Topic.new(name: name)
    assert topic.save
    assert_equal name, topic.reload.name
  end

  test "allows name starting with a number" do
    topic = Topic.new(name: "3d-printing")
    assert_predicate topic, :valid?
  end

  test "disallows rails-2.3.4-&&&&@@$# as a topic" do
    topic = Topic.new(name: "rails-2.3.4-&&&&@@$#")
    refute_predicate topic, :valid?
    assert topic.errors[:name]
  end

  test "replaces underscore in name with hyphen" do
    topic = create(:topic, name: "node_js")
    assert_equal "node-js", topic.reload.name
  end

  test "disallows slash in name" do
    topic = Topic.new(name: "cheshire137/gh-notifications-snoozer")
    refute_predicate topic, :valid?
    assert topic.errors[:name]
  end

  test "disallows comma in name" do
    topic = Topic.new(name: "cats,dogs")
    refute_predicate topic, :valid?
    assert topic.errors[:name]
  end

  test "disallows # in name" do
    topic = Topic.new(name: "sea#")
    refute_predicate topic, :valid?
    assert topic.errors[:name]
  end

  test "disallows double quote in name" do
    topic = Topic.new(name: 'cool-"cats"')
    refute_predicate topic, :valid?
    assert topic.errors[:name]
  end

  test "disallows starting name with a hyphen" do
    topic = Topic.new(name: "-xCoolGuyX-")
    refute_predicate topic, :valid?
    assert topic.errors[:name]
  end

  test "disallows emoji in name" do
    topic = Topic.new(name: "🐹")
    refute_predicate topic, :valid?
    assert topic.errors[:name]
  end

  test "lowercases and strips leading + trailing whitespace from name" do
    topic = Topic.new(name: "\tGLORIOUS-TAG-OF-GLORY   ")
    assert topic.save
    assert_equal "glorious-tag-of-glory", topic.reload.name
  end

  test "validates uniqueness of normalized name" do
    topic = Topic.create(name: "fancy-frogs")
    duplicate = Topic.new(name: " FaNcY-fRoGs\n")
    refute duplicate.save
    assert duplicate.errors[:name]
  end

  context ".normalize" do
    test "replaces spaces with dashes" do
      name = Topic.normalize("circle to land")
      assert_equal "circle-to-land", name
    end

    test "strips leading + trailing whitespace" do
      name = Topic.normalize("\tGLORIOUS-TAG-OF-GLORY   ")
      assert_equal "glorious-tag-of-glory", name
    end

    test "removes consecutive whitespace" do
      name = Topic.normalize("luke    i    am your    father")
      assert_equal "luke-i-am-your-father", name
    end
  end

  context "#update_aliases_from_names" do
    test "adds new aliases" do
      topic = create :topic

      assert_difference "topic.topic_aliases.count", 2 do
        topic.update_aliases_from_names("cat, dog, ))-pickles, cat")
      end

      assert_same_elements %w[cat dog], topic.alias_names
    end

    test "removes old aliases not in the given string" do
      topic = create :topic
      old_relation1 = create(:topic_relation, topic: topic, name: "kittens", relation_type: :alias)
      old_relation2 = create(:topic_relation, topic: topic, name: "hog", relation_type: :alias)

      topic.update_aliases_from_names("frog, log, hog")

      assert_same_elements %w[frog log hog], topic.alias_names
      refute TopicRelation.exists?(old_relation1.id)
      assert TopicRelation.exists?(old_relation2.id)
    end

    test "changes a related topic to an alias" do
      topic = create :topic
      old_relation = create(:topic_relation, topic: topic, name: "pickles", relation_type: :related)

      topic.update_aliases_from_names("fries,pickles")

      assert_same_elements %w[fries pickles], topic.alias_names
      assert_predicate old_relation.reload, :alias?
    end
  end

  context "#related_topic_names" do
    test "returns names of related topics" do
      topic = create :topic
      create(:topic_relation, topic: topic, name: "frogger", relation_type: :related)
      create(:topic_relation, topic: topic, name: "pacman", relation_type: :related)
      create(:topic_relation, topic: topic, name: "digdug", relation_type: :alias)

      assert_same_elements %w[frogger pacman], topic.related_topic_names
    end

    test "returns an empty array when topic has no related topics" do
      topic = create :topic

      assert_empty topic.related_topic_names
    end
  end

  context "#alias_names" do
    test "returns names of aliased topics" do
      topic = create :topic
      create(:topic_relation, topic: topic, name: "video-game", relation_type: :alias)
      create(:topic_relation, topic: topic, name: "game", relation_type: :alias)
      create(:topic_relation, topic: topic, name: "boardgame", relation_type: :related)

      assert_same_elements %w[video-game game], topic.alias_names
    end

    test "returns an empty array when topic has no aliases" do
      topic = create :topic

      assert_empty topic.alias_names
    end
  end

  context "#update_related_topics_from_names" do
    test "adds new related topics" do
      topic = create :topic

      assert_difference "topic.related_topics.count", 2 do
        topic.update_related_topics_from_names("cat, dog, ))-pickles, cat")
      end

      assert_same_elements %w[cat dog], topic.related_topic_names
    end

    test "removes old related topics not in the given string" do
      topic = create :topic
      old_relation1 = create(:topic_relation, topic: topic, name: "kittens", relation_type: :related)
      old_relation2 = create(:topic_relation, topic: topic, name: "hog", relation_type: :related)

      topic.update_related_topics_from_names("frog, log, hog")

      assert_same_elements %w[frog log hog], topic.related_topic_names
      refute TopicRelation.exists?(old_relation1.id)
      assert TopicRelation.exists?(old_relation2.id)
    end

    test "changes an alias to a related topic" do
      topic = create :topic
      old_relation = create(:topic_relation, topic: topic, name: "pickles", relation_type: :alias)

      topic.update_related_topics_from_names("fries,pickles")

      assert_same_elements %w[fries pickles], topic.related_topic_names
      assert_predicate old_relation.reload, :related?
    end
  end

  context ".extract_featured_topic_name" do
    test "returns given string if given string is featured topic name" do
      featured_topic = create :featured_topic

      assert_equal featured_topic.name, Topic.extract_featured_topic_name(featured_topic.name)
    end

    test "returns nil if given string is non-featured topic name" do
      topic = create :topic

      assert_nil Topic.extract_featured_topic_name(topic.name)
    end

    test "returns nil if given string does not include a featured topic's name" do
      topic = create :topic

      assert_nil Topic.extract_featured_topic_name("somewhere over the #{topic.name} I am")
    end

    test "returns string if given string includes a featured topic's name" do
      featured_topic = create :featured_topic
      input = "somewhere over the #{featured_topic.name} I am"

      assert_equal featured_topic.name, Topic.extract_featured_topic_name(input)
    end

    test "returns string if given string uses a search qualifier with featured topic name" do
      featured_topic = create :featured_topic
      input = "author:sample-user topic:#{featured_topic.name} cats"

      assert_equal featured_topic.name, Topic.extract_featured_topic_name(input)
    end
  end

  context ".related_to" do
    test "includes related topic names when we have a curated list" do
      topic = create(:featured_topic, name: "react")
      topic.update_related_topics_from_names("vue")

      assert_includes Topic.related_to("react"), "vue"
    end
  end

  context "applied scope" do
    test "returns topic applied to a repository" do
      repo_topic = create(:repository_topic, state: :created)

      Topic.update_applied_counts(Topic.ids)

      assert_equal [repo_topic.topic], Topic.applied
    end

    test "returns topic suggested and accepted for a repository" do
      repo_topic = create(:repository_topic, state: :suggested)

      Topic.update_applied_counts(Topic.ids)

      assert_equal [repo_topic.topic], Topic.applied
    end

    test "omits topics declined for a repository" do
      topic_ids = [
        create(:repository_topic, state: :declined_too_general),
        create(:repository_topic, state: :declined_too_specific),
        create(:repository_topic, state: :declined_not_relevant),
        create(:repository_topic, state: :declined_personal_preference),
      ].map(&:topic_id)

      Topic.update_applied_counts(topic_ids)

      assert_empty Topic.applied
    end

    test "returns an empty list when no topic has been used" do
      create(:topic, name: "unused-topic")

      Topic.update_applied_counts(Topic.ids)

      assert_empty Topic.applied
    end
  end

  context ".applied_and_related_to" do
    test "returns only related relations" do
      topic = create(:topic, name: "this-topic")
      second_topic = create(:topic, name: "second-topic")
      third_topic = create(:topic, name: "third-topic")
      create(:topic_relation, relation_type: :related, topic: topic, name: "second-topic")
      create(:topic_relation, relation_type: :alias, topic: topic, name: "third-topic")
      repo = create(:repository)
      create(:repository_topic, repository: repo, topic: topic)
      create(:repository_topic, repository: repo, topic: second_topic)
      create(:repository_topic, repository: repo, topic: third_topic)

      expected_topics = [second_topic]

      Topic.update_applied_counts([topic, second_topic, third_topic].map(&:id))

      assert_equal expected_topics, Topic.applied_and_related_to("this-topic")
    end
  end

  context "#safe_display_name" do
    test "returns the display name if set" do
      topic = create(:topic, name: "name", display_name: "display")
      assert_equal "display", topic.safe_display_name
    end

    test "falls back to the name if not set" do
      topic = create(:topic, name: "name", display_name: nil)
      assert_equal "name", topic.safe_display_name
    end
  end

  context "#to_s" do
    test "returns the name" do
      assert_equal "cats", Topic.new(name: "cats").to_s
    end
  end

  context "#to_param" do
    test "returns the name" do
      assert_equal "bagel", Topic.new(name: "bagel").to_param
    end
  end

  context ".filter_flagged_names" do
    test "filters topics correctly" do
      topic = create :topic
      flagged_topic = create :flagged_topic

      filtered = Topic.filter_flagged_names([topic.name, flagged_topic.name])
      assert_equal [topic.name], filtered
    end

    test "filters empty array" do
      assert_equal [], Topic.filter_flagged_names([])
    end
  end

  context ".find_by_name" do
    test "normalizes the given name and returns a Topic" do
      topic = create(:topic, name: "hot-topics")
      assert_equal topic, Topic.find_by_name(" HoT-ToPiCs\t\t\n")
    end

    test "returns nil when no Topic with given name exists" do
      assert_nil Topic.find_by_name("uh-oh-spaghettios")
    end
  end

  context ".valid_name?" do
    test "true when given a valid name" do
      assert Topic.valid_name?("cats")
    end

    test "true when given the name of an existing topic" do
      assert Topic.valid_name?((create :topic).name)
    end

    test "false when given an invalid name" do
      refute Topic.valid_name?("-8-bit")
      refute Topic.valid_name?("")
      refute Topic.valid_name?(nil)
    end
  end

  context ".popular_names_for_repositories" do
    test "empty when no topics on given repositories" do
      repo = create(:repository)
      assert_empty Topic.popular_names_for_repositories(repositories: [repo])
    end

    test "empty when topic only applied to one repository" do
      topic = create :topic
      repo = create(:repository)
      create(:repository_topic, repository: repo, topic: topic)

      assert_empty Topic.popular_names_for_repositories(repositories: [repo])
    end

    test "returns most applied topic names for given repo scope" do
      most_popular = create :topic # applied the most
      somewhat_popular = create :topic # applied a couple times
      least_popular = create :topic # applied least frequently
      declined = create :topic # declined on some repos
      unused = create :topic # not tied to any repos

      owner = create(:organization)
      repo1 = create(:repository, owner: owner)
      repo2 = create(:repository, owner: owner)
      repo3 = create(:repository, owner: owner)

      create(:repository_topic, topic: most_popular, repository: repo1, state: :created)
      create(:repository_topic, topic: most_popular, repository: repo2, state: :created)
      create(:repository_topic, topic: most_popular, repository: repo3, state: :created)

      # Apply a topic enough where it would show in the results except it's not
      # included in the given repository scope.
      create(:repository_topic, topic: most_popular, state: :created)
      create(:repository_topic, topic: most_popular, state: :created)
      create(:repository_topic, topic: most_popular, state: :created)

      create(:repository_topic, topic: somewhat_popular, repository: repo1, state: :created)
      create(:repository_topic, topic: somewhat_popular, repository: repo2, state: :created)

      create(:repository_topic, topic: least_popular, repository: repo3, state: :created)

      create(:repository_topic, topic: declined, repository: repo2, state: :declined_too_general)
      create(:repository_topic, topic: declined, repository: repo3, state: :declined_too_specific)

      repo_scope = owner.repositories
      assert_equal [most_popular.name, somewhat_popular.name],
        Topic.popular_names_for_repositories(repositories: repo_scope, limit: 2)
    end
  end

  test ".update_applied_counts" do
    topic1 = create(:topic)
    topic2 = create(:topic)
    topic3 = create(:topic)

    create(:repository_topic, topic: topic1, state: :created)
    create(:repository_topic, topic: topic2, state: :created)
    create(:repository_topic, topic: topic2, state: :suggested)
    create(:repository_topic, topic: topic2, state: :declined_too_specific)
    create(:repository_topic, topic: topic3, state: :created)

    Topic.update_applied_counts([topic1.id, topic2.id])

    assert_equal 1, topic1.reload.applied_count
    assert_equal 2, topic2.reload.applied_count
    assert_equal 0, topic3.reload.applied_count

    topic1.update!(applied_count: 0)
    assert_equal 0, topic1.reload.applied_count
    topic2.update!(applied_count: 0)
    assert_equal 0, topic2.reload.applied_count

    create(:repository_topic, topic: topic2, state: :created)

    Topic.update_applied_counts([topic1.id, topic2.id, topic3.id])

    assert_equal 1, topic1.reload.applied_count
    assert_equal 3, topic2.reload.applied_count
    assert_equal 1, topic3.reload.applied_count
  end

  test "suggestions_for_autocomplete" do
    assert_no_query_warnings do
      repo = create(:repository)
      topic1 = create(:topic, name: "foo")
      topic2 = create(:topic, name: "bar")
      create(:repository_topic, topic: topic1, repository: repo, user: repo.owner)
      create(:repository_topic, topic: topic2, repository: repo, user: repo.owner)
      Topic.update_applied_counts(Topic.ids)

      assert_equal [topic1], Topic.suggestions_for_autocomplete(query: "foo")
      assert_equal [], Topic.suggestions_for_autocomplete(query: GRIN_EMOJI)
    end
  end

  test "#resource_path and #resource_url" do
    topic = create(:topic, name: "whatever")
    resource_path = topic.resource_path
    resource_url = topic.resource_url

    if GitHub.enterprise?
      expected_query_values = { "q" => "topic:whatever", "type" => "Repositories" }
      assert_equal "/search", resource_path.path
      assert_equal expected_query_values, resource_path.query_values

      assert_equal "/search", resource_url.path
      assert_equal expected_query_values, resource_url.query_values
      refute_nil resource_url.host
      refute_nil resource_url.scheme
    else
      assert_equal "/topics/whatever", resource_path.path
      assert_nil resource_path.query_values

      assert_equal "/topics/whatever", resource_url.path
      assert_nil resource_url.query_values
      refute_nil resource_url.host
      refute_nil resource_url.scheme
    end
  end

  test "flagging and unflagging generates audit log events" do
    user = create(:user)
    GitHub.context.push(actor_id: user.id)

    topic = create(:topic)
    refute topic.flagged?

    events = assert_performed_audit_entries(count: 1, only: "topic.flag") do
      topic.flagged = true
      topic.save
    end

    assert topic.reload.flagged?

    expected_payload = {
      name: topic.name,
      flagged: true,
      applied_count: 0,
  }.merge(GitHub.guarded_audit_log_staff_actor_entry(user))

    assert_subset_hash expected_payload, events.first

    events = assert_performed_audit_entries(count: 1, only: "topic.unflag") do
      topic.flagged = false
      topic.save
    end

    refute topic.reload.flagged?

    expected_payload = {
      name: topic.name,
      flagged: false,
      applied_count: 0,
    }.merge(GitHub.guarded_audit_log_staff_actor_entry(user))

    assert_subset_hash expected_payload, events.first
  end
end
