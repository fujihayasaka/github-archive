# typed: true
# frozen_string_literal: true

require "test_helper"

class TwoFactorRecoveryRequestReviewTest < GitHub::TestCase
  include AuditLogHelpers
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @user = create(:two_factor_credential_user, login: "user", created_at: Time.now - 60.days)

    @request = create(:completed_two_factor_recovery_request_token, user: @user, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)
    @timestamp = 2.days.ago.freeze

    @deceased_user = create(:two_factor_credential_user, login: "deceased")

    @deceased_user.mark_deceased

    @staff_user = create(:staff_admin_user)
    @time = Time.now.freeze

    @user_with_backup_email = create(:two_factor_credential_user, login: "user-backup-email")
    backup_email = @user_with_backup_email.add_email("backup-verified-email@example.com")
    backup_email.verify!
    @user_with_backup_email.set_backup_email(backup_email)

    @user_with_unverified_backup_email = create(:two_factor_credential_user, login: "user-unverified-backup-email")
    unverified_backup_email = @user_with_unverified_backup_email.add_email("backup-unverified-email@example.com")
    unverified_backup_email.verify!
    @user_with_unverified_backup_email.set_backup_email(unverified_backup_email)
    unverified_backup_email.unverify!

    @verified_device_user = create(:user, login: "verified-device-user", created_at: Time.now - 60.days)
    @verified_device = create(:authenticated_device, user: @verified_device_user, approved_at: Time.now - 60.days)
    @verified_device_request = create(:completed_two_factor_recovery_request_token, user: @verified_device_user, authenticated_device: @verified_device, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)

    @public_key_user = create(:two_factor_credential_user, login: "pk-user", created_at: Time.now - 60.days)
    @public_key = create(:public_key, user: @public_key_user)
    @public_key_authed_request = create(:completed_two_factor_recovery_request_token, user: @public_key_user, public_key_id: @public_key.id, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)

    @sponsorable_high_value_subscription_user = create(:credit_card_user, :sponsorable,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )

    GitHub.flipper[:phoenix_two_factor_lockout_request_flow].enable(@sponsorable_high_value_subscription_user)

    threshold = 1000_00

    high_value_tier = create(:sponsors_tier, :published,
      sponsors_listing: @sponsorable_high_value_subscription_user.sponsors_listing,
      monthly_price_in_cents: threshold,
      yearly_price_in_cents: threshold * 12)

    sponsor = create(:credit_card_user, :sponsorable,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )

    create(:sponsorship, sponsorable: @sponsorable_high_value_subscription_user, sponsor: sponsor,
      tier: high_value_tier)

    @sponsorable_high_value_tier_user = create(:credit_card_user, :sponsorable,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )

    GitHub.flipper[:phoenix_two_factor_lockout_request_flow].enable(@sponsorable_high_value_tier_user)

    create(:sponsors_tier, :published,
      sponsors_listing: @sponsorable_high_value_tier_user.sponsors_listing,
      monthly_price_in_cents: 6000_00,
      yearly_price_in_cents: 6000_00 * 12)

    @user_with_large_number_of_sponsors = create(:credit_card_user, :sponsorable,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )

    GitHub.flipper[:phoenix_two_factor_lockout_request_flow].enable(@user_with_large_number_of_sponsors)

    5.times { create(:sponsorship, sponsorable: @user_with_large_number_of_sponsors) }

    @user_with_some_small_sponsors = create(:credit_card_user, :sponsorable,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )

    GitHub.flipper[:phoenix_two_factor_lockout_request_flow].enable(@user_with_some_small_sponsors)

    2.times { create(:sponsorship, sponsorable: @user_with_some_small_sponsors) }
    GitHub.flipper[:recovery_without_password_flagging].disable

    GitHub.flipper[:members_without_2fa_allowed].disable
  end

  unless GitHub.enterprise?
    context "required order of operations" do
      #     [ **** IMPORTANT **** ]

      # The ordering of our conditional checks is extremely important, as the review
      # process does not need to exhaust all checks. As soon as a problem is found,
      # the request is considered marked for manual review and no automation will
      # be performed.
      #
      # If a user is staff or deceased they need manual intervention - no exceptions.
      #
      # In any other case we render a staff reviewable list of emails in the approval
      # modal **ONLY** when their email settings are identified as a problem. We
      # need to ensure their email settings are checked first, as this method exits
      # as soon as a problem is identified.
      #
      # Since Organization memberships are the most resource intensive check
      # we have placed them last to lessen the burden on our MySQL clusters.
      #
      # Keep this in mind if adding any new checks to this flow
      test "conditions are triggered in expected order" do

        review = new_automated_review
        ordered_checks = sequence("correct_order")
        @request.expects(:user).in_sequence(ordered_checks).returns(@user)
        @user.expects(:type).in_sequence(ordered_checks).returns("User")
        @user.expects(:site_admin?).in_sequence(ordered_checks)
        @user.expects(:deceased?).in_sequence(ordered_checks)
        review.expects(:check_emails).in_sequence(ordered_checks)
        review.expects(:check_audit_logs).in_sequence(ordered_checks)
        review.expects(:check_sponsorships).in_sequence(ordered_checks)
        review.expects(:check_org_membership).in_sequence(ordered_checks)

        review.expects(:event_payload).in_sequence(ordered_checks).returns({})
        review.expects(:instrument_risk_assesment).in_sequence(ordered_checks)
        review.expects(:instrument_hydro).in_sequence(ordered_checks)

        review.perform
      end
    end

    context "#assess_risk" do
      test "review not required when automation is possible" do
        review = new_automated_review
        review.perform

        refute review.review_required?
        assert_nil review.message
        assert_nil review.type
        assert_nil review.reason
        assert_nil review.audit_entry_time
      end

      # Sometimes we want more granuality for deciding whether to send for manual review than "does a log of X type exist"
      # we want to check other conditions as well, sometimes a log of X type is OK to have if other positive indicators present
      context "more complex event handling logic" do
        context "password reset account recovery" do
          test "request is flagged for 'without_password' reason if current request is passwordless" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            review = new_automated_review(request: @request, without_password: true)
            time = @verified_device_request.created_at - 1.day
            client_id = 12345

            review.perform
            assert review.review_required?
            assert_equal "Recovery request was initiated without user password.", review.message
            assert_equal "without_password", review.type
            assert_equal "without_password", review.reason
          end

          test "when passwordless request is flagged for unrelated reasons, passwordless context is still tracked" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            request = create(:completed_two_factor_recovery_request_token, user: @staff_user, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)

            events = subscribe "two_factor_account_recovery_review.risk_assessment"
            review = new_automated_review(user: @staff_user, request: request, without_password: true)

            Timecop.freeze(@time) do
              review.perform
            end

            assert review.review_required?
            assert_equal "User is staff member", review.message
            assert_equal "staff", review.type
            assert_nil review.reason
            assert_nil review.audit_entry_time

            assert event = events.pop, "an event was expected"
            assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

            result = { request.id => { "review_required" => true, "message" => "User is staff member", "type" => "staff", "reason" => nil, "without_password" => true, "two_factor_account_recovery_id" => request.id, "performed_at" => "#{@time}" } }.to_json

            expected_payload = {
              review_required: true,
              message: "User is staff member",
              type: "staff",
              reason: nil,
              without_password: true,
              two_factor_account_recovery_id: request.id,
              user: @staff_user.login,
              user_id: @staff_user.id,
            }

            assert_equal expected_payload, event.payload
            assert_equal result, TwoFactorRecoveryRequestReview.mget([request.id]).to_json
          end

          test "flags when initiate event is missing" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            review = TwoFactorRecoveryRequestReview.new(@request)

            review.perform

            assert review.review_required?
            assert_equal "Recovery request audit log context is missing.", review.message
            assert_equal "without_password", review.type
            assert_equal "password_context_missing", review.reason
            assert_nil review.audit_entry_time
          end

          test "flags when initiate event entry point is unrecognized" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            review = TwoFactorRecoveryRequestReview.new(@request)

            initiate_entry = [{ :actor_ip => "127.0.0.1",
              :actor_location => { "location" => { "lat" => 0.0, "lon" => 0.0 } },
              :note => "From github.localhost",
              :user => @user.login,
              :user_id => @user.id,
              :two_factor_account_recovery_id => @request.id,
              :controller_action => "unknown",
              :action => "two_factor_account_recovery.initiate",
              :operation_type => "authentication",
              :@timestamp => (@time.to_i * 1000)
            }]

            review.stubs(:recovery_initiate_user_actions).returns(initiate_entry) if GitHub.flipper[:recovery_without_password_flagging].enabled?
            review.perform

            assert review.review_required?
            assert_equal "Recovery request was initiated from unknown entry point.", review.message
            assert_equal "without_password", review.type
            assert_equal "password_context_unexpected", review.reason
            assert_nil review.audit_entry_time
          end

          test "review not required if password reset recovery request shares client_id with recent partial login event" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            GitHub.flipper[:recovery_without_password_partial_login_auto].enable
            client_id = 12351234
            review = new_automated_review(request: @request, without_password: true, client_id: 12351234)
            time = @request.created_at - 10.minutes
            entries = [{ :client_id => client_id,
              :user => @user.login,
              :user_id => @user.id,
              :from => "sessions#create",
              :action => "user.two_factor_requested",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }]

            review.expects(:recent_user_actions).at_least_once.returns(entries)
            review.expects(:recent_partial_login_actions).at_least_once.returns(entries)
            review.perform
            refute review.review_required?
          end

          test "review required if password reset recovery request doesn't have any partial login events" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            GitHub.flipper[:recovery_without_password_partial_login_auto].enable
            client_id = 12351234
            review = new_automated_review(request: @request, without_password: true, client_id: 12351234)
            time = @request.created_at - 10.minutes

            review.expects(:recent_user_actions).at_least_once.returns([])
            review.expects(:recent_partial_login_actions).at_least_once.returns([])
            review.perform
            assert review.review_required?
            assert_equal "Recovery request was initiated without user password.", review.message
            assert_equal "without_password", review.type
            assert_equal "without_password", review.reason
          end

          test "review required if password reset recovery request doesn't share client_id with recent partial login event" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            GitHub.flipper[:recovery_without_password_partial_login_auto].enable
            client_id = 12351234
            review = new_automated_review(request: @request, without_password: true, client_id: 12351234)
            time = @request.created_at - 10.minutes
            entries = [{ :client_id => client_id + 1,
              :user => @user.login,
              :user_id => @user.id,
              :from => "sessions#create",
              :action => "user.two_factor_requested",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }]

            review.expects(:recent_user_actions).at_least_once.returns(entries)
            review.expects(:recent_partial_login_actions).at_least_once.returns(entries)
            review.perform
            assert review.review_required?
            assert_equal "Partial login event found from different client ID.", review.message
            assert_equal "without_password", review.type
            assert_equal "password_usage_from_different_device", review.reason
          end

          test "review required if password reset recovery request has old partial login event" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            GitHub.flipper[:recovery_without_password_partial_login_auto].enable
            client_id = 12351234
            review = new_automated_review(request: @request, without_password: true, client_id: 12351234)
            time = @request.created_at - 40.minutes
            entries = [{ :client_id => client_id,
              :user => @user.login,
              :user_id => @user.id,
              :from => "sessions#create",
              :action => "user.two_factor_requested",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }]

            review.expects(:recent_user_actions).at_least_once.returns(entries)
            review.expects(:recent_partial_login_actions).at_least_once.returns(entries)
            review.perform
            assert review.review_required?
            assert_equal "Recovery request was initiated without user password.", review.message
            assert_equal "without_password", review.type
            assert_equal "without_password", review.reason
          end

          test "review required if password reset recovery request has partial login event after request was created" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            GitHub.flipper[:recovery_without_password_partial_login_auto].enable
            client_id = 12351234
            review = new_automated_review(request: @request, without_password: true, client_id: 12351234)
            time = @request.created_at + 10.minutes
            entries = [{ :client_id => client_id,
              :user => @user.login,
              :user_id => @user.id,
              :from => "sessions#create",
              :action => "user.two_factor_requested",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }]

            review.expects(:recent_user_actions).at_least_once.returns(entries)
            review.expects(:recent_partial_login_actions).at_least_once.returns(entries)
            review.perform
            assert review.review_required?
            assert_equal "Recovery request was initiated without user password.", review.message
            assert_equal "without_password", review.type
            assert_equal "without_password", review.reason
          end

          test "review required if password reset recovery request has one non-matching partial login event" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            GitHub.flipper[:recovery_without_password_partial_login_auto].enable
            client_id = 12351234
            review = new_automated_review(request: @request, without_password: true, client_id: 12351234)
            time = @request.created_at - 10.minutes
            matching = { :client_id => client_id,
              :user => @user.login,
              :user_id => @user.id,
              :from => "sessions#create",
              :action => "user.two_factor_requested",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }
            non_matching = { :client_id => client_id + 1,
              :user => @user.login,
              :user_id => @user.id,
              :from => "sessions#create",
              :action => "user.two_factor_requested",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }

            entries = [matching, non_matching]

            review.expects(:recent_user_actions).at_least_once.returns(entries)
            review.expects(:recent_partial_login_actions).at_least_once.returns(entries)
            review.perform
            assert review.review_required?
            assert_equal "Partial login event found from different client ID.", review.message
            assert_equal "without_password", review.type
            assert_equal "password_usage_from_different_device", review.reason
          end

          test "review required after 1 day wait if password reset recovery request has one non-matching partial login event" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            GitHub.flipper[:recovery_without_password_partial_login_auto].enable
            client_id = 12351234
            review = new_automated_review(request: @request, without_password: true, client_id: 12351234)
            time = @request.created_at - 10.minutes
            matching = { :client_id => client_id,
              :user => @user.login,
              :user_id => @user.id,
              :from => "sessions#create",
              :action => "user.two_factor_requested",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }
            non_matching = { :client_id => client_id + 1,
              :user => @user.login,
              :user_id => @user.id,
              :from => "sessions#create",
              :action => "user.two_factor_requested",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }

            entries = [matching, non_matching]

            review.expects(:recent_user_actions).at_least_once.returns(entries)
            review.expects(:recent_partial_login_actions).at_least_once.returns(entries)

            Timecop.freeze(@request.created_at + 1.day) do
              review.perform
            end

            assert review.review_required?
            assert_equal "Partial login event found from different client ID.", review.message
            assert_equal "without_password", review.type
            assert_equal "password_usage_from_different_device", review.reason
          end

          test "review not required if password reset recovery request has one different partial login event that matches a previous login" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            GitHub.flipper[:recovery_without_password_partial_login_auto].enable
            client_id = 12351234
            review = new_automated_review(request: @request, without_password: true, client_id: 12351234)
            time = @request.created_at - 10.minutes
            matching = { :client_id => client_id,
              :user => @user.login,
              :user_id => @user.id,
              :from => "sessions#create",
              :action => "user.two_factor_requested",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }
            non_matching = { :client_id => client_id + 1,
              :user => @user.login,
              :user_id => @user.id,
              :from => "sessions#create",
              :action => "user.two_factor_requested",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }

            prevous_login = { :client_id => client_id + 1,
              :user => @user.login,
              :user_id => @user.id,
              :from => "sessions#create",
              :action => "user.login",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }

            entries = [matching, non_matching]

            review.expects(:recent_user_actions).at_least_once.returns(entries)
            review.expects(:past_login_user_actions).at_least_once.returns([prevous_login])
            review.expects(:recent_partial_login_actions).at_least_once.returns(entries)
            review.perform
            refute review.review_required?
          end

          test "emits hydro event" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            review = new_automated_review(without_password: true)

            review.perform

            assert_hydro_published({
              user: Hydro::EntitySerializer.user(@user),
              review_required: true,
              reason_type: :WITHOUT_PASSWORD,
            }, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")

            assert_hydro_messages(count: 1, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")
          end

          test "stores result in KV" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            review = new_automated_review

            result = { @request.id => { "review_required" => false, "without_password" => false, "two_factor_account_recovery_id" => @request.id, "performed_at" => "#{@time}" } }.to_json

            Timecop.freeze(@time) do
              review.perform
            end
            assert_equal result, TwoFactorRecoveryRequestReview.mget([@request.id]).to_json
          end

          test "stores passwordless result in KV" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            review = new_automated_review(without_password: true)

            result = { @request.id => { "review_required" => true, "message" => "Recovery request was initiated without user password.", "type" => "without_password", "reason" => "without_password", "without_password" => true, "two_factor_account_recovery_id" => @request.id, "performed_at" => "#{@time}" } }.to_json

            Timecop.freeze(@time) do
              review.perform
            end
            assert_equal result, TwoFactorRecoveryRequestReview.mget([@request.id]).to_json
          end

          test "stores additional context in KV when review required" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            business = create :business, owners: [@user]
            business.enable_two_factor_required actor: business.owners.first, force: true
            review = new_automated_review

            result = { @request.id => { "review_required" => true, "message" => "User is affiliated with business that requires 2FA", "type" => "org_membership", "reason" => "business_affiliation", "without_password" => false, "two_factor_account_recovery_id" => @request.id, "performed_at" => "#{@time}" } }.to_json
            Timecop.freeze(@time) do
              review.perform
            end
            assert_equal result, TwoFactorRecoveryRequestReview.mget([@request.id]).to_json
          end
        end

        context "exceptions allowing auto-approval" do
          ["ip address", "location"].each do |location_info|
            test "review not required if user has logged in from same #{location_info} as recovery request event" do
              review = new_automated_review
              time = Time.now
              ip = location_info == "ip address" ? "127.0.0.1" : nil
              location = location_info == "location" ? { "location" => { "lat" => 0.0, "lon" => 0.0 } } : nil
              entries = [{ :actor_ip => ip,
                :actor_location => location,
                :actor => @user.login,
                :actor_id => @user.id,
                :note => "From github.localhost",
                :user => @user.login,
                :user_id => @user.id,
                :action => "user.login",
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000)
              }]
              request_entry = [{ :actor_ip => "127.0.0.1",
                :actor_location => { "location" => { "lat" => 0.0, "lon" => 0.0 } },
                :note => "From github.localhost",
                :user => @user.login,
                :user_id => @user.id,
                :action => "two_factor_account_recovery.complete",
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000)
              }]

              review.expects(:recent_user_actions).at_least_once.returns(entries)
              review.expects(:recovery_submit_user_actions).at_least_once.returns(request_entry)
              review.perform
              assert_dogstats_increment 1, "two_factor_recovery_request_review.resolvable_risk", tags: ["reason:account_self_recovered"]
              refute review.review_required?
            end
          end

          TwoFactorRecoveryRequestReview::EMAIL_ACTIONS_NEW_ACCOUNT_EXPECTED.each do |expected_action|
            test "review not required if account is new and expected action #{expected_action} present in audit log" do
              new_user = create(:user, login: "new-user", created_at: Time.now - 5.days)
              request = create(:completed_two_factor_recovery_request_token, user: new_user, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)
              review = new_automated_review(user: new_user, request: request)
              time = Time.now
              entries = [{ :actor_ip => "127.0.0.1",
                :actor => new_user.login,
                :actor_id => new_user.id,
                :note => "From github.localhost",
                :user => new_user.login,
                :user_id => new_user.id,
                :action => expected_action,
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000)
              }]

              review.expects(:recent_user_actions).at_least_once.returns(entries)
              review.perform
              refute review.review_required?
            end
          end

          TwoFactorRecoveryRequestReview::POTENTIAL_TAKEOVER_INDICATORS.excluding(TwoFactorRecoveryRequestReview::AUTOMATIC_FLAG_ACTIONS).each do |ato_action|
            test "review not required if recovery request used verified device, and the request client_id matches a historical login client_id, action: #{ato_action}" do
              review = new_automated_review(user: @verified_device_user, request: @verified_device_request)
              time = @verified_device_request.created_at - 1.day
              client_id = 123456
              entries = [{ :client_id => client_id,
                :user => @verified_device_user.login,
                :user_id => @verified_device_user.id,
                :action => ato_action,
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000)
              }]
              past_login_entry = [{ :actor_id => @verified_device_user.id,
                :client_id => client_id,
                :user => @verified_device_user.login,
                :user_id => @verified_device_user.id,
                :action => "user.login",
                :operation_type => "authentication",
                :@timestamp => ((time - 10.months).to_i * 1000)
              }]

              review.expects(:recent_user_actions).at_least_once.returns(entries)
              review.expects(:past_login_user_actions).at_least_once.returns(past_login_entry)
              review.perform
              assert_dogstats_increment 1, "two_factor_recovery_request_review.resolvable_risk", tags: ["reason:verified_device_and_historical_client_used"]
              refute review.review_required?
            end
          end

          TwoFactorRecoveryRequestReview::AUTOMATIC_FLAG_ACTIONS.each do |ato_action|
            test "review required when recovery user has flagged audit log events, action: #{ato_action}" do
              GitHub.flipper[:recovery_without_password_flagging].disable
              review = new_automated_review
              time = @request.created_at - 1.day
              entries = [{ :client_id => 123456,
                :user => @user.login,
                :user_id => @user.id,
                :action => ato_action,
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000)
              }]

              review.expects(:recent_user_actions).at_least_once.returns(entries)
              # requests don't hit the other checks for `is_ato_risk_resolvable?`
              review.expects(:past_login_user_actions).never
              review.perform
              assert review.review_required?
              assert_equal "A #{ato_action} event was found for this user in the audit log before starting this recovery request.", review.message
              assert_equal "audit_log", review.type
              assert_equal ato_action, review.reason
              assert_equal time.to_i, review.audit_entry_time.to_i
            end
          end

          test "user.initiate_two_factor_recovery_without_password can actually be risk resolved if it's unrelated to the current request" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            review = new_automated_review(user: @verified_device_user, request: @verified_device_request, without_password: false)
            time = @verified_device_request.created_at - 1.day
            client_id = 123456
            entries = [{ :client_id => client_id,
              :user => @verified_device_user.login,
              :user_id => @verified_device_user.id,
              :action => "user.initiate_two_factor_recovery_without_password",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }]

            review.expects(:recent_user_actions).at_least_once.returns(entries)
            review.perform
            refute review.review_required?
          end

          test "user.initiate_two_factor_recovery_without_password won't flag at all if unrelated to the current request" do
            GitHub.flipper[:recovery_without_password_flagging].enable
            review = new_automated_review(request: @request, without_password: false)
            time = @request.created_at - 1.day
            client_id = 123456
            entries = [{ :client_id => client_id,
              :user => @user.login,
              :user_id => @user.id,
              :action => "user.initiate_two_factor_recovery_without_password",
              :operation_type => "authentication",
              :@timestamp => (time.to_i * 1000)
            }]

            review.expects(:recent_user_actions).at_least_once.returns(entries)
            review.perform
            refute_dogstats_increment("two_factor_recovery_request_review.resolvable_risk")
            refute review.review_required?
          end

          TwoFactorRecoveryRequestReview::UNRECOGNIZED_LOCATION_ACTIONS.each do |weak_ato_indicator|
            ["ip address", "location"].each do |location_info|
              test "review not required if possible takeover event is weak indicator #{weak_ato_indicator} and event matches #{location_info} of a historical login event" do
                review = new_automated_review
                time = @request.created_at - 1.day
                ip = location_info == "ip address" ? "127.0.0.1" : nil
                location = location_info == "location" ? { "location" => { "lat" => 0.0, "lon" => 0.0 } } : nil
                entries = [{ :actor_id => @user.id,
                  :actor_ip => ip,
                  :actor_location => location,
                  :user => @user.login,
                  :user_id => @user.id,
                  :action => weak_ato_indicator,
                  :operation_type => "authentication",
                  :@timestamp => (time.to_i * 1000)
                }]
                past_login_entry = [{ :actor_id => @user.id,
                  :actor_ip => ip,
                  :actor_location => location,
                  :user => @user.login,
                  :user_id => @user.id,
                  :action => "user.login",
                  :operation_type => "authentication",
                  :@timestamp => ((time - 10.months).to_i * 1000)
                }]

                review.expects(:recent_user_actions).at_least_once.returns(entries)
                review.expects(:past_login_user_actions).at_least_once.returns(past_login_entry)
                review.perform
                assert_dogstats_increment 1, "two_factor_recovery_request_review.resolvable_risk", tags: ["reason:weak_ato_location_heuristic"]
                refute review.review_required?
              end
            end
          end

          test "review not required if user created a public key recently but authenticated request with different factor" do
            review = new_automated_review
            action = "public_key.create"
            entries = [{ :actor_ip => "127.0.0.1",
              :actor => @user.login,
              :actor_id => @user.id,
              :actor_location => { "location" => { "lat" => 0.0, "lon" => 0.0 } },
              :user => @user.login,
              :user_id => @user.id,
              :action => action,
              :operation_type => "create",
              :@timestamp => (@timestamp.to_i * 1000)
            }]

            review.expects(:recent_user_actions).at_least_once.returns(entries)
            review.perform
            assert_dogstats_increment 1, "two_factor_recovery_request_review.resolvable_risk", tags: ["reason:public_key_create_different_evidence"]
            refute review.review_required?
          end
        end

        context "even if one event is resolved/ignorable, still require review if other events present" do
          TwoFactorRecoveryRequestReview::POST_REQUEST_FLAGGED_ACTIONS.excluding("user.login").each do |flagged_action|
            test "review required: post request flagged event resolved, remaining post request flagged event #{flagged_action}" do
              review = new_automated_review
              time = Time.now
              resolved_event = { :actor_ip => "127.0.0.1",
                :actor => @user.login,
                :actor_id => @user.id,
                :note => "From github.localhost",
                :user => @user.login,
                :user_id => @user.id,
                :action => "user.login",
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000)
              }
              flagged_time = @request.created_at + 1.day
              flagged_event = { :actor_ip => "192.168.0.1", # presence will cause flagging
                :note => "Suspicious",
                :user => @user.login,
                :user_id => @user.id,
                :action => flagged_action,
                :operation_type => "authentication",
                :@timestamp => (flagged_time.to_i * 1000)
              }
              resolving_events = [{ :actor_ip => "127.0.0.1", # presence will resolve resolved_event
                :note => "From github.localhost",
                :user => @user.login,
                :user_id => @user.id,
                :action => "two_factor_account_recovery.complete",
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000 + 1.day)
              }]
              entries = [resolved_event, flagged_event]

              review.expects(:recent_user_actions).at_least_once.returns(entries)
              review.expects(:recovery_submit_user_actions).at_least_once.returns(resolving_events)
              review.perform
              assert review.review_required?
              assert_equal "A #{flagged_action} event was found for this user in the audit log after this recovery request was initiated.", review.message
              assert_equal "audit_log", review.type
              assert_equal flagged_action, review.reason
              assert_equal flagged_time.to_i, review.audit_entry_time.to_i
            end
          end

          TwoFactorRecoveryRequestReview::EMAIL_ACTIONS.each do |email_action|
            test "review required: post request flagged event resolved, remaining email event #{email_action}" do
              review = new_automated_review
              time = Time.now
              resolved_event = { :actor_ip => "127.0.0.1",
                :actor => @user.login,
                :actor_id => @user.id,
                :note => "From github.localhost",
                :user => @user.login,
                :user_id => @user.id,
                :action => "user.login",
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000)
              }
              email_time = time
              email_event = { :actor_ip => "192.168.0.1", # presence will cause flagging
                :email => @user.email,
                :note => "Suspicious",
                :user => @user.login,
                :user_id => @user.id,
                :action => email_action,
                :operation_type => "authentication",
                :@timestamp => (email_time.to_i * 1000)
              }
              resolving_events = [{ :actor_ip => "127.0.0.1", # presence will resolve resolved_event
                :note => "From github.localhost",
                :user => @user.login,
                :user_id => @user.id,
                :action => "two_factor_account_recovery.complete",
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000 + 1.day)
              }]
              entries = [resolved_event, email_event]

              review.expects(:recent_user_actions).at_least_once.returns(entries)
              review.expects(:recovery_submit_user_actions).at_least_once.returns(resolving_events)
              review.perform
              assert review.review_required?
              assert_equal "A #{email_action} event was found for this user in the audit log for the email address: #{email_event[:email]}.", review.message
              assert_equal "audit_log", review.type
              assert_equal email_action, review.reason
              assert_equal email_time.to_i, review.audit_entry_time.to_i
            end
          end

          TwoFactorRecoveryRequestReview::POTENTIAL_TAKEOVER_INDICATORS.each do |ato_action|
            test "review required: post request flagged event resolved, remaining takeover event #{ato_action}" do
              review = new_automated_review(user: @public_key_user, request: @public_key_authed_request)
              time = Time.now
              resolved_event = { :actor_ip => "127.0.0.1",
                :actor => @public_key_user.login,
                :actor_id => @public_key_user.id,
                :note => "From github.localhost",
                :user => @public_key_user.login,
                :user_id => @public_key_user.id,
                :action => "user.login",
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000)
              }
              ato_time = @request.created_at - 1.day
              ato_event = { :actor_ip => "192.168.0.1", # presence will cause flagging
                :note => "Suspicious",
                :user => @public_key_user.login,
                :user_id => @public_key_user.id,
                :action => ato_action,
                :operation_type => "authentication",
                :public_key_id => @public_key.id,
                :@timestamp => (ato_time.to_i * 1000)
              }
              resolving_events = [{ :actor_ip => "127.0.0.1", # presence will resolve resolved_event
                :note => "From github.localhost",
                :user => @public_key_user.login,
                :user_id => @public_key_user.id,
                :action => "two_factor_account_recovery.complete",
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000 + 1.day)
              }]
              entries = [resolved_event, ato_event]

              review.expects(:recent_user_actions).at_least_once.returns(entries)
              review.expects(:recovery_submit_user_actions).at_least_once.returns(resolving_events)
              review.perform
              assert review.review_required?
              assert_equal "A #{ato_action} event was found for this user in the audit log before starting this recovery request.", review.message
              assert_equal "audit_log", review.type
              assert_equal ato_action, review.reason
              assert_equal ato_time.to_i, review.audit_entry_time.to_i
            end
          end

          TwoFactorRecoveryRequestReview::EMAIL_ACTIONS_NEW_ACCOUNT_EXPECTED.each do |expected_action|
            TwoFactorRecoveryRequestReview::EMAIL_ACTIONS_NEW_ACCOUNT_UNEXPECTED.each do |email_action|
              test "review required: new account does not flag for email event #{expected_action}, remaining email event #{email_action}" do
                new_user = create(:user, login: "new-user", created_at: Time.now - 5.days)
                request = create(:completed_two_factor_recovery_request_token, user: new_user, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)
                review = new_automated_review(user: new_user, request: request)
                time = Time.now
                expected_event = { :actor_ip => "127.0.0.1",
                  :actor => new_user.login,
                  :actor_id => new_user.id,
                  :note => "From github.localhost",
                  :user => new_user.login,
                  :user_id => new_user.id,
                  :action => expected_action,
                  :operation_type => "authentication",
                  :@timestamp => (time.to_i * 1000)
                }
                email_time = time
                email_event = { :actor_ip => "192.168.0.1", # presence will cause flagging
                  :email => new_user.email,
                  :note => "Suspicious",
                  :user => new_user.login,
                  :user_id => new_user.id,
                  :action => email_action,
                  :operation_type => "authentication",
                  :@timestamp => (email_time.to_i * 1000)
                }
                entries = [expected_event, email_event]

                review.expects(:recent_user_actions).at_least_once.returns(entries)
                review.perform
                assert review.review_required?
                assert_equal "A #{email_action} event was found for this user in the audit log for the email address: #{email_event[:email]}.", review.message
                assert_equal "audit_log", review.type
                assert_equal email_action, review.reason
                assert_equal email_time.to_i, review.audit_entry_time.to_i
              end
            end
          end

          TwoFactorRecoveryRequestReview::EMAIL_ACTIONS_NEW_ACCOUNT_EXPECTED.each do |expected_action|
            TwoFactorRecoveryRequestReview::POTENTIAL_TAKEOVER_INDICATORS.each do |ato_action|
              test "review required: new account does not flag for email event #{expected_action}, remaining takeover event #{ato_action}" do
                new_public_key_user = create(:user, login: "new-user", created_at: Time.now - 5.days)
                public_key = create(:public_key, user: new_public_key_user)
                request = create(:completed_two_factor_recovery_request_token, user: new_public_key_user, public_key_id: public_key.id, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)
                review = new_automated_review(user: new_public_key_user, request: request)
                time = Time.now
                expected_event = { :actor_ip => "127.0.0.1",
                  :actor => new_public_key_user.login,
                  :actor_id => new_public_key_user.id,
                  :note => "From github.localhost",
                  :user => new_public_key_user.login,
                  :user_id => new_public_key_user.id,
                  :action => expected_action,
                  :operation_type => "authentication",
                  :@timestamp => (time.to_i * 1000)
                }
                ato_time = request.created_at - 1.day
                ato_event = { :actor_ip => "192.168.0.1", # presence will cause flagging
                  :note => "Suspicious",
                  :user => new_public_key_user.login,
                  :user_id => new_public_key_user.id,
                  :action => ato_action,
                  :operation_type => "authentication",
                  :public_key_id => public_key.id,
                  :@timestamp => (ato_time.to_i * 1000)
                }
                entries = [expected_event, ato_event]

                review.expects(:recent_user_actions).at_least_once.returns(entries)
                review.perform
                assert review.review_required?
                assert_equal "A #{ato_action} event was found for this user in the audit log before starting this recovery request.", review.message
                assert_equal "audit_log", review.type
                assert_equal ato_action, review.reason
                assert_equal ato_time.to_i, review.audit_entry_time.to_i
              end
            end
          end

          TwoFactorRecoveryRequestReview::POTENTIAL_TAKEOVER_INDICATORS.excluding("public_key.create").each do |ato_action|
            test "review required: takeover event resolved, remaining takeover event #{ato_action}" do

              review = new_automated_review(user: @public_key_user, request: @public_key_authed_request)
              time = Time.now
              resolved_event = { :actor_ip => "127.0.0.1",
                :actor => @public_key_user.login,
                :actor_id => @public_key_user.id,
                :note => "From github.localhost",
                :public_key_id => @public_key.id,
                :user => @public_key_user.login,
                :user_id => @public_key_user.id,
                :action => "public_key.create",
                :operation_type => "authentication",
                :@timestamp => (time.to_i * 1000)
              }
              ato_time = @request.created_at - 1.day
              ato_event = { :actor_ip => "192.168.0.1", # presence will cause flagging
                :note => "Suspicious",
                :user => @public_key_user.login,
                :user_id => @public_key_user.id,
                :action => ato_action,
                :operation_type => "authentication",
                :public_key_id => @public_key.id,
                :@timestamp => (ato_time.to_i * 1000)
              }
              entries = [resolved_event, ato_event]

              review.expects(:recent_user_actions).at_least_once.returns(entries)
              review.perform
              assert review.review_required?
              assert_equal "A #{ato_action} event was found for this user in the audit log before starting this recovery request.", review.message
              assert_equal "audit_log", review.type
              assert_equal ato_action, review.reason
              assert_equal ato_time.to_i, review.audit_entry_time.to_i
            end
          end
        end
      end

      # This is an interesting case. Someone locked themselves out of their account
      # They opened a recovery request, but then changed their account into an Organization
      # Before the request made it to the review job.
      # Since the wrong User.type can break some of the checks that occur, we catch this and flag it for review
      test "review required when user type is not 'User'" do
        user_to_transform = create :two_factor_credential_user
        request = create(:completed_two_factor_recovery_request_token, user: user_to_transform, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)
        owner = create :user
        org = Organization.transform!(user_to_transform, owner)

        assert_equal user_to_transform.type, "Organization"

        review = new_automated_review(user: user_to_transform, request: request)

        review.perform
        assert review.review_required?
        assert_equal "User type has been changed", review.message
        assert_equal "wrong_user_type", review.type
        assert_nil review.reason
        assert_nil review.audit_entry_time
      end

      test "review required when user is staff" do
        request = create(:completed_two_factor_recovery_request_token, user: @staff_user, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)

        review = new_automated_review(user: @staff_user, request: request)

        review.perform
        assert review.review_required?
        assert_equal "User is staff member", review.message
        assert_equal "staff", review.type
        assert_nil review.reason
        assert_nil review.audit_entry_time
      end

      test "review required when user is deceased" do
        request = create(:completed_two_factor_recovery_request_token, user: @deceased_user, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)
        review = new_automated_review(user: @deceased_user, request: request)

        review.perform
        assert review.review_required?
        assert_equal "User has been marked as deceased by staff", review.message
        assert_equal "deceased", review.type
        assert_nil review.reason
        assert_nil review.audit_entry_time
      end

      test "review required when user is the last admin of an org" do
        org = create(:two_factor_credential_org, admin: @user)

        review = new_automated_review
        review.perform

        assert review.review_required?
        assert_equal "User is last admin of at least one organization", review.message
        assert_equal "org_membership", review.type
        assert_equal "last_admin", review.reason
        assert_nil review.audit_entry_time
      end

      test "review required when user is the owner of a 2fa required business" do
        business = create :business, owners: [@user]
        business.enable_two_factor_required actor: business.owners.first, force: true
        review = new_automated_review(user: business.owners.first, request: @request)

        review.perform
        assert review.review_required?
        assert_equal "User is affiliated with business that requires 2FA", review.message
        assert_equal "org_membership", review.type
        assert_equal "business_affiliation", review.reason
        assert_nil review.audit_entry_time
      end

      test "review required when user is the billing manager of a 2fa required business" do
        business = create :business, owners: [create(:two_factor_credential_user)]
        business.enable_two_factor_required actor: business.owners.first, force: true
        business.billing.add_manager @user, actor: business.owners.first
        review = new_automated_review

        review.perform
        assert review.review_required?
        assert_equal "User is affiliated with business that requires 2FA", review.message
        assert_equal "org_membership", review.type
        assert_equal "business_affiliation", review.reason
        assert_nil review.audit_entry_time
      end

      test "with members_without_2fa_allowed, review not required when user is the last admin of an org" do
        GitHub.flipper[:two_factor_cap_enforcement].enable
        GitHub.flipper[:members_without_2fa_allowed].enable
        org = create(:two_factor_credential_org, admin: @user)

        review = new_automated_review
        review.perform

        refute review.review_required?
        assert_nil review.message
        assert_nil review.type
        assert_nil review.reason
      end

      test "with members_without_2fa_allowed, review not required when user is the owner of a 2fa required business" do
        GitHub.flipper[:two_factor_cap_enforcement].enable
        GitHub.flipper[:members_without_2fa_allowed].enable
        business = create :business, owners: [@user]
        business.enable_two_factor_required actor: business.owners.first, force: true

        review = new_automated_review(user: business.owners.first, request: @request)
        review.perform

        refute review.review_required?
        assert_nil review.message
        assert_nil review.type
        assert_nil review.reason
      end

      test "with members_without_2fa_allowed, review not required when user is the billing manager of a 2fa required business" do
        GitHub.flipper[:two_factor_cap_enforcement].enable
        GitHub.flipper[:members_without_2fa_allowed].enable
        business = create :business, owners: [create(:two_factor_credential_user)]
        business.enable_two_factor_required actor: business.owners.first, force: true
        business.billing.add_manager @user, actor: business.owners.first

        review = new_automated_review
        review.perform

        refute review.review_required?
        assert_nil review.message
        assert_nil review.type
        assert_nil review.reason
      end

      test "review required if user has logged in since recovery request was created" do
        review = new_automated_review
        time = Time.now
        action = "user.login"
        entries = [{ :actor_ip => "127.0.0.1",
          :actor => @user.login,
          :actor_id => @user.id,
          :actor_location => { "location" => { "lat" => 0.0, "lon" => 0.0 } },
          :note => "From github.localhost",
          :user => @user.login,
          :user_id => @user.id,
          :action => action,
          :operation_type => "authentication",
          :@timestamp => (time.to_i * 1000)
        }]

        review.expects(:recent_user_actions).at_least_once.returns(entries)
        review.perform
        assert review.review_required?
        assert_equal "A #{action} event was found for this user in the audit log after this recovery request was initiated.", review.message
        assert_equal "audit_log", review.type
        assert_equal action, review.reason
        assert_equal time.to_i, review.audit_entry_time.to_i
      end

      test "review required if user has changed email addresses recently" do
        review = new_automated_review
        action = "user.add_email"
        email = "parrotice@meowful.com"
        entries = [{ :actor_ip => "127.0.0.1",
          :from => "user_emails#create",
          :actor => @user.login,
          :actor_id => @user.id,
          :actor_location => { "location" => { "lat" => 0.0, "lon" => 0.0 } },
          :note => email,
          :email => email,
          :user => @user.login,
          :user_id => @user.id,
          :action => action,
          :operation_type => "create",
          :@timestamp => (@timestamp.to_i * 1000),
        }]

        review.expects(:recent_user_actions).at_least_once.returns(entries)
        review.perform
        assert review.review_required?
        assert_equal "A #{action} event was found for this user in the audit log for the email address: #{email}.", review.message
        assert_equal "audit_log", review.type
        assert_equal action, review.reason
        assert_equal @timestamp.to_i, review.audit_entry_time.to_i
      end

      test "review required if user created a public key and then made request with it" do
        review = new_automated_review(user: @public_key_user, request: @public_key_authed_request)
        action = "public_key.create"
        entries = [{ :actor_ip => "127.0.0.1",
          :actor => @public_key_user.login,
          :actor_id => @public_key_user.id,
          :actor_location => { "location" => { "lat" => 0.0, "lon" => 0.0 } },
          :user => @public_key_user.login,
          :user_id => @public_key_user.id,
          :action => action,
          :operation_type => "create",
          :public_key_id => @public_key.id,
          :@timestamp => (@timestamp.to_i * 1000)
        }]

        review.expects(:recent_user_actions).at_least_once.returns(entries)

        review.perform

        assert review.review_required?
        assert_equal "A #{action} event was found for this user in the audit log before starting this recovery request.", review.message
        assert_equal "audit_log", review.type
        assert_equal action, review.reason
        assert_equal @timestamp.to_i, review.audit_entry_time.to_i
      end

      test "review required if primary verified email is marked as bouncing" do
        # this also marks the primary email as unverified
        @user.primary_user_email.mark_as_bouncing!

        review = new_automated_review

        review.perform

        assert review.review_required?
        assert_equal "Primary email #{@user.primary_user_email} is marked as bouncing. This email address should be verified again, and this account should be reviewed manually.", review.message
        assert_equal "email_status", review.type
        assert_equal "primary_email_bouncing", review.reason
        assert_nil review.audit_entry_time
      end

      test "review not required if user has only configured verified primary email for password resets" do
        @user.primary_user_email.verify!
        @user.allow_password_reset_with_primary_email_only

        review = new_automated_review

        review.perform

        refute review.review_required?
      end

      test "review not required if backup email is same as primary email" do
        @user.primary_user_email.verify!
        @user.set_backup_email(@user.primary_user_email)

        review = new_automated_review

        review.perform

        refute review.review_required?
      end

      test "review not required if backup email is also verified" do
        request = create(:completed_two_factor_recovery_request_token, user: @user_with_backup_email, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)

        review = new_automated_review(user: @user_with_backup_email, request: request)

        review.perform

        refute review.review_required?
      end

      test "review required if backup email is not verified" do
        request = create(:completed_two_factor_recovery_request_token, user: @user_with_unverified_backup_email, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)

        review = new_automated_review(user: @user_with_unverified_backup_email, request: request)

        review.perform

        assert review.review_required?
        assert_equal "Backup email #{@user_with_unverified_backup_email.backup_user_email} is not verified. This request should be reviewed manually to ensure we do not send an email to an unverified address.", review.message
        assert_equal "email_status", review.type
        assert_equal "backup_email_unverified", review.reason
        assert_nil review.audit_entry_time
      end

      test "review required if disposable email found on account with no verified emails and GitHub.prevent_disposable_email_verification is enabled" do
        GitHub.stubs(prevent_disposable_email_verification?: true)
        @user.emails.each { |e| e.unverify! }

        disposable_email = build(:user_email, user: @user, email: "disposable-email@mailinator.com")
        disposable_email.save(validate: false)

        review = new_automated_review

        review.perform
        assert review.review_required?
        assert_equal "Disposable email #{disposable_email} found on account without any verified email addresses", review.message
        assert_equal "email_status", review.type
        assert_equal "disposable_email_found", review.reason
        assert_nil review.audit_entry_time
      end

      test "review is not required if disposable email found on account with no verified emails and GitHub.prevent_disposable_email_verification is disabled" do
        GitHub.stubs(prevent_disposable_email_verification?: false)
        @user.emails.each { |e| e.unverify! }

        disposable_email = build(:user_email, user: @user, email: "disposable-email@mailinator.com")
        disposable_email.save(validate: false)

        review = new_automated_review

        review.perform
        refute review.review_required?
        assert_nil review.message
        assert_nil review.type
        assert_nil review.reason
        assert_nil review.audit_entry_time
      end

      test "review not required if email reputation above threshold" do
        @user.primary_user_email.verify!

        normal_email = create(:user_email, user: @user, email: "normal-email@example.com")
        normal_email.verify!

        EmailDomainReputationRecord
          .expects(:reputation)
          .with(normal_email.to_s)
          .at_least_once
          .returns(Spam::Reputation.new({ reputation: 0.9 }))

        EmailDomainReputationRecord
          .expects(:reputation)
          .with(@user.primary_user_email.to_s)
          .at_least_once
          .returns(Spam::Reputation.new({ reputation: 0.5 }))

        review = new_automated_review
        review.perform

        refute review.review_required?
        assert_nil review.message
        assert_nil review.type
        assert_nil review.reason
        assert_nil review.audit_entry_time
      end

      test "review required if email reputation below threshold" do
        @user.primary_user_email.verify!

        email_from_questionable_domain = create(:user_email, user: @user, email: "poor-reputation-email@example.com")
        email_from_questionable_domain.verify!

        EmailDomainReputationRecord
          .expects(:reputation)
          .with(email_from_questionable_domain.to_s)
          .at_least_once
          .returns(Spam::Reputation.new({ reputation: 0.09 }))

        # check other emails before primary, presuming it to be more likely to be legitimate, catch other email before having to check primary
        EmailDomainReputationRecord
          .expects(:reputation)
          .with(@user.primary_user_email.to_s)
          .never
          .returns(Spam::Reputation.new({ reputation: 0.5 })
        )

        review = new_automated_review

        review.perform
        assert review.review_required?
        assert_equal "Email #{email_from_questionable_domain} comes from a domain with low reputation (0.09)", review.message
        assert_equal "email_status", review.type
        assert_equal "disreputable_email", review.reason
        assert_nil review.audit_entry_time
      end
    end

    context "#perform" do
      test "invokes #assess_risk" do
        review = new_automated_review

        review.expects(:assess_risk).once

        review.perform
      end

      test "stores result in KV" do
        GitHub.flipper[:recovery_without_password_flagging].disable
        review = new_automated_review

        result = { @request.id => { "review_required" => false, "performed_at" => "#{@time}" } }.to_json

        Timecop.freeze(@time) do
          review.perform
        end
        assert_equal result, TwoFactorRecoveryRequestReview.mget([@request.id]).to_json
      end

      test "stores additional context in KV when review required" do
        GitHub.flipper[:recovery_without_password_flagging].disable
        business = create :business, owners: [@user]
        business.enable_two_factor_required actor: business.owners.first, force: true
        review = new_automated_review

        result = { @request.id => { "review_required" => true, "message" => "User is affiliated with business that requires 2FA", "type" => "org_membership", "reason" => "business_affiliation", "performed_at" => "#{@time}" } }.to_json
        Timecop.freeze(@time) do
          review.perform
        end
        assert_equal result, TwoFactorRecoveryRequestReview.mget([@request.id]).to_json
      end

      context "when no review required" do
        test "emits audit log event" do
          review = new_automated_review

          events = subscribe "two_factor_account_recovery_review.risk_assessment"

          review.perform

          assert event = events.pop, "an event was expected"
          assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

          expected_payload = {
            user: @user.login,
            user_id: @user.id,
            review_required: false
          }
          expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

          assert_equal expected_payload, event.payload
        end

        test "emits hydro event" do
          review = new_automated_review

          review.perform

          assert_hydro_published({
            user: Hydro::EntitySerializer.user(@user),
            review_required: false,
          }, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")

          assert_hydro_messages(count: 1, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")
        end
      end

      context "when email on account is from low-reputation domain" do
        test "emits audit log event" do
          email_from_questionable_domain = create(:user_email, user: @user, email: "poor-reputation-email@example.com")
          email_from_questionable_domain.verify!

          EmailDomainReputationRecord
            .expects(:reputation)
            .with(email_from_questionable_domain.to_s)
            .at_least_once
            .returns(Spam::Reputation.new({ reputation: 0.09 }))

          review = new_automated_review

          events = subscribe "two_factor_account_recovery_review.risk_assessment"

          review.perform

          assert event = events.pop, "an event was expected"
          assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

          expected_payload = {
            user: @user.login,
            user_id: @user.id,
            review_required: true,
            message: "Email #{email_from_questionable_domain} comes from a domain with low reputation (0.09)",
            type: "email_status",
            reason: "disreputable_email"
          }
          expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

          assert_equal expected_payload, event.payload
        end

        test "emits hydro event" do
          email_from_questionable_domain = create(:user_email, user: @user, email: "poor-reputation-email@example.com")
          email_from_questionable_domain.verify!

          EmailDomainReputationRecord
            .expects(:reputation)
            .with(email_from_questionable_domain.to_s)
            .at_least_once
            .returns(Spam::Reputation.new({ reputation: 0.09 }))

          review = new_automated_review

          review.perform

          assert_hydro_published({
            user: Hydro::EntitySerializer.user(@user),
            review_required: true,
            reason_type: :EMAIL_STATUS,
            email_status_type: :LOW_REPUTATION_DOMAIN,
          }, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")

          assert_hydro_messages(count: 1, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")
        end
      end

      context "when public_key.create event found in audit log" do
        test "sends audit log event" do
          review = new_automated_review(user: @public_key_user, request: @public_key_authed_request)
          action = "public_key.create"
          entries = [{ :actor_ip => "127.0.0.1",
            :actor => @public_key_user.login,
            :actor_id => @public_key_user.id,
            :actor_location => { "location" => { "lat" => 0.0, "lon" => 0.0 } },
            :user => @public_key_user.login,
            :user_id => @public_key_user.id,
            :action => action,
            :operation_type => "create",
            :public_key_id => @public_key.id,
            :@timestamp => (@timestamp.to_i * 1000)
          }]

          review.expects(:recent_user_actions).at_least_once.returns(entries)

          events = subscribe "two_factor_account_recovery_review.risk_assessment"

          review.perform

          assert event = events.pop, "an event was expected"
          assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

          expected_payload = {
            user: @public_key_user.login,
            user_id: @public_key_user.id,
            review_required: true,
            message: "A public_key.create event was found for this user in the audit log before starting this recovery request.",
            type: "audit_log",
            reason: "public_key.create"
          }
          expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

          assert_equal expected_payload, event.payload
        end

        test "sends hydro event" do
          review = new_automated_review(user: @public_key_user, request: @public_key_authed_request)
          action = "public_key.create"
          entries = [{ :actor_ip => "127.0.0.1",
            :actor => @public_key_user.login,
            :actor_id => @public_key_user.id,
            :actor_location => { "location" => { "lat" => 0.0, "lon" => 0.0 } },
            :user => @public_key_user.login,
            :user_id => @public_key_user.id,
            :action => action,
            :operation_type => "create",
            :public_key_id => @public_key.id,
            :@timestamp => (@timestamp.to_i * 1000)
          }]

          review.expects(:recent_user_actions).at_least_once.returns(entries)

          review.perform

          assert_hydro_published({
            user: Hydro::EntitySerializer.user(@public_key_user),
            review_required: true,
            reason_type: :AUDIT_LOG,
            audit_log_event_type: "public_key.create"
          }, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")

          assert_hydro_messages(count: 1, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")
        end
      end

      context "when user is last admin of org" do
        test "sends audit log event" do
          org = create(:two_factor_credential_org, admin: @user)

          review = new_automated_review

          events = subscribe "two_factor_account_recovery_review.risk_assessment"

          review.perform

          assert event = events.pop, "an event was expected"
          assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

          expected_payload = {
            user: @user.login,
            user_id: @user.id,
            review_required: true,
            message: "User is last admin of at least one organization",
            type: "org_membership",
            reason: "last_admin"
          }
          expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

          assert_equal expected_payload, event.payload
        end

        test "sends hydro event" do
          org = create(:two_factor_credential_org, admin: @user)

          review = new_automated_review

          review.perform

          assert_hydro_published({
            user: Hydro::EntitySerializer.user(@user),
            review_required: true,
            reason_type: :ORGANIZATION_MEMBERSHIP,
            org_membership_type: :LAST_ADMIN,
          }, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")

          assert_hydro_messages(count: 1, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")
        end
      end

      context "when user is staff" do
        test "sends audit log event" do
          request = create(:completed_two_factor_recovery_request_token, user: @staff_user, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @staff_user, request: request)

          events = subscribe "two_factor_account_recovery_review.risk_assessment"

          review.perform

          assert event = events.pop, "an event was expected"
          assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

          expected_payload = {
            user: @staff_user.login,
            user_id: @staff_user.id,
            review_required: true,
            message: "User is staff member",
            type: "staff",
            reason: nil, # TODO: can we drop this from the payload when it's nil?
          }
          expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

          assert_equal expected_payload, event.payload
        end

        test "sends hydro event" do
          request = create(:completed_two_factor_recovery_request_token, user: @staff_user, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @staff_user, request: request)

          review.perform

          assert_hydro_published({
            user: Hydro::EntitySerializer.user(@staff_user),
            review_required: true,
            reason_type: :STAFF,
          }, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")

          assert_hydro_messages(count: 1, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")
        end
      end

      context "when user is deceased" do
        test "sends audit log event" do
          request = create(:completed_two_factor_recovery_request_token, user: @deceased_user, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @deceased_user, request: request)

          events = subscribe "two_factor_account_recovery_review.risk_assessment"

          review.perform

          assert event = events.pop, "an event was expected"
          assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

          expected_payload = {
            user: @deceased_user.login,
            user_id: @deceased_user.id,
            review_required: true,
            message: "User has been marked as deceased by staff",
            type: "deceased",
            reason: nil, # TODO: can we drop this from the payload when it's nil?
          }
          expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

          assert_equal expected_payload, event.payload
        end

        test "sends hydro event" do
          request = create(:completed_two_factor_recovery_request_token, user: @deceased_user, created_at: Time.now - 1.day, request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @deceased, request: request)

          review.perform

          assert_hydro_published({
            user: Hydro::EntitySerializer.user(@deceased_user),
            review_required: true,
            reason_type: :DECEASED,
          }, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")

          assert_hydro_messages(count: 1, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")
        end
      end

      context "when user has large amount of monthly sponsorship" do
        test "automated review warns of problem" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @sponsorable_high_value_subscription_user,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @public_key_user, request: request)
          review.perform

          assert review.review_required?
          assert_equal "User requesting account recovery receives significant amount " \
            "from sponsors: $1,000.00 per month", review.message
          assert_equal "sponsors", review.type
          assert_equal "high_monthly_sponsorship", review.reason
          assert_nil review.audit_entry_time
        end

        test "sends audit log event" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @sponsorable_high_value_subscription_user,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @sponsorable_high_value_subscription_user, request: request)

          events = subscribe "two_factor_account_recovery_review.risk_assessment"

          review.perform

          assert event = events.pop, "an event was expected"
          assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

          expected_payload = {
            user: @sponsorable_high_value_subscription_user.login,
            user_id: @sponsorable_high_value_subscription_user.id,
            review_required: true,
            message: "User requesting account recovery receives significant amount from " \
              "sponsors: $1,000.00 per month",
            type: "sponsors",
            reason: "high_monthly_sponsorship",
          }
          expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

          assert_equal expected_payload, event.payload
        end

        test "sends hydro event" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @sponsorable_high_value_subscription_user,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @sponsorable_high_value_subscription_user, request: request)
          review.perform

          assert_hydro_published({
            user: Hydro::EntitySerializer.user(@sponsorable_high_value_subscription_user),
            review_required: true,
            reason_type: :SPONSORS,
            # TODO: we lack granularity on the sponsorship reason - is this fine?
            # sponsors_type: :HIGH_MONTHLY_SPONSORSHIP,
          }, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")

          assert_hydro_messages(count: 1, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")
        end
      end

      context "when user has high sponsorship tier" do
        test "automated review identifies this as a problem" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @sponsorable_high_value_tier_user,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @sponsorable_high_value_subscription_user, request: request)
          review.perform

          assert review.review_required?
          assert_equal "User has published sponsorship tier over $5,000.00 per month",
            review.message
          assert_equal "sponsors", review.type
          assert_equal "high_sponsor_tier", review.reason
          assert_nil review.audit_entry_time
        end

        test "sends audit log event" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @sponsorable_high_value_tier_user,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @sponsorable_high_value_tier_user, request: request)

          events = subscribe "two_factor_account_recovery_review.risk_assessment"

          review.perform

          assert event = events.pop, "an event was expected"
          assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

          expected_payload = {
            user: @sponsorable_high_value_tier_user.login,
            user_id: @sponsorable_high_value_tier_user.id,
            review_required: true,
            message: "User has published sponsorship tier over $5,000.00 per month",
            type: "sponsors",
            reason: "high_sponsor_tier",
          }
          expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

          assert_equal expected_payload, event.payload
        end

        test "sends hydro event" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @sponsorable_high_value_tier_user,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @sponsorable_high_value_tier_user, request: request)
          review.perform

          assert_hydro_published({
            user: Hydro::EntitySerializer.user(@sponsorable_high_value_tier_user),
            review_required: true,
            reason_type: :SPONSORS,
            # TODO: we lack granularity on the sponsorship reason - is this fine?
            # sponsors_type: :HIGH_MONTHLY_SPONSORSHIP,
          }, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")

          assert_hydro_messages(count: 1, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")
        end
      end

      context "when user has high number of sponsoring users" do
        test "automated review identifies this as a problem" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @user_with_large_number_of_sponsors,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @user_with_large_number_of_sponsors, request: request)

          TwoFactorRecoveryRequestReview.stub_const("SPONSOR_COUNT_THRESHOLD", 4) do
            review.perform
          end

          assert review.review_required?
          assert_equal "User has 5 active sponsors", review.message
          assert_equal "sponsors", review.type
          assert_equal "high_sponsor_count", review.reason
          assert_nil review.audit_entry_time
        end

        test "sends audit log event" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @user_with_large_number_of_sponsors,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @user_with_large_number_of_sponsors, request: request)

          events = subscribe "two_factor_account_recovery_review.risk_assessment"

          TwoFactorRecoveryRequestReview.stub_const("SPONSOR_COUNT_THRESHOLD", 4) do
            review.perform
          end

          assert event = events.pop, "an event was expected"
          assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

          expected_payload = {
            user: @user_with_large_number_of_sponsors.login,
            user_id: @user_with_large_number_of_sponsors.id,
            review_required: true,
            message: "User has 5 active sponsors",
            type: "sponsors",
            reason: "high_sponsor_count"
          }
          expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

          assert_equal expected_payload, event.payload
        end

        test "sends hydro event" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @user_with_large_number_of_sponsors,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @user_with_large_number_of_sponsors, request: request)

          TwoFactorRecoveryRequestReview.stub_const("SPONSOR_COUNT_THRESHOLD", 4) do
            review.perform
          end

          assert_hydro_published({
            user: Hydro::EntitySerializer.user(@user_with_large_number_of_sponsors),
            review_required: true,
            reason_type: :SPONSORS,
            # TODO: we lack granularity on the sponsorship reason - is this fine?
            # sponsors_type: :HIGH_MONTHLY_SPONSORSHIP,
          }, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")

          assert_hydro_messages(count: 1, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")
        end
      end

      context "when user has low amount of sponsorship" do
        test "automated review does not report issue" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @user_with_some_small_sponsors,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @user_with_some_small_sponsors, request: request)
          review.perform

          refute review.review_required?
        end

        test "sends audit log event" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @user_with_some_small_sponsors,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @user_with_some_small_sponsors, request: request)

          events = subscribe "two_factor_account_recovery_review.risk_assessment"

          review.perform

          assert event = events.pop, "an event was expected"
          assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

          expected_payload = {
            user: @user_with_some_small_sponsors.login,
            user_id: @user_with_some_small_sponsors.id,
            review_required: false
          }
          expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

          assert_equal expected_payload, event.payload
        end

        test "sends hydro event" do
          request = create(:completed_two_factor_recovery_request_token,
            user: @user_with_some_small_sponsors,
            created_at: Time.now - 1.day,
            request_completed_at: Time.now - 11.hours)

          review = new_automated_review(user: @user_with_some_small_sponsors, request: request)
          review.perform

          assert_hydro_published({
            user: Hydro::EntitySerializer.user(@user_with_some_small_sponsors),
            review_required: false
          }, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")

          assert_hydro_messages(count: 1, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview")
        end
      end
    end

    context "when error raised inside perform" do
      test "catches exceptions and requires review" do
        User.any_instance.expects(:site_admin?).raises(StandardError.new("explodifying"))
        Failbot.expects(:report).once
        review = new_automated_review

        review.perform

        assert review.review_required?
        assert_equal "explodifying", review.message
        assert_equal "automated_review_process_failed", review.type
        assert_nil review.reason
        assert_nil review.audit_entry_time
      end

      test "emits audit log event" do
        User.any_instance.expects(:site_admin?).raises(StandardError.new("explodifying"))
        Failbot.expects(:report).once
        review = new_automated_review

        events = subscribe "two_factor_account_recovery_review.risk_assessment"

        review.perform

        assert event = events.pop, "an event was expected"
        assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

        expected_payload = {
          user: @user.login,
          user_id: @user.id,
          review_required: true,
          message: "explodifying",
          type: "automated_review_process_failed",
          reason: nil,
        }
        expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

        assert_equal expected_payload, event.payload
      end
    end

    context "when evidence removed from review" do
      test "review required if request is missing evidence" do
        request = create(:two_factor_recovery_request_missing_evidence)
        review = new_automated_review(user: request.user, request: request)

        review.perform

        assert review.review_required?
        assert_equal "Evidence used to complete the request is no longer present", review.message
        assert_equal "evidence_missing", review.type
        assert_nil review.reason
        assert_nil review.audit_entry_time
      end

      test "emits audit log event" do
        request = create(:two_factor_recovery_request_missing_evidence)
        review = new_automated_review(user: request.user, request: request)

        events = subscribe "two_factor_account_recovery_review.risk_assessment"

        review.perform

        assert event = events.pop, "an event was expected"
        assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

        expected_payload = {
          user: request.user.login,
          user_id: request.user.id,
          review_required: true,
          message: "Evidence used to complete the request is no longer present",
          type: "evidence_missing",
          reason: nil,
        }
        expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?

        assert_equal expected_payload, event.payload
      end

      test "emits audit log event for auto approved request" do
        request = create(:two_factor_recovery_request_missing_evidence)
        review = new_automated_review(user: request.user, request: request)

        events = subscribe "two_factor_account_recovery_review.risk_assessment"

        review.perform

        assert event = events.pop, "an event was expected"
        assert_equal "two_factor_account_recovery_review.risk_assessment", event.name

        expected_payload = {
          user: request.user.login,
          user_id: request.user.id,
          review_required: true,
          message: "Evidence used to complete the request is no longer present",
          type: "evidence_missing",
          reason: nil,
        }
        expected_payload[:without_password] = false if GitHub.flipper[:recovery_without_password_flagging].enabled?
        assert_equal expected_payload, event.payload
      end
    end
  end

  context "#recent_user_actions" do
    test "sends the correct phrase" do
      Timecop.freeze do
        review = new_automated_review

        recent_options = {
          actor_id: @request.user.id,
          allowlist: TwoFactorRecoveryRequestReview::ACTIONS_LIST,
          phrase: "created:>=#{30.days.ago.iso8601}",
          per_page: 100,
        }
        res_mock = Minitest::Mock.new
        res_mock.expect(:results, [])

        audit_mock = Minitest::Mock.new
        audit_mock.expect(:execute, res_mock)

        Audit::Driftwood::Query.expects(:new_user_query).with(recent_options).at_least_once.returns(audit_mock)

        review.perform
      end
    end
  end

  context "#recovery_submit_user_actions" do
    test "sends the correct phrase" do
      Timecop.freeze do
        review = new_automated_review
        entries = [{ :actor_ip => "127.0.0.1",
          :actor => @user.login,
          :actor_id => @user.id,
          :note => "From github.localhost",
          :user => @user.login,
          :user_id => @user.id,
          :action => "user.login",
          :operation_type => "authentication",
          :@timestamp => (time.to_i * 1000)
        }]
        request_options = {
          user_id: @request.user.id,
          allowlist: ["two_factor_account_recovery.complete"],
          phrase: "created:>=#{@request.created_at.iso8601}",
          per_page: 100,
        }

        review.expects(:recent_user_actions).at_least_once.returns(entries)

        res_mock = Minitest::Mock.new
        res_mock.expect(:results, [])

        audit_mock = Minitest::Mock.new
        audit_mock.expect(:execute, res_mock)

        Audit::Driftwood::Query.expects(:new_user_query).with(request_options).at_least_once.returns(audit_mock)

        review.perform
      end
    end

    test "throws error and makes no decision when audit logs unavailable" do
      review = new_automated_review
      Audit::Driftwood::Query.expects(:new_user_query).throws(Driftwood::TwirpUtil::Error.new)

      begin
        review.perform
      rescue TwoFactorRecoveryRequestReview::TemporarilyUnavailableError => e
        assert_equal e.message, "Audit logs not available to review recovery request"
      end
    end
  end

  def new_automated_review(user: nil, request: nil, without_password: false, client_id: nil)
    review = TwoFactorRecoveryRequestReview.new(request.nil? ? @request : request)
    initiate_entry = [{ :actor_ip => "127.0.0.1",
      :actor_location => { "location" => { "lat" => 0.0, "lon" => 0.0 } },
      :note => "From github.localhost",
      :user => user.nil? ? @request.user.login : user.login,
      :user_id => user.nil? ? @request.user.id : user.id,
      :two_factor_account_recovery_id => request.nil? ? @request.id : request.id,
      :controller_action => without_password ? "without_password" : "start",
      :action => "two_factor_account_recovery.initiate",
      :client_id => client_id,
      :operation_type => "authentication",
      :@timestamp => (@time.to_i * 1000)
    }]
    review.stubs(:recovery_initiate_user_actions).returns(initiate_entry) if GitHub.flipper[:recovery_without_password_flagging].enabled?
    review
  end
end
