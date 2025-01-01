# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Filters
    class ByCustomPropertyTest < GitHub::TestCase
      fixtures do
        @org = create(:organization)

        @org_custom_prop = create(
          :custom_property_definition,
          source: @org,
          property_name: "foo",
        )

        @repo_1 = create(:private_repository, owner: @org, name: "repo-1").tap do |r|
          create(:security_overview_analytics_repository, repository: r)
          @repo_1_custom_prop_value = create(
            :custom_property_value,
            definition: @org_custom_prop,
            target: r,
            value: "value-1"
          )
        end

        @repo_2 = create(:private_repository, owner: @org, name: "repo-2").tap do |r|
          create(:security_overview_analytics_repository, repository: r)
          @repo_1_custom_prop_value = create(
            :custom_property_value,
            definition: @org_custom_prop,
            target: r,
            value: "value-2"
          )
        end
      end

      setup do
        setup_search
        make_searchable(@org, @repo_1, @repo_2)
        @base_rel = ::SecurityOverviewAnalytics::Repository.all
      end

      teardown do
        teardown_search
      end

      context "#apply" do
        context "when allowed_repo_ids is empty" do
          test "it returns the same relation" do
            res_rel = ByCustomProperty.new(
              allowed_repo_ids: [],
              query: "props.foo:value-1",
              org: @org,
            ).apply(@base_rel)

            assert_same_elements(res_rel.pluck(:repository_id), @base_rel.pluck(:repository_id))
          end
        end

        context "when no custom properties are in the query" do
          test "it returns the same relation" do
            res_rel = ByCustomProperty.new(
              allowed_repo_ids: [@repo_1.id, @repo_2.id],
              query: "",
              org: @org,
            ).apply(@base_rel)

            assert_same_elements(res_rel.pluck(:repository_id), @base_rel.pluck(:repository_id))
          end
        end

        test "it returns a relation with the repo IDs matching the requested custom properties" do
          [["value-1", @repo_1], ["value-2", @repo_2]].each do |value, expected|
            res_rel = ByCustomProperty.new(
              query: "props.foo:#{value}",
              org: @org,
            ).apply(@base_rel)

            assert_same_elements([expected.id], res_rel.pluck(:repository_id), "for value #{value}")
          end
        end
      end

      context "#is_empty?" do
        test "returns proper result for is_empty?" do
          refute ByCustomProperty.new(
            allowed_repo_ids: [],
            query: "props.foo:value-1",
            org: @org,
          ).is_empty?
          assert ByCustomProperty.new(
            allowed_repo_ids: [],
            query: "",
            org: @org,
          ).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns proper result for has_incl_filters?" do
          assert ByCustomProperty.new(
            allowed_repo_ids: [],
            query: "props.foo:value-1",
            org: @org,
          ).has_incl_filters?
          refute ByCustomProperty.new(
            allowed_repo_ids: [],
            query: "-props.foo:value-1",
            org: @org,
          ).has_incl_filters?
          refute ByCustomProperty.new(
            allowed_repo_ids: [],
            query: "",
            org: @org,
          ).has_incl_filters?
        end
      end
    end
  end
end
