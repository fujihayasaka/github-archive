# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module TradeCompliance::TradeScreening
  class EisPollJobTest < GitHub::TestCase
    skip_enterprise

    include HydroTestHelpers
    include JobTestHelper
    include DogstatsTestHelpers

    setup do
      skip unless GitHub.billing_enabled?
      # we enable this flag to make sure we test the full path of SDN. this flag is responsible for applying SDN logic.
      enable_feature_flag(:live_sdn_screening)
    end

    test "makes calls to EIS for fetching new messages then updates user and contact statuses" do
      profile = create(:account_screening_profile, :with_credit_card, external_uuid: "d60756eb-bd19-4013-GTHB-1SSINDTST36")
      user = profile.user
      create(:billing_contact, customer: user.customer)
      billing_contact_request_id = "1"
      AccountScreeningProfile.any_instance.stubs(:request_id).returns(billing_contact_request_id)
      Billing::Contact.any_instance.stubs(:trade_screening_request_id).returns(billing_contact_request_id)

      response = make_request("trade_controls/sdn/valid_eis_api_call") do
        EisPollJob.perform_now
      end

      user.reload
      profile.reload
      assert_predicate profile, :true_match?
      assert_predicate profile, :billing_no_hit?
      assert_predicate user.customer.contacts.first, :no_hit?
      assert_equal "0000000000578332688", TradeCompliance::Kv.store.get("trade_controls:sdn:eis_offset_value").value!
    end

    test "makes calls to EIS for fetching new messages then updates user even if contact info is missing" do
      profile = create(:account_screening_profile, :with_credit_card, external_uuid: "d60756eb-bd19-4013-GTHB-1SSINDTST36")
      user = profile.user
      enable_feature_flag(:read_billing_information_from_contacts, user)

      response = make_request("trade_controls/sdn/valid_eis_api_call") do
        EisPollJob.perform_now
      end

      user.reload
      profile.reload
      assert_predicate profile, :true_match?
      assert_predicate profile, :billing_true_match?
      assert_predicate user.customer.contacts, :blank?
      assert_equal "0000000000578332688", TradeCompliance::Kv.store.get("trade_controls:sdn:eis_offset_value").value!
    end

    test "makes calls to EIS for fetching new messages but doesn't take action if user is already true_match" do
      upp = create(:account_screening_profile, external_uuid: "d60756eb-bd19-4013-GTHB-1SSINDTST36", msft_trade_screening_status: "true_match")

      AccountScreeningProfile.any_instance.expects(:save).once.returns(true)
      response = make_request("trade_controls/sdn/valid_eis_api_call") do
        EisPollJob.perform_now
      end
      upp.reload

      assert_equal 0, upp.errors.size
      assert_equal "0000000000578332688", TradeCompliance::Kv.store.get("trade_controls:sdn:eis_offset_value").value!
    end

    test "makes calls to EIS for fetching new messages and updates the user status to no_hit" do
      upp = create(:account_screening_profile)
      ApiService.stubs(:make_eis_request).returns(build_eis_response_body(external_id: upp.external_uuid, status: "no_hit"))

      EisPollJob.perform_now
      upp.reload

      assert_equal "no_hit", upp.msft_trade_screening_status
      assert_equal "0000000000578332688", TradeCompliance::Kv.store.get("trade_controls:sdn:eis_offset_value").value!
    end

    test "should gracefully handle the case where the screening record owner is deleted before the EIS update is received for the record" do
      upp = create(:account_screening_profile)
      upp.owner.delete
      ApiService.stubs(:make_eis_request).returns(build_eis_response_body(external_id: upp.external_uuid, status: "data_issue"))

      EisPollJob.perform_now

      needle = Failbot.reports.last
      assert_equal "TradeCompliance::TradeScreening::UnknownActorError", Failbot.exception_classname_from_hash(needle)
      assert_match "AccountScreeningProfile owner is nil for external ID: #{upp.external_uuid}", Failbot.exception_message_from_hash(needle)
    end

    test "makes calls to EIS for fetching new messages and updates the user status to hit_in_review" do
      upp = create(:account_screening_profile)
      ApiService.stubs(:make_eis_request).returns(build_eis_response_body(external_id: upp.external_uuid, status: "hit_in_review"))

      EisPollJob.perform_now
      upp.reload

      assert_equal "hit_in_review", upp.msft_trade_screening_status
      assert_equal "0000000000578332688", TradeCompliance::Kv.store.get("trade_controls:sdn:eis_offset_value").value!
    end

    test "updates last_trade_screen_date of each record successfully polled" do
      upp = create(:account_screening_profile)
      assert_nil upp.last_trade_screen_date

      current_time = Time.new(2020, 11, 25, 1, 0, 0).utc
      Timecop.freeze(current_time) do
        eis_response = build_eis_response_body(external_id: upp.external_uuid, status: "no_hit")
        ApiService.stubs(:make_eis_request).returns(eis_response)

        EisPollJob.perform_now
      end

      upp.reload
      assert_equal upp.last_trade_screen_date, current_time
    end

    test "reports to failbot if the status isn't one of the agreed on values" do
      upp = create(:account_screening_profile)
      ApiService.stubs(:make_eis_request).returns(build_eis_response_body(external_id: upp.external_uuid, status: "a_wrong_status"))

      EisPollJob.perform_now

      needle = Failbot.reports.last
      assert_equal "TradeCompliance::TradeScreening::EisBusResponseParsingError", Failbot.exception_classname_from_hash(needle)
    end

    test "reports a user not found exception if the external_id doesn't refer to a user" do
      ApiService.stubs(:make_eis_request).returns(build_eis_response_body(external_id: "1234-5678-9101-1121", status: "a_wrong_status"))

      EisPollJob.perform_now

      needle = Failbot.reports.last
      assert_equal "ActiveRecord::RecordNotFound", Failbot.exception_classname_from_hash(needle)
    end

    test "when call to EIS returns empty list it doesn't throw exceptions" do
      ApiService.stubs(:make_eis_request).returns(EisBusResponse.new(
        last_offset: "1",
        messages: []
      ))

      EisPollJob.perform_now

      assert_equal "1", TradeCompliance::Kv.store.get("trade_controls:sdn:eis_offset_value").value!
    end

    test "doesn't throw exception but reports failure when updating screening status, even if screening record is malformed" do
      AccountScreeningProfile.any_instance.stubs(:name_required?).returns(false)
      upp = create(:account_screening_profile, first_name: "")

      AccountScreeningProfile.any_instance.stubs(:name_required?).returns(true)
      Failbot.expects(:report).with do |err|
        assert_kind_of EisBusResponseParsingError, err
        assert_match /first_name:blank-first_name:too_short/, err.to_s
      end
      ApiService.stubs(:make_eis_request).returns(build_eis_response_body(external_id: upp.external_uuid, status: "hit_in_review"))

      EisPollJob.perform_now

      assert_equal "hit_in_review", upp.reload.msft_trade_screening_status
      assert_predicate upp.first_name, :blank?, "first_name should be blank"
    end

    test "rescues the failure and reports to failbot" do
      ApiService.stubs(:make_eis_request).raises(ApiServiceError)

      EisPollJob.perform_now

      needle = Failbot.reports.last
      assert_equal "TradeCompliance::TradeScreening::ApiServiceError", Failbot.exception_classname_from_hash(needle)
    end

    test "reports failure to update but doesn't raise exception to halt the job" do
      upp = create(:account_screening_profile)

      # This is to make sure that updates are allowed regardless if validation would've failed otherwise
      upp.update_column(:first_name, "")
      AccountScreeningProfile.any_instance.stubs(:name_required?).returns(true)

      # since we no longer validate on save, this is the only way to simulate an error
      AccountScreeningProfile.any_instance.stubs(:save).returns(false)
      ApiService.stubs(:make_eis_request).returns(build_eis_response_body(external_id: upp.external_uuid, status: "hit_in_review"))

      Failbot.expects(:report).with do |err, context|
        assert_kind_of EisBusResponseParsingError, err
        assert_match /save:unsuccessful/, err.to_s
        assert_equal upp.external_uuid, context[:external_uuid]
        assert_equal "hit_in_review", context[:status]
        assert context[:offset].present?
      end

      EisPollJob.perform_now
    end

    test "publishes hydro event on successful request" do
      ts_record = create(:account_screening_profile)
      eid = "d60756eb-bd19-4013-GTHB-1SSINDTST201"
      ApiService.stubs(:make_eis_request).returns(build_eis_response_body(eid: eid, external_id: ts_record.external_uuid, status: "true_match"))

      EisPollJob.perform_now
      assert_hydro_published({
        country: ts_record.country_code,
        external_user_id: ts_record.external_uuid,
        request_id: eid,
        request_type: "EIS",
        status: "true_match",
        actor_type: "USER"
      }, schema: "github.trade_screening.v0.TradeScreeningResult")
    end

    %w[ssi_d ssi_e ssi_f lic_r data_issue].each do |lr_status|
      test "an actor with an #{lr_status} status cannot perform a commercial interaction" do
        upp = create(:account_screening_profile)
        user = upp.user

        enable_feature_flag(:live_sdn_screening, user)

        refute user.has_commercial_interaction_restriction?

        status = lr_status.split("_").map(&:titleize).join(" ")
        eis_response = build_eis_response_body(external_id: upp.external_uuid, status: status)
        ApiService.stubs(:make_eis_request).returns(eis_response)

        EisPollJob.perform_now

        user.reload
        assert user.has_commercial_interaction_restriction?
      end
    end

    %w[ssi_d_30 ssi_e_60 ssi_f_14 lic_a].each do |la_status|
      test "an actor with an #{la_status} status can perform a commercial interaction" do
        # user with a license required status
        upp = create(:account_screening_profile, msft_trade_screening_status: "lic_r")
        user = upp.user

        enable_feature_flag(:live_sdn_screening, user)

        assert user.has_commercial_interaction_restriction?

        status = la_status.split("_").map(&:titleize).join(" ")
        eis_response = build_eis_response_body(external_id: upp.external_uuid, status: status)
        ApiService.stubs(:make_eis_request).returns(eis_response)

        EisPollJob.perform_now

        user.reload
        assert_nil user.trade_screening_record.screening_status_reason
        refute user.has_commercial_interaction_restriction?
      end
    end

    test "an actor with a data_issue status has the status reason persisted" do
      upp = create(:account_screening_profile)
      user = upp.user
      upp.metadata = { test: "don't overwrite this value" }
      upp.save!

      enable_feature_flag(:live_sdn_screening, user)

      refute user.has_commercial_interaction_restriction?
      refute_empty user.trade_screening_record.metadata
      assert user.trade_screening_record.metadata.key?("test")

      status = "Data Issue"
      eis_response = build_eis_response_body(external_id: upp.external_uuid, status: status, status_reason: "#{status} - Name")
      ApiService.stubs(:make_eis_request).returns(eis_response)

      EisPollJob.perform_now

      user.reload
      assert user.has_commercial_interaction_restriction?
      refute_empty user.trade_screening_record.metadata
      assert user.trade_screening_record.metadata.key?("test")
      refute_empty user.trade_screening_record.screening_status_reason
      assert_equal "data_issue: #{status} - Name", user.trade_screening_record.screening_status_reason
    end

    test "an actor with a data_issue status without status_reason returned defaults to Data Issue - Other as the reason" do
      upp = create(:account_screening_profile)
      user = upp.user
      upp.metadata = { test: "don't overwrite this value" }
      upp.save!

      enable_feature_flag(:live_sdn_screening, user)

      refute user.has_commercial_interaction_restriction?
      refute_nil user.trade_screening_record.metadata
      assert user.trade_screening_record.metadata.key?("test")

      status = "Data Issue"
      eis_response = build_eis_response_body(external_id: upp.external_uuid, status: status)
      ApiService.stubs(:make_eis_request).returns(eis_response)

      EisPollJob.perform_now

      user.reload
      assert user.has_commercial_interaction_restriction?
      refute_empty user.trade_screening_record.metadata
      assert user.trade_screening_record.metadata.key?("test")
      refute_empty user.trade_screening_record.screening_status_reason
      assert_equal "Data Issue - Missing", user.trade_screening_record.screening_status_reason
    end

    test "assert retry on dirty exit" do
      assert_retry_on_dirty_exit(job: EisPollJob)
    end

    test "reports number of messages in a batch and processed messages to datadog" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      upp = create(:account_screening_profile, external_uuid: "d60756eb-bd19-4013-GTHB-1SSINDTST36")

      response = make_request("trade_controls/sdn/valid_eis_api_call") do
        EisPollJob.perform_now
      end

      assert_equal 1, stats.counts("sdn_api_service.eis.batch.count", tags: ["offset:0"]).first.value
      assert_equal 1, stats.counts("sdn_api_service.eis.batch.processed", tags: ["offset:0"]).first.value

    end

    test "reports stream end when loops through 2 empty messages" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      ApiService.stubs(:make_eis_request).returns(EisBusResponse.new(
        last_offset: "1",
        messages: []
      ))

      EisPollJob.perform_now
      assert_equal 1, stats.counts("sdn_api_service.eis.end_of_stream").first.value
      assert_equal 2, stats.counts("sdn_api_service.eis.batch.count").count
    end

    private

    sig { params(cassette: String, options: T::Hash[Symbol, T.untyped], block: T.untyped).void }
    def make_request(cassette, **options, &block)
      VCR.use_cassette(cassette, **options) do
        yield
      end
    end

    sig do
      params(
        external_id: String,
        status: String,
        eid: T.nilable(String),
        status_reason: T.nilable(String)
      ).returns(EisBusResponse)
    end
    def build_eis_response_body(external_id:, status:, eid: nil, status_reason: nil)
      EisBusResponse.parse(response: {
        messages: [
          {
            properties: {
              Cohort: "GITHUB-SELFSERV",
              Source: "Online",
              Action: "alertconfirmed"
            },
            messageBody: {
              messagePayload: "{\"ScrRespEnv\":{\"EId\":\"#{eid}\",\"DT\":\"2020-10-13T12:02:25.5056640-00:00\",\"SummResult\":\"#{status}\",\"ScrResps\":{\"ScrResp\":[{\"ReqID\":\"IndName_IndAddr\",\"ExternalRefID\":\"#{external_id}\",\"Result\":\"#{status}\",\"ResultDesc\":\"#{status_reason}\",\"Type\":\"Address\",\"Errs\":{\"Err\":[{\"ErrCode\":\"\",\"ErrDesc\":\"\"}]}}]}}}"
            },
          }
        ],
        lastOffset: "0000000000578332688"
      })
    end

    sig do
      params(
        upp: AccountScreeningProfile,
        status: String,
        status_reason: T.nilable(String)
      ).returns(EisBusResponse)
    end
    def build_empty_eis_response_body(upp:, status:, status_reason: nil)
      EisBusResponse.parse(response: {
        messages: [
          {
            properties: {
              Cohort: "GITHUB-SELFSERV",
              Source: "Online",
              Action: "alertconfirmed"
            },
            messageBody: {
              messagePayload: "{\"ScrRespEnv\":{\"EId\":\"\",\"DT\":\"2020-10-13T12:02:25.5056640-00:00\",\"SummResult\":\"#{status}\",\"ScrResps\":{\"ScrResp\":[]}}}"
            },
          }
        ],
        lastOffset: "0000000000578332688"
      })
    end
  end
end
