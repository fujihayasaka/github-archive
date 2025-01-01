# typed: true
# frozen_string_literal: true

require "test_helper"

class BlankslatePayloadBuilderTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)

    @blankslate_payload_builder = SecretScanning::Models::React::BlankslatePayloadBuilder.new(@repo, @user).freeze
  end

  test "builds disabled blankslate payload for admin" do
    Repository.any_instance.stubs(:adminable_by?).returns(true)
    actual_payload = @blankslate_payload_builder.blankslate_payload(SecretScanning::Models::React::BlankslateType::Disabled)

    assert_equal "disabled", actual_payload[:blankslate_type]
    assert_equal @repo.name, actual_payload[:repository][:name]
    assert_equal @repo.owner_display_login, actual_payload[:repository][:owner_display_login]
    assert_equal true, actual_payload[:adminable]
    assert_equal GitHub.help_url, actual_payload[:help_url]
  end

  test "builds loading failed blankslate payload" do
    actual_payload = @blankslate_payload_builder.blankslate_payload(SecretScanning::Models::React::BlankslateType::LoadingFailed)

    assert_equal "loadingfailed", actual_payload[:blankslate_type]
    assert_equal @repo.name, actual_payload[:repository][:name]
    assert_equal @repo.owner_display_login, actual_payload[:repository][:owner_display_login]
    assert_equal GitHub.help_url, actual_payload[:help_url]

    if GitHub.enterprise?
      assert_equal UrlHelpers.contact_path, actual_payload[:enterprise_contact_path] #/contact
    end
  end
end
