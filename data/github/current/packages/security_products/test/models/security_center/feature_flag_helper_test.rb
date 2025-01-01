# typed: strict
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class FeatureFlagHelperTest < GitHub::TestCase
    context "including the module" do
      test "raises an error when included" do
        assert_raises(StandardError) do
          Class.new do
            include FeatureFlagHelper
          end
        end
      end

      test "raises an error when prepended" do
        assert_raises(StandardError) do
          Class.new do
            prepend FeatureFlagHelper
          end
        end
      end

      test "raises an error when extended" do
        assert_raises(StandardError) do
          Class.new do
            extend FeatureFlagHelper
          end
        end
      end
    end

    context ".feature_flag" do
      test "handles no actors" do
        feature = GitHub.flipper[:my_awesome_feature]

        feature.disable
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [])

        feature.enable_percentage_of_actors(0)
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [])

        feature.enable_percentage_of_actors(50)
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [])

        feature.enable_percentage_of_actors(100)
        assert FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [])

        feature.enable_percentage_of_actors(0)
        feature.enable
        assert FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [])
      end

      test "handles private beta enablement" do
        actors = [
          T.let(create(:user), User),
          T.let(create(:private_repository), Repository),
          T.let(create(:organization), Organization),
          T.let(create(:business), Business),
        ]

        # add all test subjects to the "feature group" flag
        group_flag = GitHub.flipper[:security_center_private_beta]
        actors.each do |actor|
          group_flag.enable_actor(actor)
        end

        # create brand new feature
        feature = GitHub.flipper[:my_awesome_feature]
        feature_for_private_beta = GitHub.flipper[:my_awesome_feature_private_beta]

        # disable features to counter the ALL_FEATURES run
        feature.disable
        feature_for_private_beta.disable

        # confirm nobody gets the feature yet
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: actors)
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [])

        # enable beta for a percentage of actors, confirm test subjects don't have the feature
        feature_for_private_beta.disable # unship first
        feature_for_private_beta.enable_percentage_of_actors(99.99)
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: actors)
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [])

        # enable beta for all actors, confirm test subjects have the feature
        feature_for_private_beta.disable # unship first
        feature_for_private_beta.enable_percentage_of_actors(100)
        actors.each do |actor|
          assert FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [actor])
        end
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [])

        # enable beta for a percentage using dark shipping, confirm test subjects don't have the feature
        feature_for_private_beta.disable # unship first
        feature_for_private_beta.enable_percentage_of_time(99.99)
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: actors)
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [])

        # enable beta fully dark shipped, confirm test subjects have the feature
        feature_for_private_beta.disable # unship first
        feature_for_private_beta.enable_percentage_of_time(100)
        actors.each do |actor|
          assert FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [actor])
        end
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [])

        # fully enable the feature for private beta, confirm test subjects have the feature
        feature_for_private_beta.disable # unship first
        feature_for_private_beta.enable
        actors.each do |actor|
          assert FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [actor])
        end
        refute FeatureFlagHelper.feature_flag(:my_awesome_feature, actors: [])
      end
    end

    context ".any_actor?" do
      context "no actors" do
        test "returns false" do
          count = 0
          result = FeatureFlagHelper.any_actor?([]) do
            count += 1
            true
          end

          assert_equal 0, count
          refute result
        end
      end

      context "unsupported actor type" do
        test "returns false" do
          actor = create(:team)

          count = 0
          result = FeatureFlagHelper.any_actor?([actor]) do
            count += 1
            true
          end

          assert_equal 0, count
          refute result
        end
      end

      context "multiple actors" do
        test "iterates provided actors while the block returns false" do
          actors = [
            (actor1 = create(:user)),
            (actor2 = create(:repository)),
          ]

          count = 0
          result = FeatureFlagHelper.any_actor?(actors) do |a|
            count += 1
            assert_equal actor1, a if count == 1
            assert_equal actor2, a if count == 2
            assert_equal actor2.owner, a if count == 3
            false
          end

          refute result
          assert_equal 3, count
        end

        test "iterating the provided actors is interrupted when the block returns true" do
          actors = [
            (actor1 = create(:user)),
            (actor2 = create(:repository)),
          ]

          # actor1
          count = 0
          result = FeatureFlagHelper.any_actor?(actors) do |a|
            count += 1
            a == actor1
          end

          assert result
          assert_equal 1, count

          # actor1 and actor2
          count = 0
          result = FeatureFlagHelper.any_actor?(actors) do |a|
            count += 1
            a == actor2
          end

          assert result
          assert_equal 2, count
        end
      end

      context "User" do
        test "only iterates the provided actor when the block returns false" do
          actor = create(:user)

          count = 0
          result = FeatureFlagHelper.any_actor?([actor]) do |a|
            count += 1
            assert_equal actor, a
            false
          end

          refute result
          assert_equal 1, count
        end

        test "returns result of the block" do
          actor = create(:user)
          assert FeatureFlagHelper.any_actor?([actor]) { true }
          refute FeatureFlagHelper.any_actor?([actor]) { false }
        end
      end

      context "Repository" do
        test "walks chain of ownership (repo-org-biz) when the block returns false" do
          biz = create(:business)
          org = create(:organization, business: biz)
          repo = create(:repository, owner: org)

          count = 0
          result = FeatureFlagHelper.any_actor?([repo]) do |a|
            count += 1
            assert_equal repo, a if count == 1
            assert_equal org, a if count == 2
            assert_equal biz, a if count == 3

            false
          end

          refute result
          assert_equal 3, count
        end

        test "walks chain of ownership (repo-org) when the block returns false" do
          org = create(:organization)
          repo = create(:repository, owner: org)

          count = 0
          result = FeatureFlagHelper.any_actor?([repo]) do |a|
            count += 1
            assert_equal repo, a if count == 1
            assert_equal org, a if count == 2

            false
          end

          refute result
          assert_equal 2, count
        end

        test "walks chain of ownership (repo-user) when the block returns false" do
          user = create(:user)
          repo = create(:repository, owner: user)

          count = 0
          result = FeatureFlagHelper.any_actor?([repo]) do |a|
            count += 1
            assert_equal repo, a if count == 1
            assert_equal user, a if count == 2

            false
          end

          refute result
          assert_equal 2, count
        end

        test "walking the chain of ownership is interrupted when the block returns true" do
          biz = create(:business)
          org = create(:organization, business: biz)
          repo = create(:repository, owner: org)

          # repo
          count = 0
          result = FeatureFlagHelper.any_actor?([repo]) do |a|
            count += 1
            a == repo
          end

          assert result
          assert_equal 1, count

          # repo and org
          count = 0
          result = FeatureFlagHelper.any_actor?([repo]) do |a|
            count += 1
            a == org
          end

          assert result
          assert_equal 2, count

          # repo, org, and biz
          count = 0
          result = FeatureFlagHelper.any_actor?([repo]) do |a|
            count += 1
            a == biz
          end

          assert result
          assert_equal 3, count
        end
      end

      context "organization" do
        test "walks the chain of ownership (org-biz) when the block returns false" do
          biz = create(:business)
          org = create(:organization, business: biz)

          count = 0
          result = FeatureFlagHelper.any_actor?([org]) do |a|
            count += 1
            assert_equal org, a if count == 1
            assert_equal biz, a if count == 2

            false
          end

          refute result
          assert_equal 2, count
        end

        test "walks the chain of ownership (org) when the block returns false" do
          actor = create(:organization)

          count = 0
          result = FeatureFlagHelper.any_actor?([actor]) do |a|
            count += 1
            assert_equal actor, a
            false
          end

          refute result
          assert_equal 1, count
        end

        test "walking the chain of ownership is interrupted when the block returns true" do
          biz = create(:business)
          org = create(:organization, business: biz)

          # org
          count = 0
          result = FeatureFlagHelper.any_actor?([org]) do |a|
            count += 1
            a == org
          end

          assert result
          assert_equal 1, count

          # org and biz
          count = 0
          result = FeatureFlagHelper.any_actor?([org]) do |a|
            count += 1
            a == biz
          end

          assert result
          assert_equal 2, count
        end
      end

      context "business" do
        test "only iterates the provided actor when the block returns false" do
          actor = create(:business)

          count = 0
          result = FeatureFlagHelper.any_actor?([actor]) do |a|
            count += 1
            assert_equal actor, a
            false
          end

          refute result
          assert_equal 1, count
        end

        test "returns the result of the block" do
          actor = create(:business)
          assert FeatureFlagHelper.any_actor?([actor]) { true }
          refute FeatureFlagHelper.any_actor?([actor]) { false }
        end
      end
    end

    context ".in_private_beta?" do
      test "handles private beta enablement" do
        actor = T.let(create(:user), User)

        # 'actor.feature_enabled?' checks get cached, so you can't toggle them in tests.
        # So we're using stubs instead

        actor.stubs(:feature_enabled?).with(:security_center_private_beta).returns(true)
        assert FeatureFlagHelper.in_private_beta?(actor)

        actor.stubs(:feature_enabled?).with(:security_center_private_beta).returns(false)
        refute FeatureFlagHelper.in_private_beta?(actor)
      end
    end
  end
end
