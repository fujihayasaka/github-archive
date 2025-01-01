# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class EnterpriseInstallationCreatorTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @org   = create(:organization, login: "ACME", admin: @admin)

    @business = create :business, organizations: [@org], owners: [@admin]

    license = File.read("#{Rails.root}/test/fixtures/github-enterprise-utf8.ghl")
    @license_hash = Digest::SHA256.base64digest(license)
    @server_id = SecureRandom.uuid
    @data = {
      "license_hash" => @license_hash,
      "license_public_key" => "key",
      "customer_name" => "example_company",
      "host_name" => "github.example.com",
      "http_only" => false,
      "version" => "2.17",
      "server_id" => @server_id,
    }
  end

  test "returns an EnterpriseInstallation for a valid operation on an organization" do
    result = EnterpriseInstallation::Creator.perform(@org, actor: @admin, server_data: @data, entry_point: :test_case)
    assert_predicate result, :success?
    assert result.enterprise_installation
    assert_equal @org, result.enterprise_installation.owner
    assert result.enterprise_installation.github_app
    assert_equal @org, result.enterprise_installation.github_app.owner
    assert result.enterprise_installation.integration_installation
  end

  test "returns an EnterpriseInstallation for a valid operation on an enterprise" do
    result = EnterpriseInstallation::Creator.perform(@business, actor: @admin, server_data: @data, entry_point: :test_case)
    assert_predicate result, :success?
    assert result.enterprise_installation
    assert_equal @business, result.enterprise_installation.owner
    assert result.enterprise_installation.github_app
    assert_equal @business, result.enterprise_installation.github_app.owner
    assert result.enterprise_installation.integration_installation
  end

  test "returns a failure when enterprise installation data is invalid" do
    result = assert_no_difference ["EnterpriseInstallation.count", "Integration.count", "IntegrationInstallation.count"] do
      EnterpriseInstallation::Creator.perform(@business, actor: @admin, server_data: {}, entry_point: :test_case)
    end

    assert_predicate result, :failed?
    assert_nil result.enterprise_installation
    refute_nil result.error
  end

  test "returns a failure when app cannot be created" do
    failed_integration = build :integration
    failed_integration.errors.add(:base, "failed in test")
    EnterpriseInstallation.any_instance.stubs(:create_integration!).raises(ActiveRecord::RecordInvalid.new(failed_integration))
    result = assert_no_difference ["EnterpriseInstallation.count", "Integration.count", "IntegrationInstallation.count"] do
      EnterpriseInstallation::Creator.perform(@business, actor: @admin, server_data: @data, entry_point: :test_case)
    end

    assert_predicate result, :failed?
    assert_nil result.enterprise_installation
    assert_equal failed_integration.errors.full_messages.to_sentence, result.error
  end

  test "returns a failure when app installation cannot be created" do
    IntegrationInstallation::Creator.stubs(:perform).returns(IntegrationInstallation::Creator::Result.failed("error"))
    result = assert_no_difference ["EnterpriseInstallation.count", "Integration.count", "IntegrationInstallation.count"] do
      EnterpriseInstallation::Creator.perform(@business, actor: @admin, server_data: @data, entry_point: :test_case)
    end

    assert_predicate result, :failed?
    assert_nil result.enterprise_installation
    assert_match /Failed to install .+? on .+?/, result.error
  end

  test "returns a failure when actor is not allowed to create EnterpriseInstallations" do
    random_user = create :user
    result = assert_no_difference ["EnterpriseInstallation.count", "Integration.count", "IntegrationInstallation.count"] do
      EnterpriseInstallation::Creator.perform(@business, actor: random_user, server_data: @data, entry_point: :test_case)
    end

    assert_predicate result, :failed?
    assert_nil result.enterprise_installation
    assert_equal "Actor does not have permissions to create an EnterpriseInstallation on #{@business.name}",
                 result.error
  end

  test "returns a failure for anonymous users" do
    result = assert_no_difference ["EnterpriseInstallation.count", "Integration.count", "IntegrationInstallation.count"] do
      EnterpriseInstallation::Creator.perform(@business, actor: nil, server_data: @data, entry_point: :test_case)
    end

    assert_predicate result, :failed?
    assert_nil result.enterprise_installation
    assert_equal "Actor does not have permissions to create an EnterpriseInstallation on #{@business.name}",
                 result.error
  end

  test "logs general failures on Splunk" do
    Failbot.expects(:report).with(instance_of(EnterpriseInstallation::Creator::Result::Error))
    EnterpriseInstallation::Creator.perform(@business, actor: nil, server_data: @data, entry_point: :test_case)
  end

  test "logs ActiveRecord failures on Splunk" do
    Failbot.expects(:report).with(instance_of(ActiveRecord::RecordInvalid))
    failed_integration = build :integration
    failed_integration.errors.add(:base, "failed in test")
    EnterpriseInstallation.any_instance.stubs(:create_integration!).raises(ActiveRecord::RecordInvalid.new(failed_integration))
    EnterpriseInstallation::Creator.perform(@business, actor: @admin, server_data: @data, entry_point: :test_case)
  end
end
