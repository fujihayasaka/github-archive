# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Orgs
      class RepoTest < GitHub::TestCase
        fixtures do
          @org_1 = create(:organization)

          @repo_1 = create(:repository, owner: @org_1, name: "repository-1").tap do |r|
            create(:repository_security_center_config, repository: r)
          end
          @repo_2 = create(:repository, owner: @org_1, name: "repository-2").tap do |r|
            create(:repository_security_center_config, repository: r)
          end
          @repo_3 = create(:repository, owner: @org_1, name: "repository-3").tap do |r|
            create(:repository_security_center_config, repository: r)
          end
        end

        context "when no allowed repo IDs are provided" do
          test "it returns an empty array" do
            suggestions = Repo.new(
              allowed_repo_ids: [],
              owner_id: @org_1.id
            ).suggestions

            assert_same_elements([], suggestions)
          end
        end

        context "when allowed repo IDs is nil" do
          test "it returns all repos for the org" do
            suggestions = Repo.new(
              allowed_repo_ids: nil,
              owner_id: @org_1.id
            ).suggestions

            expected = @org_1.repositories.map { |repo| Suggestion.new(value: repo.name) }
            assert_same_elements(expected, suggestions)
          end
        end

        context "when selected values are provided" do
          test "it returns suggestions omitting the selected values" do
            suggestions = Repo.new(
              allowed_repo_ids: [@repo_1.id, @repo_2.id, @repo_3.id],
              owner_id: @org_1.id,
              selected_values: [@repo_1.name, @repo_2.name]
            ).suggestions

            assert_same_elements([Suggestion.new(value: @repo_3.name)], suggestions)
          end
        end

        context "when a value is provided" do
          test "it returns suggestions whose names match the value" do
            suggestions = Repo.new(
              allowed_repo_ids: [@repo_1.id, @repo_2.id, @repo_3.id],
              owner_id: @org_1.id,
              value: "tory-1"
            ).suggestions

            assert_same_elements([Suggestion.new(value: @repo_1.name)], suggestions)
          end
        end

        context "when selected values and a value are provided" do
          test "it returns suggestions matching the value and omitting the selected values" do
            suggestions = Repo.new(
              allowed_repo_ids: [@repo_1.id, @repo_2.id, @repo_3.id],
              owner_id: @org_1.id,
              selected_values: [@repo_1.name],
              value: "tory"
            ).suggestions

            assert_same_elements([Suggestion.new(value: @repo_2.name), Suggestion.new(value: @repo_3.name)], suggestions)
          end
        end

        test "it returns suggestions in ascending alphabetical order by value" do
          suggestions = Repo.new(
            allowed_repo_ids: [@repo_1.id, @repo_2.id, @repo_3.id],
            owner_id: @org_1.id,
            selected_values: [@repo_1.name],
            value: "tory"
          ).suggestions

          assert_same_elements([Suggestion.new(value: @repo_2.name), Suggestion.new(value: @repo_3.name)], suggestions)
        end

        context "limit" do
          test "it limits the number of suggestions returned" do
            suggestions = Repo.new(
              allowed_repo_ids: [@repo_1.id, @repo_2.id, @repo_3.id],
              limit: 1,
              owner_id: @org_1.id,
              selected_values: [@repo_1.name],
              value: "tory"
            ).suggestions

            assert_same_elements([Suggestion.new(value: @repo_2.name)], suggestions)
          end
        end
      end
    end
  end
end
