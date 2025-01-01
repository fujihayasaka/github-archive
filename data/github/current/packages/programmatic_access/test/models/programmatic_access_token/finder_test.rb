# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/authnd_client_helpers"

class ProgrammaticAccessToken::FinderTest < GitHub::TestCase
  include AuthndClientTestHelpers

  fixtures do
    @user = create(:user)
    @pat = create(:user_programmatic_access, owner: @user)
  end

  setup do
    setup_authnd_stub
  end

  teardown do
    remove_authnd_stub
  end

  def described_class
    ::ProgrammaticAccessToken::Finder
  end

  test "returns a success result when credentials are found" do
    stub_authnd_programmatic_access_find_credentials
    result = described_class.perform(@pat)

    assert_predicate result, :success?
    assert_kind_of Array, result.value
    assert_nil result.error
  end

  test "returns a failed result if authnd returns a failed result" do
    stub_authnd_programmatic_access_find_credentials(result: :RESULT_FAILED_INVALID_ATTRIBUTES, error: "attribute 'actor.type' is required")
    result = described_class.perform(@pat)

    assert_predicate result, :failed?
    assert_equal result.error, "attribute 'actor.type' is required"
    assert_nil result.value
  end

  test "returns a failed result if an exception is raised during the process" do
    stub_authnd_programmatic_access_find_credentials(raise_with: Faraday::ClientError.new("error"))
    result = described_class.perform(@pat)

    assert_predicate result, :failed?
    assert_equal result.error, "error"
    assert_nil result.value
  end

  test "returns a success result on stafftools tenant", skip_unless: :multi_tenant_enterprise? do
    stafftools_tenant = create :business, :enterprise_managed, slug: "stafftoolswus2", name: "stafftoolswus2"
    assert_equal stafftools_tenant, GitHub::CurrentTenant.get

    stub_authnd_programmatic_access_find_credentials(tenant: @user.enterprise_managed_business)
    # in the middle of this perform, we switch tenants
    result = described_class.perform(@pat)

    # assert we switched back
    assert_equal stafftools_tenant, GitHub::CurrentTenant.get
    # assert we were successful
    assert_predicate result, :success?
    assert_kind_of Array, result.value
    assert_nil result.error
  end
end
