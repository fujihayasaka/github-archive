# typed: true
# frozen_string_literal: true

require "test_helper"

class PrivateRegistry::ConfigurationTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
  end

  test "can create a private registry configuration" do
    config = create(:private_registry_configuration)

    assert config
  end

  context "for_organization" do
    test "gets all relevant configurations for the given org" do
      2.times { create(:private_registry_configuration, owner_id: @org.id, owner_type: "Organization") }

      other_org = create(:organization)
      2.times { create(:private_registry_configuration, owner_id: other_org.id, owner_type: "Organization") }

      configs = PrivateRegistry::Configuration.for_organization(@org)

      assert_equal 2, configs.count
      configs.each { |config| assert_equal @org, config.owner }
    end

    test "does not change the query result if not given an org" do
      4.times { create(:private_registry_configuration) }

      assert_equal 4, PrivateRegistry::Configuration.for_organization(nil).count
    end
  end
end
