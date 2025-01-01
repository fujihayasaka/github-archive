# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeSecurity::Features::AdvancedSecurityHelperTest < GitHub::TestCase

  fixtures do
    @org = create(:organization)
    @private_repo = create(:private_repository, owner: @org)
  end

  test "code security is available by default for public repos for non enterprise repos", skip_enterprise: true do
    repository = create(:public_repository, owner: @org)

    # Code Security settings should show for public repos
    assert CodeSecurity::Features::AdvancedSecurityHelper.code_security_should_show_in_settings?(repository:)
    # But it cannot be configured
    refute CodeSecurity::Features::AdvancedSecurityHelper.code_security_configurable?(repository:)
  end

  test "not available for private repos when not purchased" do
    repository = create(:private_repository, owner: @org)

    refute CodeSecurity::Features::AdvancedSecurityHelper.code_security_should_show_in_settings?(repository:)
    refute CodeSecurity::Features::AdvancedSecurityHelper.code_security_configurable?(repository:)
  end

  test "available for private repos when purchased" do
    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:code_security_enabled).returns(true)
    else
      @org.set_customer_to_split_metered_offering(actor: User.ghost)
    end
    repository = create(:private_repository, owner: @org)

    assert CodeSecurity::Features::AdvancedSecurityHelper.code_security_should_show_in_settings?(repository:)
    assert CodeSecurity::Features::AdvancedSecurityHelper.code_security_configurable?(repository:)
  end

  test "not available for user owned private repos" do
    repository = create(:private_repository, owner: User.ghost)

    refute CodeSecurity::Features::AdvancedSecurityHelper.code_security_should_show_in_settings?(repository:)
    refute CodeSecurity::Features::AdvancedSecurityHelper.code_security_configurable?(repository:)
  end
end
