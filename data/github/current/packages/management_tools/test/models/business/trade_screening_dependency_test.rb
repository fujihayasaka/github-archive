# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessTradeScreeningDependencyTest < GitHub::TestCase
  include TradeCompliance::TradeScreening::TradeScreeningTestHelpers

  def make_live_sdn_request(cassette, **options, &block)
    VCR.use_cassette(cassette, **options) do
      yield
    end
  end

  fixtures do
    enable_feature_flag(:live_sdn_screening)
    @profile = create(:account_screening_profile, :with_business)
    @business = @profile.business
    @staffer = create :staff_admin_user
  end

  context "#perform_live_sdn_screening" do
    test "it sets external_uuid field before making trade screening request when it's not set" do
      upp = create(:account_screening_profile, :with_business)
      upp.update_column(:external_uuid, nil) # ensure external uuid is nil before making request
      owner = upp.owner

      assert_predicate upp, :not_screened?
      assert_predicate upp.external_uuid, :blank?

      can_proceed = make_live_sdn_request("trade_controls/sdn/live_api_bad_data_error") do
        owner.perform_live_sdn_screening
      end

      refute can_proceed

      upp.reload
      assert_predicate upp, :data_issue?
      assert_predicate upp.external_uuid, :present?
      assert_predicate upp.screening_status_reason, :present?
    end

    test "calls sdn live api service, saves hit in review status and returns false" do
      upp = create(:account_screening_profile, :with_business)
      owner = upp.owner

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
      refute owner.perform_live_sdn_screening

      upp.reload
      assert upp.hit_in_review?
    end

    test "force:true force calls the api service and ignores the requirement of the record needing a not_screened status" do
      upp = create(:account_screening_profile, :with_business, :with_populated_attributes, msft_trade_screening_status: "no_hit")
      owner = upp.owner

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
      refute owner.perform_live_sdn_screening(force: true)

      upp.reload
      assert upp.hit_in_review?
    end

    test "does not call the screening API if the business does not have all the required fields" do
      upp = create(:account_screening_profile, :with_business)
      upp.update_attribute(:entity_name, nil)
      owner = upp.owner

      TradeCompliance::TradeScreening::ApiService.any_instance.expects(:request_trade_screening).never
      assert owner.perform_live_sdn_screening
    end

    test "calls sdn live api service, saves data issue status" do
      upp = create(:account_screening_profile, :with_business)
      owner = upp.owner

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
      refute owner.perform_live_sdn_screening

      upp.reload
      assert upp.data_issue?
      assert_predicate upp.screening_status_reason, :present?
    end

    test "it sets retry status and returns true if parsing of response fails" do
      upp = create(:account_screening_profile, :with_business)
      owner = upp.owner

      TradeCompliance::TradeScreening::LiveResponse.stubs(:parse).raises(TradeCompliance::TradeScreening::LiveResponseParsingError)

      assert upp.not_screened?
      can_proceed = make_live_sdn_request("trade_controls/sdn/valid_business_live_api_call") do
        owner.perform_live_sdn_screening
      end

      assert can_proceed

      upp.reload
      assert upp.retry?
    end

    test "it sets retry status and returns true if api authentication fails" do
      upp = create(:account_screening_profile, :with_business)
      owner = upp.owner

      assert upp.not_screened?

      can_proceed = make_live_sdn_request("trade_controls/sdn/unauthorized_live_error", allow_playback_repeats: true) do
        owner.perform_live_sdn_screening
      end

      assert can_proceed

      upp.reload
      assert upp.retry?
    end

    test "it sets ingestion error status and returns false if ingestion error" do
      upp = create(:account_screening_profile, :with_business)
      owner = upp.owner
      assert upp.not_screened?

      can_proceed = make_live_sdn_request("trade_controls/sdn/live_api_bad_request_error") do
        owner.perform_live_sdn_screening
      end

      refute can_proceed

      upp.reload
      assert upp.ingestion_error?
    end

    test "it sets data issue status and does not proceed with interaction" do
      upp = create(:account_screening_profile, :with_business)
      owner = upp.owner

      assert upp.not_screened?

      can_proceed = make_live_sdn_request("trade_controls/sdn/live_api_bad_data_error") do
        owner.perform_live_sdn_screening
      end

      refute can_proceed

      upp.reload
      assert_predicate upp, :data_issue?
      assert_predicate upp.screening_status_reason, :present?
    end
  end if GitHub.billing_enabled?

  context "#sdn_suspend" do
    test "can be suspended" do
      reason = "business was suspended by staff"

      @business.sdn_suspend(staff_user: @staffer, reason: reason)

      # Assertions to check org suspension worked
      assert_predicate @business.trade_screening_record, :true_match?
      assert_predicate @business, :sdn_suspended?
      assert_predicate @business, :suspended?
    end

    test "adds staff note on SDN suspension" do
      reason = "business was suspended by staff"

      @business.sdn_suspend(staff_user: @staffer, reason: reason)

      assert @business.staff_notes.any?
      assert_equal "DO NOT MODIFY THIS ACCOUNT WITHOUT APPROVAL FROM TRADE SUPPORT/CELA. business was suspended by staff", @business.staff_notes.last.body
    end

    test "it doesn't send a trade restriction enforcement email" do
      reason = "business was suspended by staff"

      Business.any_instance.expects(:send_trade_controls_enforcement_email).never

      @business.sdn_suspend(staff_user: @staffer, reason: reason)
    end

    test "it raises error when reason is blank" do
      assert_raises_with_message AccountScreeningProfile::AccountScreeningProfileUpdateError, "Reason is required!" do
        @business.sdn_suspend(staff_user: @staffer, reason: "")
      end
    end
  end if GitHub.billing_enabled?

  context "#sdn_unsuspend" do
    test "can be unsuspended by staff" do
      @business.sdn_suspend(staff_user: @staffer, reason: "suspended")
      assert_predicate @business, :sdn_suspended?
      assert_predicate @business, :suspended?

      reason = "unsuspended"
      @business.sdn_unsuspend(staff_user: @staffer, reason: reason)

      assert_predicate @business.trade_screening_record, :no_hit?
      refute_predicate @business, :sdn_suspended?
      refute_predicate @business, :suspended?
      assert_predicate @business.staff_notes, :any?
      assert_equal reason, @business.staff_notes.last.body
    end

    test "it raises error when reason is blank" do
      assert_raises_with_message AccountScreeningProfile::AccountScreeningProfileUpdateError, "Reason is required!" do
        @business.sdn_unsuspend(staff_user: @staffer, reason: "")
      end
    end
  end if GitHub.billing_enabled?

  context "#has_saved_trade_screening_record?" do
    test "returns false when there's no profile" do
      owner = create(:business)

      refute_predicate owner, :has_saved_trade_screening_record?
    end

    test "returns true when profile is valid" do
      profile = create(:account_screening_profile, :with_business, :with_business)
      owner = profile.owner

      assert_predicate owner, :has_saved_trade_screening_record?
    end
  end if GitHub.billing_enabled?

  context "#is_allowed_to_edit_trade_screening_information?" do
    %w[no_hit not_screened ssi_e_60 ssi_d_30 ssi_f_14 lic_a ingestion_error data_issue].each do |sdn_screening_status|
      test "#{sdn_screening_status} is allowed to edit personal profile" do
        profile = create(:account_screening_profile, :with_business, :with_populated_attributes)
        owner = profile.owner

        owner.trade_screening_record.update(msft_trade_screening_status: sdn_screening_status)

        assert owner.is_allowed_to_edit_trade_screening_information?
      end
    end

    %w[hit_in_review true_match ssi_d ssi_e ssi_f lic_r].each do |sdn_screening_status|
      test "#{sdn_screening_status} is not allowed to edit personal profile" do
        profile = create(:account_screening_profile, :with_business, :with_populated_attributes)
        owner = profile.owner

        owner.trade_screening_record.update(msft_trade_screening_status: sdn_screening_status)

        refute owner.is_allowed_to_edit_trade_screening_information?
      end
    end
  end if GitHub.billing_enabled?

  context "#is_allowed_to_remove_billing_information?" do
    TradeControls::SdnScreeningTestHelper::SDN_STATUS_REMOVE_ALLOW_LIST.each do |status|
      test "returns true if the profile has a #{status} screening status" do
        owner = create(:business, :with_trade_screening_record, :with_self_serve_payment, trial_expires_at: 30.days.from_now)
        owner.trade_screening_record.update_attribute :msft_trade_screening_status, status
        owner.trade_screening_record.update_attribute :last_trade_screen_date, 8.days.ago

        assert_predicate owner, :is_allowed_to_remove_billing_information?
      end
    end

    (AccountScreeningProfile::VALID_SDN_STATUSES - TradeControls::SdnScreeningTestHelper::SDN_STATUS_REMOVE_ALLOW_LIST.map(&:to_sym)).each do |status|
      test "returns false if the profile has a #{status} screening status" do
        owner = create(:business, :with_trade_screening_record, :with_self_serve_payment, trial_expires_at: 30.days.from_now)
        owner.trade_screening_record.update_attribute :msft_trade_screening_status, status
        owner.trade_screening_record.update_attribute :last_trade_screen_date, 8.days.ago

        refute_predicate owner, :is_allowed_to_remove_billing_information?
      end
    end

    test "returns false if the account does not have a trade screening record" do
      owner = create(:business)

      refute_predicate owner, :has_saved_trade_screening_record?
      refute_predicate owner, :is_allowed_to_remove_billing_information?
    end
  end if GitHub.billing_enabled?

  context "#has_commercial_interaction_restriction?" do
    context "organization" do
      test "uses feature type when determining access" do
        profile = create(:account_screening_profile, :with_business, :with_populated_attributes)
        owner = profile.owner

        owner.trade_screening_record.update \
          msft_trade_screening_status: "lic_r"

        assert owner.has_commercial_interaction_restriction?
        assert owner.has_commercial_interaction_restriction?(feature_type: :default)
        refute owner.has_commercial_interaction_restriction?(feature_type: :cost_management)
      end

      test "returns true when the business has a true_match record and any of the owned orgs has full trade restrictions" do
        org1 = create(:organization)
        org2 = create(:organization)
        business = create :business, name: "Avocado Corp", organizations: [org1, org2]
        create(:account_screening_profile, :with_business, owner: business, msft_trade_screening_status: "true_match")

        org1.trade_controls_restriction.full!
        business.mark_as_spammy
        assert business.has_commercial_interaction_restriction?
      end
    end
  end if GitHub.billing_enabled?

  context "has_sdn_auto_sponsorable_restrictions?" do
    TradeControls::SdnScreeningTestHelper::NOT_ALLOWED_SDN_AUTO_SPONSORSHIP_STATUSES.each do |status|
      test "returns true when a account screening profile has a screening status of #{status}" do
        profile = create(:account_screening_profile, :with_business, msft_trade_screening_status: status)
        owner = profile.owner

        assert_predicate owner, :has_sdn_auto_sponsorable_restrictions?
      end
    end

    TradeControls::SdnScreeningTestHelper::ALLOWED_SDN_AUTO_SPONSORSHIP_STATUSES.each do |status|
      test "returns true when a account screening profile has a screening status of #{status}" do
        profile = create(:account_screening_profile, :with_business, msft_trade_screening_status: status)
        owner = profile.owner

        assert_predicate owner, :has_sdn_auto_sponsorable_restrictions?
      end
    end

  end if GitHub.billing_enabled?

  context "#send_true_match_internal_notification" do
    test "sends true match email when the business has a true_match screening status" do
      business = create(:account_screening_profile, :with_business, :no_hit).owner
      business.expects(:send_true_match_internal_notification).once
      disable_feature_flag(:improved_controls_for_true_match, business)

      business.trade_screening_record.true_match!
    end
  end if GitHub.billing_enabled?

  context "#instrumentation_object_type" do
    test "returns :BUSINESS when self is a business" do
      business = create(:global_business)
      assert_equal :BUSINESS, business.instrumentation_object_type
    end
  end

  context "#transfer_trade_screening_record" do
    test "transfers the trade screening record from an organization to a Business" do
      user = create(:user, :verified)
      organization = create :organization, :with_corporate_terms, :with_valid_contact_for_billing, admin: user, plan: "business_plus"
      business = create(:global_business)

      assert_predicate organization.trade_screening_record, :no_hit?
      assert_predicate organization.billing_contact, :valid?
      assert organization.billing_contact.valid?(:entity_trade_screening)


      billing_contact = organization.billing_contact
      trade_screening_record = organization.trade_screening_record

      business.transfer_trade_screening_record(organization)

      assert_equal business.reload.billing_contact, billing_contact.reload # Trade screening record should now be attached to the Business
      assert_equal business.reload.trade_screening_record, trade_screening_record.reload # Trade screening record should now be attached to the Business
      assert_equal business.id, trade_screening_record.owner_id   # Owner of the TSR is now the business
      assert_predicate trade_screening_record, :no_hit?
      assert_equal business.trade_screening_record.external_uuid, trade_screening_record.external_uuid
    end

    test "does not transfer the trade screening record from an organization if it does not have a valid business schema" do
      standard_owner = create(:user, :with_valid_contact_for_billing, :verified)
      organization = create(:organization, admin: standard_owner)
      business = create(:global_business)

      standard_owner.link_trade_screening_record_to_org(organization: organization)  # Create standard ToS trade screening record
      assert_predicate organization.trade_screening_record, :no_hit?
      assert_predicate organization.trade_screening_record, :valid?
      refute organization.trade_screening_record.valid?(:entity)
      assert_equal organization.trade_screening_record.owner_id, standard_owner.id  # Owner of the TSR is the organization's admin

      billing_contact = organization.billing_contact
      trade_screening_record = organization.trade_screening_record

      business.transfer_trade_screening_record(organization)

      refute_equal business.reload.billing_contact, billing_contact.reload # Trade screening record should now be attached to the Business
      refute_equal business.reload.trade_screening_record, trade_screening_record.reload
      assert_equal organization.reload.trade_screening_record, trade_screening_record  # Trade screening record remains attached to the Organization
      assert_equal organization.reload.billing_contact, billing_contact
      refute_equal business.id, trade_screening_record.owner_id
      assert_equal standard_owner.id, trade_screening_record.owner_id
      assert_predicate trade_screening_record, :no_hit?
      assert_equal organization.trade_screening_record.external_uuid, trade_screening_record.external_uuid
    end
  end
end
