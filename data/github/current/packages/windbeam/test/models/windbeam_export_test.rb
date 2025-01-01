# typed: true
# frozen_string_literal: true

require "test_helper"

class WindbeamExportTest < GitHub::TestCase
  setup do
    @user = create(:user)
    @export = WindbeamExport.create(user: @user)
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
end
