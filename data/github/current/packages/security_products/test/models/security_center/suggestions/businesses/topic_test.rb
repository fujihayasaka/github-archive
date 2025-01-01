# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Businesses
      class TopicTest < GitHub::TestCase
        fixtures do
          # Orgs
          @org_1 = create(:organization, name: "org-1")
          @org_2 = create(:organization, name: "org-2")
          @org_3 = create(:organization, name: "org-3")
          @all_orgs = [@org_1, @org_2, @org_3]

          # Repos
          @org_1_repo_1 = create(:repository, owner: @org_1, name: "#{@org_1}-repository-1")
          @org_1_repo_2 = create(:repository, owner: @org_1, name: "#{@org_1}-repository-2")

          @org_2_repo_1 = create(:repository, owner: @org_2, name: "#{@org_2}-repository-1")
          @org_2_repo_2 = create(:repository, owner: @org_2, name: "#{@org_2}-repository-2")

          @org_3_repo_1 = create(:repository, owner: @org_3, name: "#{@org_3}-repository-1")
          @org_3_repo_2 = create(:repository, owner: @org_3, name: "#{@org_3}-repository-2")

          # Topics
          @topic_1 = create(:topic, name: "topic-1", short_description: "This is topic 1").tap do |t|
            create(:repository_topic, topic: t, repository: @org_1_repo_1)
            create(:repository_topic, topic: t, repository: @org_1_repo_2)

            create(:repository_topic, topic: t, repository: @org_2_repo_1)
            create(:repository_topic, topic: t, repository: @org_2_repo_2)
          end
          @topic_2 = create(:topic, name: "topic-2", short_description: "This is topic 2").tap do |t|
            create(:repository_topic, topic: t, repository: @org_1_repo_1)
            create(:repository_topic, topic: t, repository: @org_1_repo_2)

            create(:repository_topic, topic: t, repository: @org_3_repo_1)
            create(:repository_topic, topic: t, repository: @org_3_repo_2)
          end
          @topic_3 = create(:topic, name: "topic-3", short_description: "This is topic 3").tap do |t|
            create(:repository_topic, topic: t, repository: @org_2_repo_1)
            create(:repository_topic, topic: t, repository: @org_2_repo_2)

            create(:repository_topic, topic: t, repository: @org_3_repo_1)
            create(:repository_topic, topic: t, repository: @org_3_repo_2)
          end
        end

        context "when no authorized orgs are provided" do
          test "it returns an empty array" do
            suggestions = Topic.new(authorized_orgs: []).suggestions

            assert_same_elements([], suggestions)
          end
        end

        test "it returns suggestions for all authorized orgs" do
          ###### 3 authorized orgs.

          suggestions = Topic.new(authorized_orgs: @all_orgs).suggestions

          expected_suggestions = [@topic_1, @topic_2, @topic_3].map do |topic|
            Suggestion.new(
              description: topic.short_description,
              value: topic.name
            )
          end

          assert_same_elements(expected_suggestions, suggestions)

          ###### 1 authorized org.

          suggestions = Topic.new(authorized_orgs: [@org_3]).suggestions

          expected_suggestions = [@topic_2, @topic_3].map do |topic|
            Suggestion.new(
              description: topic.short_description,
              value: topic.name
            )
          end

          assert_same_elements(expected_suggestions, suggestions)
        end

        context "when selected values are provided" do
          test "it returns suggestions omitting the selected values" do
            suggestions = Topic.new(
              authorized_orgs: @all_orgs,
              selected_values: [@topic_1.to_s, @topic_2.to_s]
            ).suggestions

            expected_suggestions = [@topic_3].map do |topic|
              Suggestion.new(
                description: topic.short_description,
                value: topic.name
              )
            end

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        test "it returns suggestions in ascending alphabetical order by topic name" do
          suggestions = Topic.new(authorized_orgs: @all_orgs).suggestions

          expected_suggestions = [@topic_1, @topic_2, @topic_3].map do |topic|
            Suggestion.new(
              description: topic.short_description,
              value: topic.name
            )
          end

          assert_equal(expected_suggestions, suggestions)
        end

        context "limit" do
          test "it limits the number of suggestions returned" do
            suggestions = Topic.new(
              authorized_orgs: @all_orgs,
              limit: 2
            ).suggestions

            expected_suggestions = [@topic_1, @topic_2].map do |topic|
              Suggestion.new(
                description: topic.short_description,
                value: topic.name
              )
            end

            assert_same_elements(expected_suggestions, suggestions)
          end
        end
      end
    end
  end
end
