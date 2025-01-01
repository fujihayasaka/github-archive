# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::AuthorizerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::QueryAssertionTestHelpers

  fixtures do
    @user = create(:user)
  end

  setup do
    GitHub.cache.allow = nil
    GitHub.cache.clear
    @context = Context.new

    disable_feature_flag(:copilot_revokable_access)
    disable_feature_flag(:copilot_respect_revokable_access)
    disable_feature_flag(:copilot_destroy_seat_assignment_in_cooldown)
  end

  context "access_allowed?" do
    test "plain user" do
      authorizer = Copilot::Authorizer.new(Copilot::User.new(@user), @context)
      refute authorizer.access_allowed?
      assert_equal "no_access", authorizer.access_type_sku
    end

    context "trade restrictions" do
      test "triggers a trade controls check but doesn't restrict the user because the country isn't in sanctioned countries", skip_enterprise: true do
        user = create(:user)
        context = Context.new
        context.push(country_code: "RU")
        context.push(region: "55")
        context.push(region_name: "Moscow")

        perform_enqueued_jobs(only: ::TradeControls::ComplianceCheckJob) do
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), context)
          refute authorizer.access_allowed?
          assert_equal "trade_restricted_country", authorizer.access_type_sku
          user.reload
          refute user.has_full_trade_restrictions?, "Expected user to not have full trade restrictions"
        end
      end

      test "triggers a trade controls check and restrict the user because the country is in sanctioned countries", skip_enterprise: true do
        user = create(:user)
        context = Context.new
        context.push(country_code: nil)
        context.push(region: nil)
        context.push(region_name: nil)

        country = T.must(TradeControls::Countries::SANCTIONED.first)
        GitHub::Location.stubs(:look_up).returns({ country_code: country.alpha2, region_name: country.region_name, region: country.region_code })
        GitHub.context.push(actor_ip: "127.0.0.1")

        perform_enqueued_jobs(only: ::TradeControls::ComplianceCheckJob) do
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), context)
          refute authorizer.access_allowed?
          assert_equal "trade_restricted_country", authorizer.access_type_sku
          user.reload
          assert user.has_full_trade_restrictions?, "Expected user to have full trade restrictions"
        end
      end

      context "trade_restricted" do
        test "trade_restricted" do
          user = create(:user, :fully_trade_restricted)
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          refute authorizer.access_allowed?
          assert_equal "trade_restricted", authorizer.access_type_sku
        end

        test "trade_restricted_country" do
          user = create(:user)
          context = Context.new
          context.push(country_code: "RU")
          context.push(region: "55")
          context.push(region_name: "Moscow")

          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), context)
          refute authorizer.access_allowed?
          assert_equal "trade_restricted_country", authorizer.access_type_sku
        end
      end
    end

    context "properties_check" do
      test "spammy" do
        user = create(:spammy_user)
        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        refute authorizer.access_allowed?
        assert_equal "spammy_user", authorizer.access_type_sku
      end

      test "partner_user" do
        org = create(:organization)
        enable_feature_flag(:copilot_for_partners, org)
        user = create(:user)
        org.add_member(user)
        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        assert authorizer.access_allowed?
        assert_equal "partner_access", authorizer.access_type_sku
      end

      test "blocked" do
        user = create(:user)
        Copilot::User.new(user).administrative_block!(create(:user), "reason")
        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        refute authorizer.access_allowed?
        assert_equal "feature_flag_blocked", authorizer.access_type_sku
      end
    end

    context "free_user_check" do
      Copilot::FreeUser::FREE_USER_TYPES.each do |free_user_type|
        test "#{free_user_type.name} without snippy" do
          user = create(:user)
          create(
            :copilot_free_user,
            user: user,
            subscribed: true,
            free_user_type: free_user_type.name,
            last_checked_date: Date.new(9999, 12, 31),
          )
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          refute authorizer.access_allowed?, free_user_type.name
        end
      end

      Copilot::FreeUser::FREE_USER_TYPES.each do |free_user_type|
        test "#{free_user_type.name} with snippy" do
          Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
          Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")

          user = create(:user)
          create(
            :copilot_free_user,
            user: user,
            subscribed: true,
            free_user_type: free_user_type.name,
            last_checked_date: Date.new(9999, 12, 31),
          )
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          assert authorizer.access_allowed?, free_user_type.name
        end
      end
    end

    context "codespaces_check" do
      test "CODESPACES_DEMO" do
        make_trusted_oauth_apps_owner
        create(:codespaces_integration)
        user = create(:user)
        repository = create(:repository)
        enable_feature_flag(:codespaces_copilot_demo_repository, repository)
        codespace = create(:codespace, owner: user, repository:)

        credential, _ = Codespaces::Tokens.grant_repository_access(user, codespace)
        oauth_access = OauthAccessTokens.domain.active(credential)

        user = User.find(T.must(oauth_access&.user&.id))
        user.oauth_access = oauth_access

        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        assert authorizer.access_allowed?
        assert_equal "codespaces_demo", authorizer.access_type_sku
      end

      test "CODESPACES_DEMO_INACTIVE" do
        make_trusted_oauth_apps_owner
        create(:codespaces_integration)
        user = create(:user)
        repository = create(:repository)
        enable_feature_flag(:codespaces_copilot_demo_repository, repository)
        codespace = create(:codespace, owner: user, repository:)

        credential, _ = Codespaces::Tokens.grant_repository_access(user, codespace)
        oauth_access = OauthAccessTokens.domain.active(credential)

        user = User.find(T.must(oauth_access).user_id)
        user.oauth_access = oauth_access

        copilot_user = Copilot::User.new(user)

        # Set to the final value
        Copilot.redis.set(copilot_user.codespaces_demo_key, Copilot::CODESPACES_DEMO_FINAL_VALUE, ex: 30.minutes.from_now.to_i)

        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        refute authorizer.access_allowed?
        assert_equal "codespaces_demo_inactive", authorizer.access_type_sku
      end
    end

    context "cfb_seats_check" do
      test "CFB Seat" do
        seat = create(:copilot_seat)
        user = seat.assigned_user
        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        assert authorizer.access_allowed?
        assert_equal "copilot_for_business_seat", authorizer.access_type_sku
      end

      test "CFE Seat" do
        seat = create(:copilot_seat, copilot_plan: "enterprise")
        user = seat.assigned_user
        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        assert authorizer.access_allowed?
        assert_equal "copilot_enterprise_seat", authorizer.access_type_sku
      end

      test "CFB Trial Seat" do
        organization = create(:copilot_for_business_credit_card_enabled_organization)
        create(:billing_sales_serve_plan_subscription, customer: organization.business.customer)
        trial = create(:copilot_business_trial, trialable_type: "Organization", trialable_id: organization.id)
        organization = trial.trialable
        seat = create(:copilot_seat, organization: organization)
        user = seat.assigned_user
        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        assert authorizer.access_allowed?
        assert_equal "copilot_for_business_trial_seat", authorizer.access_type_sku
      end

      test "CFE Trial Seat" do
        organization = create(:copilot_for_business_credit_card_enabled_organization)
        create(:billing_sales_serve_plan_subscription, customer: organization.business.customer)
        trial = create(:copilot_business_trial, trialable_type: "Organization", trialable_id: organization.id, copilot_plan: "enterprise")
        organization = trial.trialable
        seat = create(:copilot_seat, organization: organization)
        user = seat.assigned_user
        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        assert authorizer.access_allowed?
        assert_equal "copilot_enterprise_trial_seat", authorizer.access_type_sku
      end

      test "CFB Seat for billing locked owner" do
        seat = create(:copilot_seat)
        seat.owner.disable!
        user = seat.assigned_user
        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        refute authorizer.access_allowed?
        assert_equal "copilot_for_business_billing_locked", authorizer.access_type_sku
      end

      test "CFB Seat for billing locked owner, but with another real seat" do
        seat = create(:copilot_seat)
        seat.owner.disable!
        user = seat.assigned_user

        org = create(:organization)
        org.add_member(user)
        create(:copilot_seat, organization: org, assigned_user: user)

        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        assert authorizer.access_allowed?
        assert_equal "copilot_for_business_seat", authorizer.access_type_sku
      end
    end

    context "cfb_seat_assignments_check" do
      test "user's access was revoked with feature flag enabled" do
        enable_feature_flag(:copilot_revokable_access)
        enable_feature_flag(:copilot_respect_revokable_access)
        assignment = create(:copilot_seat_assignment, :user, access_revoked_at: Time.now, pending_cancellation_date: Time.now)
        user = assignment.assignable
        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
        logs = capture_logs do
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          refute authorizer.access_allowed?
          assert_equal "access_revoked", authorizer.access_type_sku
        end
        assert_includes logs, "All seat assignments for user have their access revoked."
        refute_dogstats_increment("copilot.authorizer.access_type.copilot_for_business_seat_assignment")
        assert_dogstats_increment(1, "copilot.authorizer.async_seat_assignments_revoked_check.access_revoked")
      end

      test "user's access was revoked with feature flags disabled" do
        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)

        assignment = create(:copilot_seat_assignment, :user)
        assignment.convert_to_seats
        assignment.update_columns(access_revoked_at: Time.now, pending_cancellation_date: Time.now)
        user = assignment.assignable

        logs = capture_logs do
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          assert authorizer.access_allowed?
          assert_equal "copilot_for_business_seat", authorizer.access_type_sku
        end

        refute_includes logs, "All seat assignments for user have their access revoked."
        refute_includes logs, "User has access type copilot_for_business_seat_assignment"
        refute_dogstats_increment("copilot.authorizer.access_type.access_revoked")
        refute_dogstats_increment("copilot.authorizer.async_seat_assignments_check.access_revoked")
        # we expect this twice in the test because convert_to_seats implicitly increments authorizer access
        assert_dogstats_increment(2, "copilot.authorizer.access_type.copilot_for_business_seat")
      end

      test "allows access if user has at least non-revoked seat assignment" do
        enable_feature_flag(:copilot_revokable_access)
        enable_feature_flag(:copilot_respect_revokable_access)

        revoked_assignment = create(:copilot_seat_assignment, :user)
        revoked_assignment.unassign_and_revoke_access!(nil, :bye)
        assignment = create(:copilot_seat_assignment, :user)
        user = assignment.assignable

        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)

        logs = capture_logs do
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          assert authorizer.access_allowed?
        end

        assert_includes logs, "Loading seat assignments for user"
        assert_includes logs, "gh.user.id=\"#{user.id}\""
        refute_includes logs, "All seat assignments for user have their access revoked."
        refute_dogstats_increment("copilot.authorizer.async_seat_assignments_revoked_check.access_revoked")
      end

      test "user CFB Seat assignment" do
        assignment = create(:copilot_seat_assignment, :user)
        user = assignment.assignable
        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
        logs = capture_logs do
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          assert authorizer.access_allowed?
          assert_equal "copilot_for_business_seat_assignment", authorizer.access_type_sku
        end
        assert_includes logs, "User has at least one seat assignment"
      end

      test "team CFB Seat assignment" do
        user = create(:user)
        assignment = create(:copilot_seat_assignment, :team)
        team = assignment.assignable
        team.add_member(user)
        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
        logs = capture_logs do
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          assert authorizer.access_allowed?
          assert_equal "copilot_for_business_seat_assignment", authorizer.access_type_sku
        end
        assert_includes logs, "User has at least one seat assignment"
      end

      test "organization CFB Seat assignment" do
        user = create(:user)
        assignment = create(:copilot_seat_assignment, :organization)
        organization = assignment.assignable
        organization.add_member(user)
        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
        logs = capture_logs do
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          assert authorizer.access_allowed?
          assert_equal "copilot_for_business_seat_assignment", authorizer.access_type_sku
        end
        assert_includes logs, "User has at least one seat assignment"

      end

      test "enterprise team seat assignment" do
        assignment = create(:copilot_seat_assignment, :enterprise_team)
        enterprise_team = assignment.assignable
        user_id = enterprise_team.member_user_ids.first
        user = User.find(user_id)
        Copilot::Business.new(assignment.owner).allow_public_code_suggestions!

        capture_logs do
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          assert authorizer.access_allowed?
          assert_equal "copilot_standalone_seat_assignment", authorizer.access_type_sku
        end
      end

      test "user CFB Seat assignment for billing locked owner" do
        assignment = create(:copilot_seat_assignment, :user)
        user = assignment.assignable
        assignment.owner.disable!
        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        refute authorizer.access_allowed?
        assert_equal "copilot_for_business_billing_locked", authorizer.access_type_sku
      end
    end

    context "billing_check" do
      context "monthly" do
        context "trial" do
          test "trial monthly without snippy" do
            copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)

            plan_subscription = create(:billing_plan_subscription, :zuora)
            user = plan_subscription.user

            create(:billing_subscription_item, :paid,
              plan_subscription: plan_subscription,
              subscribable: copilot_monthly_product_uuid,
              free_trial_ends_on: 60.days.from_now
            )
            authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
            refute authorizer.access_allowed?
            assert_equal "snippy_not_configured", authorizer.access_type_sku
          end

          test "trial monthly with snippy" do
            Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
            Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
            copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)

            plan_subscription = create(:billing_plan_subscription, :zuora)
            user = plan_subscription.user

            create(:billing_subscription_item, :paid,
              plan_subscription: plan_subscription,
              subscribable: copilot_monthly_product_uuid,
              free_trial_ends_on: 60.days.from_now
            )
            authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
            assert authorizer.access_allowed?
            assert_equal "trial_30_monthly_subscriber", authorizer.access_type_sku
          end
        end

        context "no trial" do
          test "monthly without snippy" do
            copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)

            plan_subscription = create(:billing_plan_subscription, :zuora)
            user = plan_subscription.user

            create(:billing_subscription_item, :paid,
              plan_subscription: plan_subscription,
              subscribable: copilot_monthly_product_uuid,
              free_trial_ends_on: 5.days.ago
            )
            authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
            refute authorizer.access_allowed?
            assert_equal "snippy_not_configured", authorizer.access_type_sku
          end

          test "monthly with snippy" do
            Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
            Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
            copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)

            plan_subscription = create(:billing_plan_subscription, :zuora)
            user = plan_subscription.user

            create(:billing_subscription_item, :paid,
              plan_subscription: plan_subscription,
              subscribable: copilot_monthly_product_uuid,
              free_trial_ends_on: 5.days.ago
            )
            authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
            assert authorizer.access_allowed?
            assert_equal "monthly_subscriber", authorizer.access_type_sku
          end
        end
      end

      context "yearly" do
        context "trial" do
          test "trial yearly without snippy" do
            copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)

            plan_subscription = create(:billing_plan_subscription, :zuora)
            user = plan_subscription.user

            create(:billing_subscription_item, :paid,
              plan_subscription: plan_subscription,
              subscribable: copilot_yearly_product_uuid,
              free_trial_ends_on: 60.days.from_now
            )
            authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
            refute authorizer.access_allowed?
            assert_equal "snippy_not_configured", authorizer.access_type_sku
          end

          test "trial yearly with snippy" do
            Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
            Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
            copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)

            plan_subscription = create(:billing_plan_subscription, :zuora)
            user = plan_subscription.user

            create(:billing_subscription_item, :paid,
              plan_subscription: plan_subscription,
              subscribable: copilot_yearly_product_uuid,
              free_trial_ends_on: 60.days.from_now
            )
            authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
            assert authorizer.access_allowed?
            assert_equal "trial_30_yearly_subscriber", authorizer.access_type_sku
          end
        end

        context "no trial" do
          test "yearly without snippy" do
            copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)

            plan_subscription = create(:billing_plan_subscription, :zuora)
            user = plan_subscription.user

            create(:billing_subscription_item, :paid,
              plan_subscription: plan_subscription,
              subscribable: copilot_yearly_product_uuid,
              free_trial_ends_on: 5.days.ago
            )
            authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
            refute authorizer.access_allowed?
            assert_equal "snippy_not_configured", authorizer.access_type_sku
          end

          test "monthly with snippy" do
            Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
            Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
            copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)

            plan_subscription = create(:billing_plan_subscription, :zuora)
            user = plan_subscription.user

            create(:billing_subscription_item, :paid,
              plan_subscription: plan_subscription,
              subscribable: copilot_yearly_product_uuid,
              free_trial_ends_on: 5.days.ago
            )
            authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
            assert authorizer.access_allowed?
            assert_equal "yearly_subscriber", authorizer.access_type_sku
          end
        end
      end
    end

    context "async_expired_coupon_check" do
      test "valid coupon" do
        Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
        Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
        free_user = create(
          :copilot_free_user,
          :educational_redeemed,
          subscribed: true,
        )
        user = free_user.user

        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        assert authorizer.access_allowed?
        assert_equal "free_educational", authorizer.access_type_sku
      end

      test "expired coupon" do
        Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
        Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
        free_user = create(
          :copilot_free_user,
          :educational_redeemed,
          user: create(:credit_card_user),
          subscribed: true,
        )
        user = free_user.user
        user.expire_active_coupon
        user.reload
        free_user.destroy

        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        refute authorizer.access_allowed?
        assert_equal "expired_coupon", authorizer.access_type_sku
      end

      test "revoke coupon" do
        Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
        Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
        free_user = create(
          :copilot_free_user,
          :educational_redeemed,
          user: create(:credit_card_user),
          subscribed: true,
        )
        user = free_user.user
        user.expire_active_coupon
        user.reload
        free_user.destroy

        code = "revoked"
        coupon = Coupon.find_by(code: code) || create(:coupon, code: code)
        coupon.update(limit: 9999)
        user.redeem_coupon(coupon)

        authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
        refute authorizer.access_allowed?
        assert_equal "revoked_coupon", authorizer.access_type_sku
      end

      context "query counts do not scale linearly with the user's number of organizations" do
        test "for a user with no access" do
          user = create(:user)
          assert_query_counts(15) do
            authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
            refute authorizer.access_allowed?
          end
        end

        test "for a CfI user with many orgs" do
          Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
          Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
          copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)

          plan_subscription = create(:billing_plan_subscription, :zuora)
          user = plan_subscription.user

          create(:billing_subscription_item, :paid,
            plan_subscription: plan_subscription,
            subscribable: copilot_monthly_product_uuid,
            free_trial_ends_on: 5.days.ago
          )

          10.times do
            org = create(:organization)
            org.add_member(user)
          end

          assert_query_counts(18) do
            authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
            assert authorizer.access_allowed?
          end
        end
      end
    end

    context "limited_user" do
      context "FREE_LIMITED_COPILOT" do
        test "gotta be in the feature flag" do
          user = create(:user)
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          refute authorizer.access_allowed?
          assert_equal "no_access", authorizer.access_type_sku
        end

        test "being in the feature flag isn't enough" do
          user = create(:user)
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          refute authorizer.access_allowed?
          assert_equal "no_access", authorizer.access_type_sku
        end

        test "you need to have subscribed" do
          user = create(:user)
          create(:copilot_limited_user, user: user, subscribed_at: nil)
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          refute authorizer.access_allowed?
          assert_equal "no_access", authorizer.access_type_sku
        end

        test "if you subscribe, that's cool but you also have to setup snippy" do
          user = create(:user)
          create(:copilot_limited_user, user: user, subscribed_at: Time.now)
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          refute authorizer.access_allowed?
          assert_equal "snippy_not_configured", authorizer.access_type_sku
        end

        test "nice job setting up snippy but you don't have any quota" do
          user = create(:user)
          create(:copilot_limited_user, user: user, subscribed_at: Time.now)
          Copilot::User.any_instance.expects(:has_completions_quota_remaining?).returns(false)
          Copilot::User.any_instance.expects(:has_chat_quota_remaining?).returns(false)
          Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
          Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          assert_equal "free_limited_copilot", authorizer.access_type_sku
          assert authorizer.access_allowed?
        end

        test "nice job setting up snippy and you have quota" do
          user = create(:user)
          create(:copilot_limited_user, user: user, subscribed_at: Time.now)
          Copilot::User.any_instance.expects(:has_completions_quota_remaining?).returns(true) # the chat quota never gets checked
          Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
          Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
          authorizer = Copilot::Authorizer.new(Copilot::User.new(user), @context)
          assert_equal "free_limited_copilot", authorizer.access_type_sku
          assert authorizer.access_allowed?
        end
      end
    end
  end
end if GitHub.copilot_enabled?
