# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../helpers/advanced_security_skus_base_test"

# The tests in AutoCodeqlTest have complex setups, designed to ensure that everything
# is in a legitimate state for testing the most common scenarios in both bundled and
# unbundled SKU modes where necessary.
#
# Some tests involve testing enablement behaviour outside of the "happy path"
# scenario, and thus require a cut-down setup. Those tests are in this file.
class AutoCodeqlBasicTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @org = create :organization, admin: @user
    @private_repo = create(:private_repository, :minimal, id: 2, owner: @org)
  end

  context "enable/disable/update Auto CodeQL" do
    # Note that calling `AutoCodeql`'s `on_enable` method might well succeed even with
    # configuration that wouldn't permit it. However, that's because `on_enable` is the
    # implementation detail and the checking happens in the `ServiceManager`. Hence we
    # test enabling AutoCodeQL via the Service Manager in this test and those below.
    test "AutoCodeQL can't be enabled if the org uses unbundled GHAS and only Secret Protection has been purchased" do
      @org.mark_secret_protection_as_purchased_for_entity_as_volume(actor: @user)
      GitHub::Enterprise.license.stubs(:secret_protection_enabled).returns(true) if GitHub.enterprise?

      service_manager = SecurityProduct::ServiceManager.new(@private_repo)
      service_manager.toggle_services(@user, services_to_enable: [[:code_security, { force?: true }]])

      assert_equal :code_security_disabled, service_manager.toggle_services(@user, services_to_enable: [:auto_codeql]).error
    end

    # These states should be incompatible, but are worth testing
    test "AutoCodeQL can't be enabled if the org uses unbundled GHAS but somehow the (bundled) GHAS service is enabled instead of Code Security" do
      @org.set_customer_to_split_metered_offering(actor: @user)
      # In the previous test, we didn't need to stub `advanced_security_products_bundled?`;
      # it already returned the right value since Secret Protection was purchased.
      # In this test we're deliberately not having either product purchased but nonetheless
      # want to test in unbundled mode, hence stubbing.
      @private_repo.stubs(:advanced_security_products_bundled?).returns(false) if GitHub.enterprise?

      service_manager = SecurityProduct::ServiceManager.new(@private_repo)
      service_manager.toggle_services(@user, services_to_enable: [[:advanced_security, { force?: true }]])
      GitHub.stubs(:code_scanning_enabled?).returns(true) if GitHub.enterprise?

      assert_equal :code_security_disabled, service_manager.toggle_services(@user, services_to_enable: [:auto_codeql]).error
    end

    # Likewise, these states should also be incompatible, but are also worth testing
    test "AutoCodeQL can't be enabled if org has bundled GHAS and somehow Code Security is enabled rather than GHAS" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)

      service_manager = SecurityProduct::ServiceManager.new(@private_repo)
      service_manager.toggle_services(@user, services_to_enable: [[:code_security, { force?: true }]])
      service_manager.toggle_services(@user, services_to_disable: [[:advanced_security, { force?: true }]])
      GitHub.stubs(:code_scanning_enabled?).returns(true) if GitHub.enterprise?

      assert_equal :advanced_security_disabled, service_manager.toggle_services(@user, services_to_enable: [:auto_codeql]).error
    end
  end
end
