# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Filters
    class ByCustomPropertyTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @user_session = create(:user_session, user: @user)
        @org = create(:organization, admin: @user)
        @repo_1 = create(:private_repository, owner: @org).tap do |r|
          create(:security_overview_analytics_repository, repository: r)
        end
        @repo_2 = create(:private_repository, owner: @org).tap do |r|
          create(:security_overview_analytics_repository, repository: r)
        end
      end

      setup do
        @base_rel = ::SecurityOverviewAnalytics::Repository.all
      end

      context "#apply" do
        context "when allowed_repo_ids is empty" do
          test "it returns the same relation" do
            res_rel = ByCustomProperty.new(
              allowed_repo_ids: [],
              query: "props.foo:foo_value_1",
              org: @org,
              user: @user,
              user_session: @user_session
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
              user: @user,
              user_session: @user_session
            ).apply(@base_rel)

            assert_same_elements(res_rel.pluck(:repository_id), @base_rel.pluck(:repository_id))
          end
        end

        test "it returns a relation with the repo IDs matching the requested custom properties" do
          ByCustomProperty.any_instance.stubs(:es_repo_ids).returns([@repo_1.id])

          res_rel = ByCustomProperty.new(
            allowed_repo_ids: [@repo_1.id, @repo_2.id],
            query: "props.foo:foo_value_1",
            org: @org,
            user: @user,
            user_session: @user_session
          ).apply(@base_rel)

          assert_same_elements([@repo_1.id], res_rel.pluck(:repository_id))
        end
      end

      context "#is_empty?" do
        test "returns proper result for is_empty?" do
          refute ByCustomProperty.new(
            allowed_repo_ids: [],
            query: "props.foo:foo_value_1",
            org: @org,
            user: @user,
            user_session: @user_session
          ).is_empty?
          assert ByCustomProperty.new(
            allowed_repo_ids: [],
            query: "",
            org: @org,
            user: @user,
            user_session: @user_session
          ).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns proper result for has_incl_filters?" do
          assert ByCustomProperty.new(
            allowed_repo_ids: [],
            query: "props.foo:foo_value_1",
            org: @org,
            user: @user,
            user_session: @user_session
          ).has_incl_filters?
          refute ByCustomProperty.new(
            allowed_repo_ids: [],
            query: "-props.foo:foo_value_1",
            org: @org,
            user: @user,
            user_session: @user_session
          ).has_incl_filters?
          refute ByCustomProperty.new(
            allowed_repo_ids: [],
            query: "",
            org: @org,
            user: @user,
            user_session: @user_session
          ).has_incl_filters?
        end
      end
    end
  end
end
