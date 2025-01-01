# typed: strict
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  module TradeScreeningTestHelpers
    extend T::Helpers

    abstract!

    requires_ancestor { GitHub::BasicTestCase }

    sig { returns(LiveResponse) }
    def build_empty_live_response
      LiveResponse.new(eid: "", external_uuid: "", status: "")
    end

    sig { params(screening_profile: AccountScreeningProfile).returns(ScreeningDetails) }
    def build_screening_request(screening_profile:)
      screening_details = screening_profile.screening_details
      contacts = screening_profile.owner_contacts
      contacts.each { |c| screening_details.add_customer_details(details: c.customer_details) } if contacts.any?

      screening_details
    end

    sig { params(screening_profile: AccountScreeningProfile, status: String).returns(LiveResponse) }
    def build_screening_response(screening_profile:, status:)
      screening_request = build_screening_request(screening_profile: screening_profile)
      request_body = screening_request.to_hash
      LiveResponse.parse(response: {
        ScrRespEnv: {
          EId: request_body[:ScrReqsEnv][:EId],
          DT: request_body[:ScrReqsEnv][:DT],
          SummResult: status,
          ScrResps: {
            ScrResp: [
              {
                ReqID: "IndName_IndAddr",
                ExternalRefID: request_body[:ScrReqsEnv][:ExternalRefID],
                Result: status,
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
    end

    sig { params(expected: T.nilable(CustomerDetails), actual: T.nilable(CustomerDetails)).void }
    def assert_customer_details_equal(expected, actual)
      assert_nil actual if expected.nil?
      refute_nil actual if expected.present?
      return if expected.nil? && actual.nil?

      assert_equal expected.instance_variables.size, actual.instance_variables.size
      expected.instance_variables.each do |attr|
        expected_value = expected.instance_variable_get(attr)
        actual_value = actual.instance_variable_get(attr)
        assert_nil actual_value if expected_value.nil?
        refute_nil actual_value if expected_value.present?
        next if expected_value.nil? && actual_value.nil?

        assert_equal expected_value, actual_value
      end
    end

    sig { params(expected: T.nilable(ScreeningDetails), actual: T.nilable(ScreeningDetails)).void }
    def assert_screening_details_equal(expected, actual)
      assert_nil actual if expected.nil?
      refute_nil actual if expected.present?
      return if expected.nil? && actual.nil?

      assert_equal expected.instance_variables.size, actual.instance_variables.size
      expected.instance_variables.each do |attr|
        expected_value = expected.instance_variable_get(attr)
        actual_value = actual.instance_variable_get(attr)
        assert_nil actual_value if expected_value.nil?
        refute_nil actual_value if expected_value.present?
        next if expected_value.nil? && actual_value.nil?

        if expected_value.is_a?(Array)
          assert_equal expected_value.size, actual_value.size
          next unless expected_value.first.is_a?(CustomerDetails)

          expected_value = T.let(expected_value, T::Array[CustomerDetails])
          actual_value = T.let(expected_value, T::Array[CustomerDetails])
          expected_value = expected_value.sort { |a, b| T.must(a.id.to_s <=> b.id.to_s) }
          actual_value = actual_value.sort { |a, b| T.must(a.id.to_s <=> b.id.to_s) }

          expected_value.each_with_index { |expected_customer_detail, index| assert_customer_details_equal(expected_customer_detail, actual_value[index]) }
          next
        end

        assert_equal expected_value, actual_value
      end
    end

    sig { params(status: String).returns(String) }
    def screening_status_description(status)
      if status == "hit_in_review"
        TradeControls::Notices.trade_screening_customer_account_under_review_for_less_than_2_days
      elsif status == "ingestion_error"
        TradeControls::Notices.trade_screening_customer_account_ingestion_error
      elsif status == "data_issue"
        TradeControls::Notices.trade_screening_customer_account_data_issue_other_error
      elsif status == "spammy"
        TradeControls::Notices.trade_screening_account_spammy
      else
        TradeControls::Notices.trade_screening_customer_account_permanently_blocked_after_review
      end
    end

    sig { returns(String) }
    def trade_screening_status_banner_selector
      "react-partial[partial-name='trade-screening-status-banner']"
    end

    sig { params(target: Billing::Types::Account).returns(Symbol) }
    def trade_screening_notice(target:)
      notice = if target.trade_screening_record.is_true_match_restricted?
        :trade_screening_true_match_notice
      else
        :trade_screening_generic_notice
      end
    end
  end
end
