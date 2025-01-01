# typed: true
# frozen_string_literal: true

require "test_helper"

class TopicImporterTest < GitHub::TestCase
  setup do
    @topics_repo_owner = create(:organization, login: TopicImporter::REPO_OWNER)
    @topics_repo = create(:repository, owner: @topics_repo_owner, name: TopicImporter::REPO_NAME, from_example: :explore)
    @importer = TopicImporter.new
  end

  context "#import" do
    test "sets an error if the topics repository does not exist" do
      @topics_repo.destroy

      @importer.import(dry_run: true)

      assert_includes @importer.errors, "Missing public repository #{@topics_repo.nwo}"
    end

    test "sets an error if the latest sha couldn't be found in the topics repository" do
      @topics_repo.destroy
      # Make the repo again, but don't set it up with `example_repo`:
      repo = create(:repository, owner: @topics_repo_owner, name: TopicImporter::REPO_NAME)

      @importer.import(dry_run: true)

      assert_includes @importer.errors,
        "Could not determine latest commit for #{repo.nwo} in #{repo.default_branch} branch"
    end

    test "does not create or update any topics when in dry run" do
      topic = create(:topic, name: "graphql")

      assert_no_difference "Topic.count" do
        @importer.import(dry_run: true)

        assert_empty @importer.errors
      end

      assert_nil topic.reload.released
      assert_nil topic.github_url
      assert_nil topic.short_description
    end

    test "removes curated content for topics that have been deleted from the repository" do
      topic = create(:featured_topic, name: "not-in-repo")

      assert_difference "Topic.curated.count", -1 do
        @importer.import(dry_run: false, topic_names: [topic.name])

        assert_empty @importer.errors
      end

      assert Topic.exists?(topic.id), "topic should not have been deleted"
      refute_predicate topic.reload, :curated?,
        "topic should no longer have curated content"
      refute_predicate topic, :featured?, "should no longer be featured"
    end

    test "reports in dry run that it will remove curated content for topics not in repo" do
      topic = create(:curated_topic, name: "not-in-repo")

      assert_no_difference "Topic.curated.count" do
        @importer.import(dry_run: true)

        assert_empty @importer.errors
      end

      assert_predicate topic.reload, :curated?, "topic should still have curated content"

      changeset = @importer.updated_topic_changesets.detect { |changeset| changeset.topic == topic }
      refute_nil changeset
      assert_empty changeset.new_related
      assert_empty changeset.new_aliases
    end

    test "creates new topics when not in dry run" do
      assert_difference "Topic.count", 2 do
        assert_difference "TopicRelation.count", 10 do
          @importer.import(dry_run: false, topic_names: %w[graphql 3d])

          assert_empty @importer.errors
        end
      end

      refute_nil Topic.find_by_name("graphql")

      topic_3d = Topic.find_by_name("3d")
      refute_nil topic_3d
      assert_nil topic_3d.logo_url
    end

    test "only creates new topics from the given list when not in dry run" do
      assert_difference "Topic.count" do
        assert_difference "TopicRelation.count", 3 do
          @importer.import(dry_run: false, topic_names: ["3d"])

          assert_empty @importer.errors
        end
      end

      assert_nil Topic.find_by_name("graphql")
      refute_nil Topic.find_by_name("3d")
    end

    test "updates existing topics when not in dry run" do
      topic = create(:topic, name: "graphql", short_description: "GraphQL is cool.")
      topic.update_related_topics_from_names("graphql-client, graphql-api")

      assert_difference "Topic.count" do
        @importer.import(dry_run: false, topic_names: %w[graphql 3d])

        assert_empty @importer.errors
      end

      assert_equal "2015", topic.reload.released
      assert_equal "#{GitHub.scheme}://#{GitHub.urls.raw_host_name}/#{TopicImporter::REPO_OWNER}/" \
                   "#{TopicImporter::REPO_NAME}/550b4226c6538d27b09cf1a3ee39d18ac0fda3d6/topics/" \
                   "#{topic.name}/#{topic.name}.png", topic.logo_url
      assert_equal "https://github.com/graphql", topic.github_url
      assert_equal "GraphQL is a query language for APIs and a runtime for fulfilling those " \
                   "queries with your existing data.", topic.short_description
      assert_same_elements %w[api rest graphql-client graphql-api graphql-schema graphql-query
                              graphql-server], topic.related_topic_names
    end

    test "updates only existing topics from given list when not in dry run" do
      topic_3d = create(:topic, name: "3d", short_description: "3d imaging is neat")
      topic_graphql = create(:topic, name: "graphql", short_description: "GraphQL is neat")

      assert_no_difference "Topic.count" do
        @importer.import(dry_run: false, topic_names: ["graphql"])

        assert_empty @importer.errors
      end

      assert_equal "GraphQL is a query language for APIs and a runtime for fulfilling those " \
                   "queries with your existing data.", topic_graphql.reload.short_description
      assert_equal "3d imaging is neat", topic_3d.reload.short_description
    end
  end

  context "#any_updates?" do
    test "true when the importer finds changed topics after import" do
      create(:topic, name: "graphql")

      @importer.import(dry_run: true)

      assert_predicate @importer, :any_updates?
    end

    test "false when the importer finds no changed topics after import" do
      @importer.import(dry_run: true)

      refute_predicate @importer, :any_updates?
    end
  end

  context "#any_new?" do
    test "true when the importer finds new topics after import" do
      @importer.import(dry_run: true)

      assert_predicate @importer, :any_new?
    end

    test "false when the importer finds no new topics after import" do
      create(:topic, name: "3d")
      create(:topic, name: "babel")
      create(:topic, name: "graphql")

      @importer.import(dry_run: true)

      refute_predicate @importer, :any_new?
    end
  end

  context "#any_changes?" do
    test "true when the importer finds new or changed topics after import" do
      @importer.import(dry_run: true)

      assert_predicate @importer, :any_changes?
    end

    test "false when the importer finds no new or changed topics after import" do
      # Get all the changes in:
      @importer.import(dry_run: false, topic_names: %w[babel graphql 3d])
      assert_empty @importer.errors

      importer = TopicImporter.new
      importer.import(dry_run: true) # import should find no changes since last import

      refute_predicate importer, :any_changes?
    end
  end

  context "#new_topic_changesets" do
    test "returns changesets for topics not yet in the database" do
      create(:topic, name: "babel")

      @importer.import(dry_run: true)

      changesets = @importer.new_topic_changesets
      assert_equal 2, changesets.size
      assert_same_elements %w[graphql 3d], changesets.map { |changeset| changeset.topic.name }
    end
  end

  context "#updated_topic_changesets" do
    test "returns changesets for topics in the database that have updates" do
      create(:topic, name: "babel")

      @importer.import(dry_run: true)

      changesets = @importer.updated_topic_changesets
      assert_equal 1, changesets.size
      assert_equal %w[babel], changesets.map { |changeset| changeset.topic.name }
    end
  end

  context "#new_count" do
    test "returns the number of topics the importer will create" do
      @importer.import(dry_run: true)

      assert_equal 3, @importer.new_count
    end
  end

  context "#updated_count" do
    test "returns the number of topics the importer will update" do
      create(:topic, name: "graphql")
      @importer.import(dry_run: true)

      assert_equal 1, @importer.updated_count
    end
  end
end
