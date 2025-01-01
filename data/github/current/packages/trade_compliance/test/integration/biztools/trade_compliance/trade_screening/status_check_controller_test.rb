# typed: true
# frozen_string_literal: true

require "test_helper"

class Biztools::TradeCompliance::TradeScreening::StatusCheckControllerTest < GitHub::IntegrationTestCase
  skip_unless :billing_enabled?

  fixtures do
    @staffer = create(:staff_admin_user)
    @user = create(:user)
    @business = create(:business)
    @user_trade_screening_record = create(:account_screening_profile, :not_screened, owner: @user)
    @business_trade_screening_record = create(:account_screening_profile, :not_screened, :with_business, owner: @business)
  end

  setup do
    GitHub.flipper[:live_sdn_screening].enable
  end

  def entity_identifier(entity)
    entity.is_a?(User) ? entity.display_login : entity.slug
  end

  def json_response
    JSON.parse(response.body)
  end

  def perform_status_check_test(entity:, param_name:, screening_record:)
    [false, true].each do |screened|
      if screened
        screening_record.no_hit!
      end

      as @staffer
      get "/biztools/trade_screening/status_check/#{param_name}/#{entity_identifier(entity)}", xhr: true

      assert_response :success
      assert_equal screened, json_response["screened"], "Expected screened to be #{screened} for #{entity.class.name}"
    end
  end

  test "status check for user by user_id" do
    perform_status_check_test(
      entity: @user,
      param_name: :by_user_id,
      screening_record: @user_trade_screening_record
    )
  end

  test "status check for business by slug" do
    perform_status_check_test(
      entity: @business,
      param_name: :by_slug,
      screening_record: @business_trade_screening_record
    )
  end
end
