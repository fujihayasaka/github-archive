# typed: true
# frozen_string_literal: true

require "test_helper"
require "uri"

class WindbeamExportTest < GitHub::TestCase
  setup do
    @user = create(:user)
    @random_user = create(:user)
    @export = WindbeamExport.create(user: @user)
    @sample_azure_url = "windbeamexportsblobstg.blob.core.windows.net/1/participant-1"
  end

  def extract_token_from_url(url)
    T.must(T.must(URI.parse(url).query).split("&").find { |param| param.start_with?("token=") }).split("=").last
  end

  context "validations" do
    test "is valid with valid attributes" do
      assert @export.valid?
    end

    test "is not valid without a user" do
      export = WindbeamExport.new
      refute export.valid?
      assert_includes export.errors.full_messages, "User can't be blank"
    end

    test "is not valid with an invalid state" do
      assert_raises(ArgumentError) do
        WindbeamExport.new(user: @user, state: :invalid_state)
      end
    end
  end

  context "initialization" do
    test "sets default state to pending" do
      new_export = WindbeamExport.new(user: @user)
      assert_equal "pending", new_export.state
    end
  end

  context "scopes" do
    test "newest returns exports ordered by created_at desc" do
      WindbeamExport.where(user: @user).delete_all

      older_export = WindbeamExport.create(user: @user, created_at: 2.days.ago)
      middle_export = WindbeamExport.create(user: @user, created_at: 1.day.ago)
      newer_export = WindbeamExport.create(user: @user, created_at: 1.hour.ago)

      result_ids = WindbeamExport.newest.pluck(:id)
      expected_ids = [newer_export.id, middle_export.id, older_export.id]

      assert_equal expected_ids, result_ids
    end
  end

  context "state transitions" do
    test "start_export changes state to in_progress" do
      @export.start_export
      assert_equal "in_progress", @export.reload.state
    end

    test "complete_export changes state to completed" do
      @export.complete_export
      assert_equal "completed", @export.reload.state
    end

    test "fail_export changes state to failed" do
      @export.fail_export
      assert_equal "failed", @export.reload.state
    end
  end

  context "text fields" do
    test "set_azure_url updates azure_url and azure_url_updated_at" do
      url = "https://azure.com/export.zip"
      freeze_time do
        @export.set_azure_url(url)
        assert_equal url, @export.reload.azure_url
        assert_equal Time.current, @export.azure_url_updated_at
      end
    end

    test "set_request_id updates request_id" do
      request_id = "6ac24fe0-c8cb-4f9b-b24f-6381cbdd6a73"
      @export.set_request_id(request_id)
      assert_equal request_id, @export.reload.request_id
    end
  end

  context "enum behavior" do
    test "allows setting valid states" do
      [:pending, :in_progress, :completed, :failed].each do |state|
        @export.state = state
        assert @export.valid?
      end
    end

    test "raises error for invalid state" do
      assert_raises(ArgumentError) do
        @export.state = :invalid_state
      end
    end
  end

  context "url generation" do
    test "token_to_url returns nil for correct user with bad token" do
      @export.complete_export
      @export.set_azure_url(@sample_azure_url)

      token = @export.user.signed_auth_token \
            scope:   "WindbeamExport",
            expires: @export.created_at - 1.day, #it's expired
            data:    { export_id: @export.id }

      assert_nil WindbeamExport.token_to_url(token.to_s, @user)
    end

    test "token_to_url returns nil for incorrect user with good token" do
      @export.complete_export
      @export.set_azure_url(@sample_azure_url)

      token = @export.user.signed_auth_token \
            scope:   "WindbeamExport",
            expires: @export.created_at + 7.days,
            data:    { export_id: @export.id }

      assert_nil WindbeamExport.token_to_url(token.to_s, @random_user)
    end

    test "token_to_url returns nil for nil azure_url" do
      @export.complete_export
      @export.set_azure_url(nil)

      token = @export.user.signed_auth_token \
            scope:   "WindbeamExport",
            expires: @export.created_at + 7.days,
            data:    { export_id: @export.id }

      assert_nil WindbeamExport.token_to_url(token.to_s, @user)
    end

    test "token_to_url returns azure blob url for correct user with good token" do
      @export.complete_export
      @export.set_azure_url(@sample_azure_url)
      @export.update(azure_url_updated_at: 1.hour.ago)

      token = @export.user.signed_auth_token \
            scope:   "WindbeamExport",
            expires: @export.created_at + 7.days,
            data:    { export_id: @export.id }

      assert_equal @sample_azure_url, WindbeamExport.token_to_url(token.to_s, @user)
    end

    test "token_to_url updates the azure_url and azure_url_updated_at if it expires" do
      @export.complete_export
      @export.set_azure_url(@sample_azure_url)
      @export.update(azure_url_updated_at: 13.hours.ago)

      url = @export.url_with_token
      refute_nil url
      token = extract_token_from_url(url)

      mock_client = mock
      refreshed_url = "windbeamexportsblobstg.blob.core.windows.net/23/participant-23"
      mock_client.stubs(:get_download_url).returns(refreshed_url)
      Dsr.stubs(:windbeam_client).returns(mock_client)

      freeze_time do
        current_time = Time.current
        assert_equal refreshed_url, WindbeamExport.token_to_url(token.to_s, @user)
        @export.reload
        assert_equal refreshed_url, @export.azure_url
        assert_equal current_time, @export.azure_url_updated_at
      end
    end

    test "token_to_url returns nil if windbeam api throws an error" do
      @export.complete_export
      @export.set_azure_url(@sample_azure_url)
      @export.update(azure_url_updated_at: 13.hours.ago)

      url = @export.url_with_token
      refute_nil url
      token = extract_token_from_url(url)

      mock_client = mock
      mock_client.stubs(:get_download_url).raises(WindbeamApi::Errors::CommunicationError)
      Dsr.stubs(:windbeam_client).returns(mock_client)

      assert_nil WindbeamExport.token_to_url(token.to_s, @user)
    end
  end
end
