# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessAdvancedSecurityFeaturesTest < GitHub::TestCase
  fixtures do
    return if GitHub.enterprise?

    @owner = create(:user)
    @business = create(:business, :enterprise_managed)
    @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

    # EMU
    @emu_user = create(:emu, business: @business)
    @emu_owned_repo = create(:private_repository, force_user_owned: true, owner: @emu_user)
  end

  context "feature_available_for_user_repositories?", skip_enterprise: true do
    test "returns true if the business is enterprise managed and the feature flag is enabled" do
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
      assert feature.feature_available_for_user_repositories?
    end

    test "returns false if it is not enterprise managed" do
      # Add an unrelated business
      biz = create(:business)
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(biz)
      refute feature.feature_available_for_user_repositories?
    end

    test "returns false if the business has not purchased advanced security" do
      biz = create(:business, :enterprise_managed)
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(biz)
      refute feature.feature_available_for_user_repositories?
    end
  end

  context "get_enterprise_users", skip_enterprise: true do
    test "fetches users in the business" do
      # Add an unrelated business
      biz = create(:business, :enterprise_managed)
      rando = create(:emu, business: biz)

      # Add a few more users
      ids = [@emu_user.id]
      10.times do |_|
        u = create(:emu, business: @business)
        ids << u.id
      end
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

      users = feature.get_enterprise_users(user_ids: ids + [rando.id])

      assert_same_elements ids, users.map(&:id)
    end

    test "includes suspended users" do
      # add a suspended user
      suspended_user = create(:emu, business: @business, login: "suspended-emu")
      suspended_user.external_identities.first.disable

      ids = [@emu_user.id, suspended_user.id]
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

      users = feature.get_enterprise_users(user_ids: ids)

      assert_same_elements ids, users.map(&:id)
    end

    test "returns nothing if the business has not setup a provider" do
      @business.external_provider.destroy

      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

      users = feature.get_enterprise_users(user_ids: [@emu_user.id])
      assert_equal [], users
    end

    test "returns false if the business has not purchased advanced security" do
      biz = create(:business, :enterprise_managed)
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(biz)

      users = feature.get_enterprise_users(user_ids: [@emu_user.id])
      assert_equal [], users
    end
  end

  context "num_enterprise_users", skip_enterprise: true do
    test "fetches total user count in business" do
      # Add an unrelated business
      biz = create(:business, :enterprise_managed)
      rando = create(:emu, business: biz)

      # Add a few more users
      ids = [@emu_user.id]
      10.times do |_|
        u = create(:emu, business: @business)
        ids << u.id
      end
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

      num_users = feature.num_enterprise_users
      assert_equal ids.length, num_users
    end
  end

  context "list_enterprise_users_paged", skip_enterprise: true do
    test "lists users in the business" do
      # Add an unrelated business
      biz = create(:business, :enterprise_managed)
      rando = create(:emu, business: biz)

      # Add a few more users
      ids = [@emu_user.id]
      10.times do |_|
        u = create(:emu, business: @business)
        ids << u.id
      end
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

      # Ask for a bit more than the expected count
      users = feature.list_enterprise_users_paged(page: 1, per_page: ids.length + 1)

      assert_same_elements ids, users.map(&:id)
    end

    test "includes suspended users" do
      # add a suspended user
      suspended_user = create(:emu, business: @business, login: "suspended-emu")
      suspended_user.external_identities.first.disable

      ids = [@emu_user.id, suspended_user.id]
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

      users = feature.list_enterprise_users_paged(page: 1, per_page: ids.length + 1)

      assert_same_elements ids, users.map(&:id)
    end

    test "returns nothing if the business has not setup a provider" do
      @business.external_provider.destroy

      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

      users = feature.list_enterprise_users_paged(page: 1, per_page: 100)
      assert_equal [], users
    end

    test "returns false if the business has not purchased advanced security" do
      biz = create(:business, :enterprise_managed)
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(biz)

      users = feature.list_enterprise_users_paged(page: 1, per_page: 100)
      assert_equal [], users
    end
  end

  context "list_enterprise_users_offset", skip_enterprise: true do
    test "lists users in the business from an offset of 0" do
      # Add a few more users
      ids = [@emu_user.id]
      10.times do |_|
        u = create(:emu, business: @business)
        ids << u.id
      end

      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
      users = feature.list_enterprise_users_offset(offset_id: 0, per_page: ids.length + 1)

      assert_same_elements ids, users.map(&:id)
    end

    test "lists users in the business from a non-zero offset" do
      # Add some users we don't expect to be in the list
      offset = @emu_user.id
      5.times do |_|
        u = create(:emu, business: @business)
        offset = u.id
      end
      # Add some users we expect to be in the list
      ids = []
      5.times do |_|
        u = create(:emu, business: @business)
        ids << u.id
      end

      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
      users = feature.list_enterprise_users_offset(offset_id: offset, per_page: ids.length + 1)

      assert_same_elements ids, users.map(&:id)
    end

    test "includes suspended users" do
      # add a suspended user
      suspended_user = create(:emu, business: @business, login: "suspended-emu")
      suspended_user.external_identities.first.disable

      ids = [@emu_user.id, suspended_user.id]
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

      users = feature.list_enterprise_users_offset(offset_id: 0, per_page: ids.length + 1)

      assert_same_elements ids, users.map(&:id)
    end

    test "returns nothing if the business has not setup a provider" do
      @business.external_provider.destroy

      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

      users = feature.list_enterprise_users_offset(offset_id: 0, per_page: 100)
      assert_equal [], users
    end

    test "returns false if the business has not purchased advanced security" do
      biz = create(:business, :enterprise_managed)
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(biz)

      users = feature.list_enterprise_users_offset(offset_id: 0, per_page: 100)
      assert_equal [], users
    end
  end

  context "list_enterprise_users_ids_offset", skip_enterprise: true do
    test "lists users in the business from an offset of 0" do
      # Add a few more users
      ids = [@emu_user.id]
      10.times do |_|
        u = create(:emu, business: @business)
        ids << u.id
      end

      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
      user_ids = feature.list_enterprise_users_ids_offset(offset_id: 0, per_page: ids.length + 1)

      assert_same_elements ids, user_ids
    end

    test "lists users in the business from a non-zero offset" do
      # Add some users we don't expect to be in the list
      offset = @emu_user.id
      5.times do |_|
        u = create(:emu, business: @business)
        offset = u.id
      end
      # Add some users we expect to be in the list
      ids = []
      5.times do |_|
        u = create(:emu, business: @business)
        ids << u.id
      end

      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
      user_ids = feature.list_enterprise_users_ids_offset(offset_id: offset, per_page: ids.length + 1)

      assert_same_elements ids, user_ids
    end

    test "includes suspended users" do
      # add a suspended user
      suspended_user = create(:emu, business: @business, login: "suspended-emu")
      suspended_user.external_identities.first.disable

      ids = [@emu_user.id, suspended_user.id]
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

      user_ids = feature.list_enterprise_users_ids_offset(offset_id: 0, per_page: ids.length + 1)

      assert_same_elements ids, user_ids
    end

    test "returns nothing if the business has not setup a provider" do
      @business.external_provider.destroy

      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

      users = feature.list_enterprise_users_ids_offset(offset_id: 0, per_page: 100)
      assert_equal [], users
    end

    test "returns false if the business has not purchased advanced security" do
      biz = create(:business, :enterprise_managed)
      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(biz)

      users = feature.list_enterprise_users_ids_offset(offset_id: 0, per_page: 100)
      assert_equal [], users
    end
  end

  if GitHub.enterprise?
    class BusinessAdvancedSecurityFeaturesEnterpriseTest < GitHub::TestCase
      fixtures do
        @business = GitHub.global_business || create(:business, seats: 5)
        @owner = @business.admins.first
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

        @rando = create(:user)
      end

      setup do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
      end

      context "feature_available_for_user_repositories?" do
        test "short-circuits true for enterprise" do
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          assert feature.feature_available_for_user_repositories?
        end

        test "returns false if config is not set" do
          GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          refute feature.feature_available_for_user_repositories?
        end
      end

      context "list_enterprise_users_paged" do
        test "returns all users" do
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          ids = [User.ghost.id, @owner.id, @rando.id]

          # Ask for a bit more than the expected count
          users = feature.list_enterprise_users_paged(page: 1, per_page: ids.length + 1)

          assert_same_elements ids, users.map(&:id)
        end

        test "returns nothing if feature is unavailable" do
          GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

          assert_equal [], feature.list_enterprise_users_paged(page: 1, per_page: 100)
        end
      end

      context "get_enterprise_users" do
        test "fetches users in the business" do
          ids = [User.ghost.id, @owner.id, @rando.id]
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          users = feature.get_enterprise_users(user_ids: ids)

          assert_same_elements ids, users.map(&:id)
        end

        test "returns nothing if feature is unavailable" do
          GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)

          ids = [User.ghost.id, @owner.id, @rando.id]
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

          assert_equal [], feature.get_enterprise_users(user_ids: ids)
        end
      end

      context "num_enterprise_users" do
        test "lists users in the business" do
          # Add a few more users
          ids = [User.ghost.id, @owner.id, @rando.id]
          10.times do |_|
            u = create(:user)
            ids << u.id
          end
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

          num_users = feature.num_enterprise_users
          assert_equal ids.length, num_users
        end
      end

      context "list_enterprise_users_offset" do
        test "lists users at an offset of 0" do
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          ids = [User.ghost.id, @owner.id, @rando.id]

          # Ask for a bit more than the expected count
          users = feature.list_enterprise_users_offset(offset_id: 0, per_page: ids.length + 1)

          assert_same_elements ids, users.map(&:id)
        end

        test "lists users at nonzero offset" do
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          ids = [@owner.id, @rando.id]

          # Ask for a bit more than the expected count
          users = feature.list_enterprise_users_offset(offset_id: User.ghost.id, per_page: ids.length + 1)

          assert_same_elements ids, users.map(&:id)
        end

        test "respects the per_page param" do
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          ids = [User.ghost.id]

          # Ask for a bit more than the expected count
          users = feature.list_enterprise_users_offset(offset_id: 0, per_page: 1)

          assert_same_elements ids, users.map(&:id)
        end

        test "returns nothing if feature is unavailable" do
          GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

          assert_equal [], feature.list_enterprise_users_offset(offset_id: 0, per_page: 100)
        end
      end

      context "list_enterprise_users_ids_offset" do
        test "lists users at an offset of 0" do
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          ids = [User.ghost.id, @owner.id, @rando.id]

          # Ask for a bit more than the expected count
          user_ids = feature.list_enterprise_users_ids_offset(offset_id: 0, per_page: ids.length + 1)

          assert_same_elements ids, user_ids
        end

        test "lists users at nonzero offset" do
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          ids = [@owner.id, @rando.id]

          # Ask for a bit more than the expected count
          user_ids = feature.list_enterprise_users_ids_offset(offset_id: User.ghost.id, per_page: ids.length + 1)

          assert_same_elements ids, user_ids
        end

        test "respects the per_page param" do
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          ids = [User.ghost.id]

          # Ask for a bit more than the expected count
          user_ids = feature.list_enterprise_users_ids_offset(offset_id: 0, per_page: 1)

          assert_same_elements ids, user_ids
        end

        test "returns nothing if feature is unavailable" do
          GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

          assert_equal [], feature.list_enterprise_users_ids_offset(offset_id: 0, per_page: 100)
        end
      end
    end
  end
end
