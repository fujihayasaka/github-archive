# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Orgs
      class TopicTest < GitHub::TestCase
        fixtures do
          @org_1 = create(:organization)

          @repo_1 = create(:repository, owner: @org_1, name: "repository-1")
          @repo_2 = create(:repository, owner: @org_1, name: "repository-2")
          @repo_3 = create(:repository, owner: @org_1, name: "repository-3")

          @topic_1 = create(:topic, name: "topic-1", short_description: "This is topic 1").tap do |t|
            create(:repository_topic, topic: t, repository: @repo_1)
            create(:repository_topic, topic: t, repository: @repo_2)
          end
          @topic_2 = create(:topic, name: "topic-2", short_description: "This is topic 2").tap do |t|
            create(:repository_topic, topic: t, repository: @repo_1)
            create(:repository_topic, topic: t, repository: @repo_3)
          end
          @topic_3 = create(:topic, name: "topic-3", short_description: "This is topic 3").tap do |t|
            create(:repository_topic, topic: t, repository: @repo_2)
            create(:repository_topic, topic: t, repository: @repo_3)
          end
        end

        context "when no allowed repo IDs are provided" do
          test "it returns an empty array" do
            suggestions = Topic.new(organization: @org_1, allowed_repo_ids: []).suggestions

            assert_same_elements([], suggestions)
          end
        end

        context "when allowed repo IDs is nil" do
          test "it returns all topics for the org" do
            suggestions = Topic.new(organization: @org_1, allowed_repo_ids: nil).suggestions

            assert_same_elements(
              [
                Suggestion.new(description: @topic_1.short_description, value: @topic_1.name),
                Suggestion.new(description: @topic_2.short_description, value: @topic_2.name),
                Suggestion.new(description: @topic_3.short_description, value: @topic_3.name)
              ],
              suggestions
            )
          end
        end

        context "when selected values are provided" do
          test "it returns suggestions omitting the selected values" do
            suggestions = Topic.new(
              organization: @org_1,
              allowed_repo_ids: [@repo_1.id, @repo_2.id, @repo_3.id],
              selected_values: [@topic_1.name]
            ).suggestions

            assert_same_elements(
              [
                Suggestion.new(description: @topic_2.short_description, value: @topic_2.name),
                Suggestion.new(description: @topic_3.short_description, value: @topic_3.name)
              ],
              suggestions
            )
          end
        end

        context "when a value is provided" do
          test "it returns suggestions whose names match the value" do
            suggestions = Topic.new(
              organization: @org_1,
              allowed_repo_ids: [@repo_1.id, @repo_2.id, @repo_3.id],
              value: "pic-2"
            ).suggestions

            assert_same_elements(
              [Suggestion.new(description: @topic_2.short_description, value: @topic_2.name)],
              suggestions
            )
          end
        end

        context "when selected values and a value are provided" do
          test "it returns suggestions matching the value and omitting the selected values" do
            suggestions = Topic.new(
              organization: @org_1,
              allowed_repo_ids: [@repo_1.id, @repo_2.id, @repo_3.id],
              selected_values: [@topic_1.name],
              value: "pic"
            ).suggestions

            assert_same_elements(
              [
                Suggestion.new(description: @topic_2.short_description, value: @topic_2.name),
                Suggestion.new(description: @topic_3.short_description, value: @topic_3.name)
              ],
              suggestions
            )
          end
        end

        test "it returns suggestions in ascending alphabetical order by value" do
          suggestions = Topic.new(
            organization: @org_1,
            allowed_repo_ids: [@repo_1.id, @repo_2.id, @repo_3.id],
            value: "topic"
          ).suggestions

          assert_same_elements(
            [
              Suggestion.new(description: @topic_1.short_description, value: @topic_1.name),
              Suggestion.new(description: @topic_2.short_description, value: @topic_2.name),
              Suggestion.new(description: @topic_3.short_description, value: @topic_3.name)
            ],
            suggestions
          )
        end

        context "limit" do
          test "it limits the number of suggestions returned" do
            suggestions = Topic.new(
              organization: @org_1,
              allowed_repo_ids: [@repo_1.id, @repo_2.id, @repo_3.id],
              limit: 2,
              value: "topic"
            ).suggestions

            assert_same_elements(
              [
                Suggestion.new(description: @topic_1.short_description, value: @topic_1.name),
                Suggestion.new(description: @topic_2.short_description, value: @topic_2.name)
              ],
              suggestions
            )
          end
        end
      end
    end
  end
end
