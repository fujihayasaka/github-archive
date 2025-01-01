# typed: true
# frozen_string_literal: true

require "test_helper"

class UserTradeScreeningDependencyTest < GitHub::TestCase
  include DogstatsTestHelpers
  include AuditLog::IntegrationTestHelpers
  include GitHub::LoggerHelper
  include HydroTestHelpers
  include TradeCompliance::TradeScreening::TradeScreeningTestHelpers

  def make_live_sdn_request(cassette, **options, &block)
    VCR.use_cassette(cassette, **options) do
      yield
    end
  end

  setup do
    @profile = create(:account_screening_profile)
    @user = @profile.user
  end

  context "#add_sdn_suspension_staff_note" do
    test "Adds a staff note to the user" do
      profile = create(:account_screening_profile)
      user = profile.user

      user.enable_feature(:live_sdn_screening)

      user.add_sdn_suspension_staff_note

      assert user.staff_notes.any?
      assert_equal "DO NOT MODIFY THIS ACCOUNT WITHOUT APPROVAL FROM TRADE SUPPORT/CELA.", user.staff_notes.last.body

      report = Failbot.reports.last
      refute_equal "failed to add sdn staff note", Failbot.exception_message_from_hash(report)
    end

    test "reports to sentry when adding a staff note fails" do
      profile = create(:account_screening_profile)
      user = profile.user

      user.enable_feature(:live_sdn_screening)
      StaffNote.any_instance.stubs(:save).returns(false)

      user.add_sdn_suspension_staff_note

      report = Failbot.reports.last
      assert_equal "failed to add sdn staff note", Failbot.exception_message_from_hash(report)
    end
  end

  context "#humanize_trade_screening_status" do
    %w[no_hit not_screened ssi_e_60 ssi_d_30 ssi_f_14 lic_r lic_a ingestion_error data_issue].each do |sdn_screening_status|
      test "returns a descriptive message when account is #{sdn_screening_status}" do
        profile = create(:account_screening_profile, msft_trade_screening_status: sdn_screening_status)
        user = profile.user

        status_description = user.humanize_trade_screening_status

        refute_includes status_description, sdn_screening_status
      end

      test "returns a descriptive message when account is #{sdn_screening_status} that includes that screening status" do
        profile = create(:account_screening_profile, msft_trade_screening_status: sdn_screening_status)
        user = profile.user

        status_description = user.humanize_trade_screening_status(authorized_staffer: true)

        assert_includes status_description, sdn_screening_status
      end
    end
  end

  context "#add_sdn_unsuspension_staff_note" do
    test "Adds a staff note to the user" do
      profile = create(:account_screening_profile)
      user = profile.user

      user.enable_feature(:live_sdn_screening)

      user.add_sdn_unsuspension_staff_note

      assert user.staff_notes.any?
      assert_equal "Account is no longer SDN suspended", user.staff_notes.last.body

      report = Failbot.reports.last
      refute_equal "failed to add sdn staff note", Failbot.exception_message_from_hash(report)
    end

    test "reports to sentry when adding a staff note fails" do
      profile = create(:account_screening_profile)
      user = profile.user

      user.enable_feature(:live_sdn_screening)
      StaffNote.any_instance.stubs(:save).returns(false)

      user.add_sdn_suspension_staff_note

      report = Failbot.reports.last
      assert_equal "failed to add sdn staff note", Failbot.exception_message_from_hash(report)
    end
  end

  context "#perform_live_sdn_screening" do
    test "does not perform screening if user is spammy but sets spammy screening status" do
      profile = create(:account_screening_profile)
      user = profile.user
      user.enable_feature(:live_sdn_screening)

      assert_predicate profile, :not_screened?
      user.mark_as_spammy

      TradeCompliance::TradeScreening::ApiService.any_instance.expects(:request_trade_screening).never
      TradeControls::Sdn::BillingChangesJob.expects(:perform_later).once

      user.perform_live_sdn_screening
      assert_predicate profile.reload, :spammy?
      assert OFACDowngrade.find_by(user_id: user.id)

      assert_hydro_published({
        country: T.must(profile).country_code,
        external_user_id: T.must(profile).external_uuid,
        request_id: "NO_SDN_REQUEST_MADE",
        request_type: "LIVE",
        status: "spammy",
        actor_type: "USER"
      }, schema: "github.trade_screening.v0.TradeScreeningResult")
    end

    test "cancels downgrade if user moves out of spammy within grace period" do
      profile = create(:account_screening_profile)
      user = profile.user
      user.enable_feature(:live_sdn_screening)

      assert_predicate profile, :not_screened?
      user.mark_as_spammy

      TradeCompliance::TradeScreening::ApiService.any_instance.expects(:request_trade_screening).never
      TradeControls::Sdn::BillingChangesJob.expects(:perform_later).once

      user.perform_live_sdn_screening
      assert_predicate profile.reload, :spammy?
      assert OFACDowngrade.find_by(user_id: user.id)

      TradeControls::Sdn::BillingChangesJob.expects(:perform_later).once
      profile.update(msft_trade_screening_status: "no_hit")
      assert OFACDowngrade.find_by(user_id: user.id)

      user.mark_not_spammy
      refute OFACDowngrade.find_by(user_id: user.id)
    end

    test "does not perform screening if user is spammy and has an existing trade restriction" do
      TradeControls::Sdn::BillingChangesJob.expects(:perform_later).once

      profile = create(:account_screening_profile)
      profile.update(msft_trade_screening_status: "hit_in_review")
      user = profile.user
      user.enable_feature(:live_sdn_screening)

      assert_predicate profile, :hit_in_review?
      user.mark_as_spammy

      TradeCompliance::TradeScreening::ApiService.any_instance.expects(:request_trade_screening).never
      user.perform_live_sdn_screening
      assert_predicate profile.reload, :hit_in_review? # still hit in review
      assert OFACDowngrade.find_by(user_id: user.id)
    end

    test "does not set external_uuid if already set" do
      profile = create(:account_screening_profile)
      user = profile.user
      user.enable_feature(:live_sdn_screening)
      uuid = profile.external_uuid

      assert uuid.present?

      make_live_sdn_request("trade_controls/sdn/valid_user_live_api_call") do
        user.perform_live_sdn_screening
      end
      profile.reload
      assert_equal profile.external_uuid, uuid
    end

    context "org_is_on_standard_tos?" do
      test "returns false when org is not reloaded after terms of service is changed to corporate" do
        upp = create(:account_screening_profile, :with_org)
        owner = upp.owner
        assert_predicate owner, :org_is_on_standard_tos?

        owner.terms_of_service.update(type: "Corporate", actor: owner)

        refute_predicate owner, :org_is_on_standard_tos?
      end

      test "returns false when org is reloaded after terms of service is changed to corporate" do
        upp = create(:account_screening_profile, :with_org)
        owner = upp.owner
        assert_predicate owner, :org_is_on_standard_tos?

        owner.terms_of_service.update(type: "Corporate", actor: owner)

        owner.reload
        refute_predicate owner, :org_is_on_standard_tos?
      end

      test "updates linked screening record correctly" do
        admin = create(:user, :with_trade_screening_record)
        organization = create(:organization, :trade_unrestricted, admin: admin)
        organization.enable_feature(:live_sdn_screening)

        admin.link_trade_screening_record_to_org(organization: organization)
        profile = organization.trade_screening_record

        make_live_sdn_request("trade_controls/sdn/valid_user_live_api_call") do
          organization.perform_live_sdn_screening
        end
        profile.reload

        assert_predicate profile, :hit_in_review?
      end
    end

    test "does not call the screening API if the org does not have all the required fields" do
      upp = create(:account_screening_profile, :with_org)
      upp.update_attribute(:entity_name, nil)
      owner = upp.owner
      owner.terms_of_service.update(type: "Corporate", actor: owner)
      owner.enable_feature(:live_sdn_screening)

      TradeCompliance::TradeScreening::ApiService.any_instance.expects(:request_trade_screening).never
      assert owner.perform_live_sdn_screening
    end

    test "calls sdn live api service, saves hit in review status and returns false" do
      GitHub.flipper[:sync_billing_address_to_contact].disable
      upp = create(:account_screening_profile)
      user = upp.user
      user.enable_feature(:live_sdn_screening)

      screening_request = build_screening_request(screening_profile: upp)
      request_body = screening_request.to_hash
      live_response = TradeCompliance::TradeScreening::LiveResponse.parse(response: {
        ScrRespEnv: {
          EId: request_body[:ScrReqsEnv][:EId],
          DT: request_body[:ScrReqsEnv][:DT],
          SummResult: "Hit in Review",
          ScrResps: {
            ScrResp: [
              {
                ReqID: "IndName_IndAddr",
                ExternalRefID: request_body[:ScrReqsEnv][:ExternalRefID],
                Result: "Hit in Review",
                ResultDesc: "",
                Type: "Address",
                Errs: {
                  Err: [
                    {
                      ErrCode: "",
                      ErrDesc: ""
                    }
                  ]
                }
              }
            ]
          }
        }
      })

      assert upp.not_screened?
      TradeCompliance::TradeScreening::ApiService.stubs(:request_trade_screening).returns(live_response)
      refute user.perform_live_sdn_screening

      upp.reload
      assert upp.hit_in_review?
      assert_empty upp.metadata
    end

    test "requests trade screening with multiple addresses and saves each address's status" do
      GitHub.flipper[:sync_billing_address_to_contact].disable
      profile = T.let(create(:account_screening_profile, :with_credit_card), AccountScreeningProfile)
      user = T.must(profile.user)
      billing_contact = T.let(create(:billing_contact, customer: user.customer), Billing::Contact)
      shipping_contact = T.let(create(:shipping_contact, customer: user.customer), Billing::Contact)
      user.enable_feature(:live_sdn_screening)

      screening_request = build_screening_request(screening_profile: profile)
      request_body = screening_request.to_hash
      live_response = TradeCompliance::TradeScreening::LiveResponse.parse(response: {
        ScrRespEnv: {
          EId: request_body[:ScrReqsEnv][:EId],
          DT: request_body[:ScrReqsEnv][:DT],
          SummResult: "Hit in Review",
          ScrResps: {
            ScrResp: [
              {
                ReqID: profile.request_id,
                ExternalRefID: profile.external_uuid,
                Result: "Hit in Review",
                ResultDesc: "",
                Type: "Address",
                Errs: {
                  Err: [
                    {
                      ErrCode: "",
                      ErrDesc: ""
                    }
                  ]
                }
              },
              {
                ReqID: shipping_contact.trade_screening_request_id,
                ExternalRefID: profile.external_uuid,
                Result: "No Hit",
                ResultDesc: "",
                Type: "Address",
                Errs: {
                  Err: [
                    {
                      ErrCode: "",
                      ErrDesc: ""
                    }
                  ]
                }
              }
            ]
          }
        }
      })
      TradeCompliance::TradeScreening::ApiService.stubs(:request_trade_screening).returns(live_response)

      assert_predicate profile, :not_screened?
      refute user.perform_live_sdn_screening

      profile.reload
      billing_contact.reload
      shipping_contact.reload
      assert_predicate profile, :hit_in_review?
      assert_predicate profile, :billing_hit_in_review?
      assert_predicate billing_contact, :hit_in_review?
      assert_predicate shipping_contact, :no_hit?
    end

    test "force:true force calls the api service and ignores the requirement of the record needing a not_screened status" do
      GitHub.flipper[:sync_billing_address_to_contact].disable
      upp = create(:account_screening_profile, :with_populated_attributes, msft_trade_screening_status: "no_hit")
      user = upp.user
      user.enable_feature(:live_sdn_screening)

      screening_request = build_screening_request(screening_profile: upp)
      request_body = screening_request.to_hash
      live_response = TradeCompliance::TradeScreening::LiveResponse.parse(response: {
        ScrRespEnv: {
          EId: request_body[:ScrReqsEnv][:EId],
          DT: request_body[:ScrReqsEnv][:DT],
          SummResult: "Hit in Review",
          ScrResps: {
            ScrResp: [
              {
                ReqID: "IndName_IndAddr",
                ExternalRefID: request_body[:ScrReqsEnv][:ExternalRefID],
                Result: "Hit in Review",
                ResultDesc: "",
                Type: "Address",
                Errs: {
                  Err: [
                    {
                      ErrCode: "",
                      ErrDesc: ""
                    }
                  ]
                }
              }
            ]
          }
        }
      })

      assert upp.no_hit? # instead of not_screened?
      TradeCompliance::TradeScreening::ApiService.stubs(:request_trade_screening).returns(live_response)
      refute user.perform_live_sdn_screening(force: true)

      upp.reload
      assert upp.hit_in_review?
      assert_empty upp.metadata
    end

    test "calls sdn live api service, saves data issue status" do
      upp = create(:account_screening_profile)
      user = upp.user
      user.enable_feature(:live_sdn_screening)

      screening_request = build_screening_request(screening_profile: upp)
      request_body = screening_request.to_hash
      live_response = TradeCompliance::TradeScreening::LiveResponse.parse(response: {
        ScrRespEnv: {
          EId: request_body[:ScrReqsEnv][:EId],
          DT: request_body[:ScrReqsEnv][:DT],
          SummResult: "Data Issue",
          ScrResps: {
            ScrResp: [
              {
                ReqID: "IndName_IndAddr",
                ExternalRefID: request_body[:ScrReqsEnv][:ExternalRefID],
                Result: "Data Issue",
                ResultDesc: "Data Issue - Address",
                Type: "Address"
              }
            ]
          }
        }
      })

      assert upp.not_screened?
      TradeCompliance::TradeScreening::ApiService.stubs(:request_trade_screening).returns(live_response)
      refute user.perform_live_sdn_screening

      upp.reload
      assert upp.data_issue?
      assert_predicate upp.screening_status_reason, :present?
    end

    test "sets screening record metadata with retry status and instruments to audit log if API service returns 500 HTTP status" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      uuid_str = "6c8b6229-3506-427f-aa64-9ce87e9cfa94"
      SecureRandom.stubs(:uuid).returns(uuid_str)

      upp = create(:account_screening_profile)
      user = upp.user
      user.enable_feature(:live_sdn_screening)

      conn = GitHub::FaradayClient::Internal.new(url: "http://example.invalid") do |builder|
        builder.adapter :test do |stub|
          stub.post(GitHub.sdn_live_api_url_path) do
            [
              500,
              { "Content-Type": "text/plain", },
              "{}"
            ]
          end
        end
      end

      TradeCompliance::TradeScreening::ApiService.stubs(:live_connection).returns(conn)

      log_exception = "Request to the SDN API failed because of 500 HTTP status"
      log_reason = "Request to the SDN API failed because of TradeCompliance::TradeScreening::ApiServiceBadResponseError error"
      log_key = "sdn_api_service.live.failed"


      expected_log = {
        "Body" => "sdn_api_service.failed",
        "gh.sdn_api_service.type" => "live",
        "gh.sdn_api_service.url" => GitHub.sdn_live_api_base_url,
        "gh.sdn_api_service.eid" => uuid_str,
        "gh.sdn_api_service.external_uuid" => uuid_str,
        "error.message" => log_exception
      }

      assert_logged(**expected_log) do
        events = assert_performed_audit_entries(count: 1, only: "account_screening_profile.live_sdn_screening") do
          assert user.perform_live_sdn_screening # user can still proceed
        end

        user.reload
        assert user.trade_screening_record.retry?
        assert_equal "retry: #{log_exception}", user.trade_screening_record.screening_status_reason

        # Datadog log
        expected_tags = [
          "reason:#{log_reason}",
          "eid:#{uuid_str}",
          "owner_type:USER",
        ]
        assert_dogstats_increment 1, log_key, tags: expected_tags

        # Audit log event
        update_event = events.first
        assert_equal "retry", update_event[:screening_status]
        assert_equal "retry: #{log_exception}", update_event[:status_reason]
      end
    end

    test "it sets retry status and returns true if parsing of response fails" do
      upp = create(:account_screening_profile)
      user = upp.user
      user.enable_feature(:live_sdn_screening)

      TradeCompliance::TradeScreening::LiveResponse.stubs(:parse).raises(TradeCompliance::TradeScreening::LiveResponseParsingError)

      assert upp.not_screened?
      can_proceed = make_live_sdn_request("trade_controls/sdn/valid_user_live_api_call") do
        user.perform_live_sdn_screening
      end

      assert can_proceed

      upp.reload
      assert upp.retry?
    end

    test "it sets the retry status if the live screening request times out" do
      profile = create(:account_screening_profile, :not_screened)
      user = profile.user
      user.enable_feature(:live_sdn_screening)
      TradeCompliance::TradeScreening::ApiService.stubs(:live_connection).raises(Faraday::TimeoutError)

      log_reason = "Request to the SDN API failed because of Faraday::TimeoutError error"

      # We control the Envelop ID we generate for the request
      uuid_str = "6c8b6229-3506-427f-aa64-9ce87e9cfa94"
      SecureRandom.stubs(:uuid).returns(uuid_str)

      expected_log = {
        "Body" => "sdn_api_service.failed",
        "gh.sdn_api_service.type" => "live",
        "gh.sdn_api_service.url" => GitHub.sdn_live_api_base_url,
        "gh.sdn_api_service.eid" => uuid_str,
        "gh.sdn_api_service.external_uuid" => profile.external_uuid,
        "error.message" => "timeout"
      }

      assert_logged(**expected_log) do
        events = assert_performed_audit_entries(count: 1, only: "account_screening_profile.live_sdn_screening") do
          assert user.perform_live_sdn_screening # user can still proceed
        end

        user.reload
        assert user.trade_screening_record.retry?
        assert_equal "retry: timeout", user.trade_screening_record.screening_status_reason

        # Datadog log
        expected_tags = [
          "reason:#{log_reason}",
          "eid:#{uuid_str}",
          "owner_type:USER",
        ]
        assert_dogstats_increment 1, "sdn_api_service.live.failed", tags: expected_tags

        # Audit log event
        update_event = events.first
        assert_equal "retry", update_event[:screening_status]
        assert_equal "retry: timeout", update_event[:status_reason]
      end
    end

    test "sets the retry status even if the profile has already been screened" do
      upp = create(:account_screening_profile, :no_hit)
      user = upp.user
      user.enable_feature(:live_sdn_screening)
      # A profile with any status other than not_screened would return false
      user.expects(:should_perform_live_sdn_screening?).returns(true)
      TradeCompliance::TradeScreening::LiveResponse.stubs(:parse).raises(TradeCompliance::TradeScreening::LiveResponseParsingError, "Expected ScrResp array to have at least one response.")

      assert upp.no_hit?

      assert_logged(
        "Body": "sdn_api_service.screened.retry",
        "gh.sdn_api_service.retry_reason": "Expected ScrResp array to have at least one response.",
        "gh.sdn_api_service.existing_status": "retry",
        "gh.sdn_api_service.external_uuid": upp.external_uuid) do
        make_live_sdn_request("trade_controls/sdn/valid_user_live_api_call") do
          user.perform_live_sdn_screening
        end
      end

      upp.reload
      assert upp.retry?
      assert_dogstats_increment 1, "sdn_api_service.screened.retry"
    end

    test "it sets the retry status if the profile has already been screened but the force flag is true" do
      upp = create(:account_screening_profile, :no_hit)
      user = upp.user
      user.enable_feature(:live_sdn_screening)
      # A profile with any status other than not_screened would return false
      user.expects(:should_perform_live_sdn_screening?).returns(true)
      TradeCompliance::TradeScreening::LiveResponse.stubs(:parse).raises(TradeCompliance::TradeScreening::LiveResponseParsingError, "Expected ScrResp array to have at least one response.")

      assert upp.no_hit?
      can_proceed = make_live_sdn_request("trade_controls/sdn/valid_user_live_api_call") do
        user.perform_live_sdn_screening(force: true)
      end

      upp.reload

      assert can_proceed
      assert upp.retry?
    end

    test "it sets retry status and returns true if api authentication fails" do
      upp = create(:account_screening_profile)
      user = upp.user
      user.enable_feature(:live_sdn_screening)

      assert upp.not_screened?

      can_proceed = make_live_sdn_request("trade_controls/sdn/unauthorized_live_error", allow_playback_repeats: true) do
        user.perform_live_sdn_screening
      end

      assert can_proceed

      upp.reload
      assert upp.retry?
    end

    test "it sets ingestion error status and returns false if ingestion error" do
      upp = create(:account_screening_profile)
      user = upp.user
      user.enable_feature(:live_sdn_screening)

      assert upp.not_screened?

      can_proceed = make_live_sdn_request("trade_controls/sdn/live_api_bad_request_error") do
        user.perform_live_sdn_screening
      end

      refute can_proceed

      upp.reload
      assert upp.ingestion_error?
    end

    test "it sets data issue status and does not proceed with interaction" do
      upp = create(:account_screening_profile)
      user = upp.user
      user.enable_feature(:live_sdn_screening)

      assert upp.not_screened?

      can_proceed = make_live_sdn_request("trade_controls/sdn/live_api_bad_data_error") do
        user.perform_live_sdn_screening
      end

      refute can_proceed

      upp.reload
      assert_predicate upp, :data_issue?
      assert_predicate upp.screening_status_reason, :present?
    end
  end

  context "#has_saved_trade_screening_record?" do
    test "returns false when there's no profile" do
      user = create(:user)

      refute_predicate user, :has_saved_trade_screening_record?
    end

    test "returns false when profile is invalid" do
      profile = build(:account_screening_profile, first_name: "")
      profile.save(validate: false)
      user = profile.user

      refute_predicate user, :has_saved_trade_screening_record?
    end

    test "returns true when profile is invalid and status is true_match" do
      user = create(:user)

      profile = build(:account_screening_profile, first_name: "", owner: user, msft_trade_screening_status: "true_match")
      profile.save!

      assert_predicate user, :has_saved_trade_screening_record?
      refute_predicate profile, :valid?
    end

    test "returns true when profile is valid" do
      profile = create(:account_screening_profile)
      user = profile.user

      assert_predicate user, :has_saved_trade_screening_record?
    end

    test "returns true when profile becomes valid after update" do
      profile = build(:account_screening_profile, first_name: "")
      profile.save(validate: false)
      user = profile.user

      refute_predicate user, :has_saved_trade_screening_record?

      profile.first_name = "John"
      profile.save!

      assert_predicate user, :has_saved_trade_screening_record?
    end
  end

  context "#is_allowed_to_edit_trade_screening_information?" do
    %w[no_hit not_screened ssi_e_60 ssi_d_30 ssi_f_14 lic_a ingestion_error data_issue].each do |sdn_screening_status|
      test "#{sdn_screening_status} is allowed to edit personal profile" do
        profile = create(:account_screening_profile, :with_populated_attributes)
        user = profile.user
        user.enable_feature(:live_sdn_screening)

        user.trade_screening_record.update(msft_trade_screening_status: sdn_screening_status)

        assert user.is_allowed_to_edit_trade_screening_information?
      end
    end

    %w[hit_in_review true_match ssi_d ssi_e ssi_f lic_r].each do |sdn_screening_status|
      test "#{sdn_screening_status} is not allowed to edit personal profile" do
        profile = create(:account_screening_profile, :with_populated_attributes)
        user = profile.user
        user.enable_feature(:live_sdn_screening)

        user.trade_screening_record.update(msft_trade_screening_status: sdn_screening_status)

        refute user.is_allowed_to_edit_trade_screening_information?
      end
    end
  end

  context "#is_allowed_to_remove_billing_information?" do
    TradeControls::SdnScreeningTestHelper::SDN_STATUS_REMOVE_ALLOW_LIST.each do |status|
      test "returns true if the profile has a #{status} screening status" do
        profile = create(:account_screening_profile, msft_trade_screening_status: status, last_trade_screen_date: 8.days.ago)

        assert profile.owner.is_allowed_to_remove_billing_information?
      end
    end

    (AccountScreeningProfile::VALID_SDN_STATUSES - TradeControls::SdnScreeningTestHelper::SDN_STATUS_REMOVE_ALLOW_LIST.map(&:to_sym)).each do |status|
      test "returns false if the profile has a #{status} screening status" do
        profile = create(:account_screening_profile, msft_trade_screening_status: status, last_trade_screen_date: 8.days.ago)

        refute profile.owner.is_allowed_to_remove_billing_information?
      end
    end

    test "returns false if the trade screening record owner is a business" do
      business = create(:business)

      refute business.is_allowed_to_remove_billing_information?
    end

    test "returns false if the owning org is on standard ToS" do
      user = create(:user)
      org = create :organization, admin: user, plan: :free
      org.terms_of_service.update(type: "Standard", actor: user)
      profile = create(:account_screening_profile, :with_org, owner: org)

      refute profile.owner.is_allowed_to_remove_billing_information?
    end

    test "returns false if the account has upcoming charges" do
      profile = create(:account_screening_profile, msft_trade_screening_status: :no_hit, last_trade_screen_date: 8.days.ago)
      User.any_instance.stubs(:no_upcoming_charges?).returns(false).at_least_once

      refute profile.owner.is_allowed_to_remove_billing_information?
    end

    test "returns false if the account does not have a trade screening record" do
      user = create(:user)

      refute user.has_saved_trade_screening_record?
      refute user.is_allowed_to_remove_billing_information?
    end
  end

  context "#has_commercial_interaction_restriction?" do
    test "uses feature type when determining access" do
      profile = create(:account_screening_profile, :with_populated_attributes)
      user = profile.user
      user.enable_feature(:live_sdn_screening)

      user.trade_screening_record.lic_r!

      assert_predicate user, :has_commercial_interaction_restriction?
      assert user.has_commercial_interaction_restriction?(feature_type: :default)
      refute user.has_commercial_interaction_restriction?(feature_type: :cost_management)
    end

    test "uses copilot_vnext feature type when determining access based on country" do
      profile = create(:account_screening_profile, :with_populated_attributes, country_code: "US")
      user = profile.user
      user.enable_feature(:live_sdn_screening)
      user.disable_feature(:sdn_copilot_vnext)

      user.trade_screening_record.lic_a!

      refute_predicate user, :has_commercial_interaction_restriction?
      refute user.has_commercial_interaction_restriction?(feature_type: :default)
      refute user.has_commercial_interaction_restriction?(feature_type: :copilot)
    end

    test "uses copilot feature type when determining access based on country" do
      profile = create(:account_screening_profile, :with_populated_attributes, country_code: "IR")
      user = profile.user
      user.enable_feature(:live_sdn_screening)
      user.disable_feature(:sdn_copilot_vnext)

      user.trade_screening_record.lic_a!

      refute_predicate user, :has_commercial_interaction_restriction?
      refute user.has_commercial_interaction_restriction?(feature_type: :default)
      assert user.has_commercial_interaction_restriction?(feature_type: :copilot)
    end
  end

  context "has_sdn_auto_sponsorable_restrictions?" do
    test "returns false if live_sdn_screening flag disabled" do
      profile = create(:account_screening_profile, msft_trade_screening_status: :hit_in_review)
      user = profile.user

      user.disable_feature(:live_sdn_screening)

      refute_predicate user, :has_sdn_auto_sponsorable_restrictions?
    end

    TradeControls::SdnScreeningTestHelper::NOT_ALLOWED_SDN_AUTO_SPONSORSHIP_STATUSES.each do |status|
      test "returns true when a account screening profile has a screening status of #{status}" do
        profile = create(:account_screening_profile, msft_trade_screening_status: status)
        user = profile.user

        user.enable_feature(:live_sdn_screening)

        assert_predicate user, :has_sdn_auto_sponsorable_restrictions?
      end
    end

    TradeControls::SdnScreeningTestHelper::ALLOWED_SDN_AUTO_SPONSORSHIP_STATUSES.each do |status|
      test "returns false when a account screening profile has a screening status of #{status}" do
        profile = create(:account_screening_profile, msft_trade_screening_status: status)
        user = profile.user

        user.enable_feature(:live_sdn_screening)

        refute_predicate user, :has_sdn_auto_sponsorable_restrictions?
      end
    end

  end

  context "#sdn_suspend" do
    test "doesn't overwrite existing user profile data" do
      user = create(:user)
      profile = create(:account_screening_profile, owner: user)
      user.sdn_suspend(staff_user: User.ghost, reason: "test")
      user.reload

      assert_predicate user, :has_saved_trade_screening_record?
      refute_predicate user, :spammy?
      assert_predicate user, :suspended?
      assert_predicate user, :legal_hold?
      assert_predicate user, :recent_staff_note?
      assert_predicate user.trade_screening_record, :true_match?
      assert_equal profile.first_name, user.trade_screening_record.first_name
    end

    test "creates screening profile" do
      user = create(:user)
      user.sdn_suspend(staff_user: User.ghost, reason: "test")
      user.reload

      assert_predicate user, :has_saved_trade_screening_record?
      refute_predicate user, :spammy?
      assert_predicate user, :suspended?
      assert_predicate user, :legal_hold?
      assert_predicate user, :recent_staff_note?
      assert_predicate user.trade_screening_record, :true_match?
    end

    test "does not cancel a users iAP subscription" do
      copilot_product_uuid = create(:billing_product_uuid, :copilot)
      listing_plan = create(:marketplace_listing_plan, :published)

      plan_subscription = create(:billing_plan_subscription, :zuora, user: @user)
      user = plan_subscription.user

      non_iap_sub = create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_subscription)
      iap_sub = create(:billing_subscription_item, :iap, subscribable: copilot_product_uuid, plan_subscription: plan_subscription)

      refute_predicate user, :suspended?
      assert_predicate non_iap_sub, :active?
      assert_predicate iap_sub, :active?

      perform_enqueued_jobs only: [Billing::CancelSubscriptionItemsJob, TradeControls::Sdn::BillingChangesJob] do
        user.sdn_suspend(staff_user: User.ghost, reason: "test")
      end

      assert_predicate user.reload, :suspended?
      assert_predicate user, :sdn_suspended?
      refute_predicate non_iap_sub.reload, :active?
      assert_predicate iap_sub.reload, :active?
    end
  end

  context "#sdn_unsuspend" do
    test "doesn't overwrite existing user profile data" do
      user = create(:user)
      profile = create(:account_screening_profile, owner: user)
      user.sdn_suspend(staff_user: User.ghost, reason: "test")
      user.sdn_unsuspend(staff_user: User.ghost, reason: "test")
      user.reload

      assert_predicate user, :has_saved_trade_screening_record?
      refute_predicate user, :spammy?
      refute_predicate user, :suspended?
      refute_predicate user, :legal_hold?
      assert_predicate user, :recent_staff_note?
      assert_predicate user.trade_screening_record, :no_hit?
      assert_equal profile.first_name, user.trade_screening_record.first_name
    end

    test "correctly unsuspends pseudo records" do
      user = create(:user)
      user.sdn_suspend(staff_user: User.ghost, reason: "test")
      user.sdn_unsuspend(staff_user: User.ghost, reason: "test")
      user.reload

      assert_predicate user.trade_screening_record, :persisted?
      refute_predicate user.trade_screening_record, :valid?
      refute_predicate user, :spammy?
      refute_predicate user, :suspended?
      refute_predicate user, :legal_hold?
      assert_predicate user, :recent_staff_note?
      assert_predicate user.trade_screening_record, :no_hit?
    end
  end

  context "#unlink_user_from_all_linked_orgs" do
    test "unlinks screening record from org if admin is being suspended" do
      admin = create(:user, :verified, :with_trade_screening_record)
      org = create(:organization, admin: admin)
      org2 = create(:organization, admin: admin)

      assert admin.link_trade_screening_record_to_org(organization: org)
      assert admin.link_trade_screening_record_to_org(organization: org2)
      admin.sdn_suspend(staff_user: User.ghost, reason: "test")

      refute_predicate org.trade_screening_record, :persisted?
      refute_predicate org2.trade_screening_record, :persisted?
    end

    test "unlinks screening record from org if billing manager is being suspended" do
      admin = create(:user, :verified)
      org = create(:organization, admin: admin)
      org2 = create(:organization, admin: admin)
      billing_manager = create(:user, :verified, :with_trade_screening_record)
      org.billing.add_manager(billing_manager, actor: admin)
      org2.billing.add_manager(billing_manager, actor: admin)

      assert billing_manager.link_trade_screening_record_to_org(organization: org)
      assert billing_manager.link_trade_screening_record_to_org(organization: org2)
      billing_manager.sdn_suspend(staff_user: User.ghost, reason: "test")

      refute_predicate org.trade_screening_record, :persisted?
      refute_predicate org2.trade_screening_record, :persisted?
    end
  end

  context "#instrumentation_object_type" do
    test "returns :USER when self is user" do
      assert_equal :USER, @user.instrumentation_object_type
    end

    test "returns :CTOS_ORGANIZATION when self is organization with corporate terms of service" do
      org = create(:organization)
      org.terms_of_service.update(type: "Corporate", actor: org.admin)
      assert_equal :CTOS_ORGANIZATION, org.instrumentation_object_type
    end

    test "returns :ORGANIZATION when self is organization with standard terms of service" do
      org = create(:organization)
      assert_equal :ORGANIZATION, org.instrumentation_object_type
    end

    test "returns :CTOS_ORGANIZATION when self is organization with evaluation terms of service" do
      org = create(:organization)
      org.terms_of_service.update(type: "Evaluation", actor: org.admin)
      assert_equal :CTOS_ORGANIZATION, org.instrumentation_object_type
    end

    test "returns :BUSINESS when self is a business" do
      business = create(:global_business)
      assert_equal :BUSINESS, business.instrumentation_object_type
    end
  end

  context "#trade_screening_record" do
    test "returns the org's pseudo trade screening record even if the admin has a valid screening record" do
      admin = create(:user, :verified)
      org = create(:organization, admin: admin)

      org.trade_screening_record.update({
        city: "",
        country_code: "",
        address1: "",
        address2: "",
        postal_code: "",
        region: "",
        last_trade_screen_date: Time.now.utc,
        msft_trade_screening_status: "lic_r"
      })

      admin_asp = create(:account_screening_profile, owner: admin)
      org_asp = org.trade_screening_record
      refute_equal org_asp.id, admin_asp.id
    end

    test "returns the org admin's trade screening record if the key is set in KV storage" do
      admin = create(:user, :verified)
      admin_asp = create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin)

      TradeCompliance::Kv.store.set("organization.#{org.id}.trade_screening_ref", admin_asp.id.to_s)

      assert admin.has_trade_screening_record_linked_to_org?(organization: org)
      assert_predicate org.trade_screening_record, :persisted?
    end

    test "returns the org's trade screening record and ignore's the admin's trade screening record if ignore_linked_record is passed" do
      admin_profile = create(:account_screening_profile)
      admin = admin_profile.owner
      org = create(:organization, admin: admin)

      TradeCompliance::Kv.store.set("organization.#{org.id}.trade_screening_ref", admin_profile.id.to_s)

      assert admin.has_trade_screening_record_linked_to_org?(organization: org)
      refute_predicate org.trade_screening_record(ignore_linked_record: true), :persisted?
    end

    test "builds and returns a new record if the parent screening record was deleted however the linked KV record failed to unlink" do
      admin = create(:user, :verified)
      screening_record = create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin)

      TradeCompliance::Kv.store.set("organization.#{org.id}.trade_screening_ref", screening_record.id.to_s)

      assert admin.has_trade_screening_record_linked_to_org?(organization: org)
      link_id = org.trade_screening_record_link.link_id
      refute_nil link_id
      assert_equal screening_record.id, link_id

      admin.stubs(:unlink_user_from_all_linked_orgs).returns(false) # simulate failure to unlink
      screening_record.destroy
      org.reload
      refute_nil org.trade_screening_record # return an instance of AccountScreeningProfile
    end
  end

  context "#link_trade_screening_record_to_org" do
    test "creates a reference between the admin's trade screening record and the target SToS org" do
      events = subscribe "org.trade_screening_record_link"
      admin = create(:user, :verified, :with_trade_screening_record)
      org = create(:organization, admin: admin)

      admin.enable_feature(:live_sdn_screening)
      assert admin.link_trade_screening_record_to_org(organization: org)

      expected_payload = {
        perform: :LINK,
        trade_screening_record_link: {
          new_id: "#{admin.trade_screening_record.id}",
          new_screening_status: "not_screened",
        },
        org: org.login,
        org_id: org.id,
        actor: "#{admin}",
        actor_id: admin.id,
      }

      # after linking
      assert_predicate org.trade_screening_record, :persisted?
      assert_predicate org, :has_linked_trade_screening_record?
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "allows admin to link their billing info even when the already linked billing info is restricted" do
      admin = create(:user, :verified, :with_trade_screening_record)
      admin2 = create(:user, :verified, :with_trade_screening_record)
      org = create(:organization, admin: admin)
      org.add_admin(admin2)

      admin = User.find(admin.id)
      admin2 = User.find(admin2.id)
      admin.enable_feature(:live_sdn_screening)
      admin2.enable_feature(:live_sdn_screening)
      assert admin.link_trade_screening_record_to_org(organization: org)
      events = subscribe "org.trade_screening_record_link"
      admin.trade_screening_record.lic_r!

      assert_predicate org.trade_screening_record, :persisted?
      assert_predicate org, :has_linked_trade_screening_record?
      assert admin2.link_trade_screening_record_to_org(organization: org)

      expected_update_payload = {
        perform: :UPDATE,
        trade_screening_record_link: {
          new_id: "#{admin.trade_screening_record.id}",
          old_screening_status: "not_screened",
          new_screening_status: "lic_r",
        },
        org: org.login,
        org_id: org.id,
        actor: "#{admin}",
        actor_id: admin.id,
      }

      expected_link_payload = {
        perform: :LINK,
        trade_screening_record_link: {
          new_id: "#{admin2.trade_screening_record.id}",
          new_screening_status: "not_screened",
        },
        org: org.login,
        org_id: org.id,
        actor: "#{admin2}",
        actor_id: admin2.id,
      }

      # after linking
      assert_equal 3, events.length, "three events were expected"
      assert events.find { |e| e.payload[:perform] == :UNLINK }, "an unlink event was expected"
      assert event = events.find { |e| e.payload[:perform] == :UPDATE }, "an update event was expected"
      assert_equal expected_update_payload, event.payload
      assert event = events.find { |e| e.payload[:perform] == :LINK }, "a link event was expected"
      assert_equal expected_link_payload, event.payload
    end

    test "prevents admin from linking their billing info when they are restricted" do
      admin = create(:user, :verified, :with_trade_screening_record)
      admin2 = create(:user, :verified, :with_trade_screening_record)
      org = create(:organization, admin: admin)
      org.add_admin(admin2)

      admin.enable_feature(:live_sdn_screening)
      admin2.enable_feature(:live_sdn_screening)
      assert admin.link_trade_screening_record_to_org(organization: org)
      admin2.trade_screening_record.lic_r!

      events = subscribe "org.trade_screening_record_link"
      refute admin2.link_trade_screening_record_to_org(organization: org)
      assert_empty events
      assert_predicate org.trade_screening_record, :persisted?
    end

    test "creates a reference between the billing manager's trade screening record and the target SToS org" do
      admin = create(:user, :verified)
      org = create(:organization, admin: admin)
      billing_manager = create(:user, :verified, :with_trade_screening_record)
      org.billing.add_manager(billing_manager, actor: admin)

      admin.enable_feature(:live_sdn_screening)
      billing_manager.enable_feature(:live_sdn_screening)
      assert billing_manager.link_trade_screening_record_to_org(organization: org)

      assert_predicate org.trade_screening_record, :persisted?
    end

    test "does not create a reference if admin does not have a persisted screening record" do
      admin = create(:user, :verified)
      org = create(:organization, admin: admin)

      refute admin.link_trade_screening_record_to_org(organization: org)

      refute_predicate org.trade_screening_record, :persisted?
    end

    test "deletes org's no_hit screening record which came from LIC-R compliance screening before creating the reference" do
      admin = create(:user, :verified)
      create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin)

      no_hit_record = org.create_trade_screening_record({
        city: "",
        country_code: "",
        address1: "",
        address2: "",
        postal_code: "",
        region: "",
        last_trade_screen_date: Time.now.utc,
        msft_trade_screening_status: "no_hit"
      })

      assert admin.link_trade_screening_record_to_org(organization: org)

      assert_nil AccountScreeningProfile.find_by(id: no_hit_record.id) # record is deleted
      assert admin.has_trade_screening_record_linked_to_org?(organization: org)
    end

    test "deletes org's lic_r screening record which came from LIC-R compliance screening before creating the reference" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      admin = create(:user, :verified)
      create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin)

      lic_r_record = org.create_trade_screening_record!({
        city: "",
        country_code: "",
        address1: "",
        address2: "",
        postal_code: "",
        region: "",
        last_trade_screen_date: Time.now.utc,
        msft_trade_screening_status: "lic_r"
      })

      assert admin.link_trade_screening_record_to_org(organization: org, screening_flow: "UPGRADE")

      expected_tags = [
        "new_status:#{admin.trade_screening_record.msft_trade_screening_status}",
        "old_status:lic_r",
        "screening_flow:UPGRADE"
      ]
      assert_dogstats_increment 1, "sdn.individual_owned_org_pseudo_record_dropped"

      assert_nil AccountScreeningProfile.find_by(id: lic_r_record.id) # record is deleted
      assert admin.has_trade_screening_record_linked_to_org?(organization: org)
    end
  end

  context "#has_linked_trade_screening_record?" do
    test "returns true if org's trade screening record is owned by an admin" do
      admin = create(:user, :verified)
      create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin)

      admin.link_trade_screening_record_to_org(organization: org)

      assert_predicate org, :has_linked_trade_screening_record?
    end

    test "returns false if org does not have any saved screening record" do
      admin = create(:user, :verified)
      create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin)

      refute_predicate org, :has_linked_trade_screening_record?
    end

    test "returns false if org has a true_match pseudo screening record" do
      org = create(:organization)
      create(:account_screening_profile, :lic_r_enabled_and_true_match, owner: org)

      refute_predicate org, :has_linked_trade_screening_record?
      assert_predicate org.trade_screening_record, :true_match?
    end

    test "returns false if org has a no_hit pseudo screening record" do
      org = create(:organization)
      create(:account_screening_profile, :lic_r_enabled_and_no_hit, owner: org)

      assert_predicate org.trade_screening_record, :no_hit?
      refute_predicate org, :has_linked_trade_screening_record?
    end

    test "returns false if org has a lic_r pseudo screening record" do
      org = create(:organization)
      create(:account_screening_profile, :lic_r_enabled_and_restricted, owner: org)

      org.reload
      assert_predicate org.trade_screening_record, :lic_r?
      refute_predicate org, :has_linked_trade_screening_record?
    end
  end

  context "#unlink_trade_screening_record_from_org" do
    test "current admin removes the reference between the other admin's trade screening record and the target SToS org" do
      events = subscribe "org.trade_screening_record_link"

      admin_1 = create(:user, :verified)
      admin_2 = create(:user, :verified)
      create(:account_screening_profile, owner: admin_2)
      org = create(:organization, admin: admin_2, plan: GitHub::Plan.free)
      org.add_admin(admin_1)

      admin_2.link_trade_screening_record_to_org(organization: org)
      assert org.has_linked_trade_screening_record?

      admin_1.unlink_trade_screening_record_from_org(organization: org)


      expected_payload = {
        perform: :UNLINK,
        trade_screening_record_link: {
          old_id: "#{admin_2.trade_screening_record.id}",
          old_screening_status: admin_2.trade_screening_record.msft_trade_screening_status,
        },
        org: org.login,
        org_id: org.id,
        actor: "#{admin_1}",
        actor_id: admin_1.id,
      }

      # after unlinking
      refute org.has_linked_trade_screening_record?
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "a non-admin user cannot unlink a screening record from org" do
      non_admin_user = create(:staff_admin_user)

      some_admin = create(:user, :verified)
      create(:account_screening_profile, owner: some_admin)
      org = create(:organization, admin: some_admin, plan: GitHub::Plan.free)

      some_admin.link_trade_screening_record_to_org(organization: org)
      assert org.has_linked_trade_screening_record?

      non_admin_user.unlink_trade_screening_record_from_org(organization: org)

      # after failed unlinking
      assert org.has_linked_trade_screening_record?
    end

    test "current admin removes their own trade screening record reference to the target SToS org" do
      admin = create(:user, :verified)
      create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin)

      admin.link_trade_screening_record_to_org(organization: org)

      assert org.has_linked_trade_screening_record?
      admin.unlink_trade_screening_record_from_org(organization: org)

      # after unlinking
      refute org.has_linked_trade_screening_record?
      report = Failbot.reports.last
      assert_nil report
    end

    test "reports to sentry when removing linked screening record fails" do
      admin = create(:user, :verified)
      create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin)
      TradeControls::TradeScreeningRecordLink.any_instance.stubs(:remove).returns(false)

      admin.link_trade_screening_record_to_org(organization: org)

      assert org.has_linked_trade_screening_record?
      admin.unlink_trade_screening_record_from_org(organization: org)

      assert_predicate org, :has_linked_trade_screening_record?
      assert_includes Failbot.reports.map { |r| Failbot.exception_message_from_hash(r) }, "failed to remove linked screening record"
    end

    test "when a screening record is unlinked from an org, the org's payment method is dropped" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      admin = create(:user, :verified)
      create(:account_screening_profile, owner: admin)
      org = create(:credit_card_org, admin: admin)

      admin.link_trade_screening_record_to_org(organization: org)

      assert org.has_linked_trade_screening_record?
      assert_predicate org, :has_valid_payment_method?

      admin.unlink_trade_screening_record_from_org(organization: org)

      # after unlinking
      refute org.has_linked_trade_screening_record?
      refute_predicate org, :has_valid_payment_method?
      assert_equal 1, stats.increments("sdn.unlink_record.org_payment_method_dropped").count
    end
  end

  context "#has_trade_screening_record_linked_to_org" do
    test "returns true if the admin user has a trade screening record linked to the target SToS org" do
      admin = create(:user, :verified)
      create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin)

      admin.link_trade_screening_record_to_org(organization: org)

      assert admin.has_trade_screening_record_linked_to_org?(organization: org)
    end

    test "returns false if the admin user does not have a trade screening record linked to the target SToS org" do
      admin = create(:user, :verified)
      org = create(:organization, admin: admin)

      admin.link_trade_screening_record_to_org(organization: org)

      refute admin.has_trade_screening_record_linked_to_org?(organization: org)
    end
  end
end unless GitHub.enterprise?
