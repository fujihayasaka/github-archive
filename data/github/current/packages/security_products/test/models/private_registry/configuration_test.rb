# typed: true
# frozen_string_literal: true

require "test_helper"

class PrivateRegistry::ConfigurationTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @org = create(:organization)
  end

  test "can create a private registry configuration" do
    config = create(:private_registry_configuration)

    assert config
  end

  context ".for_organization" do
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

  context "#authenticates_with_username_and_password?" do
    %w(maven_repository).each do |registry_type|
      test "returns true when registry_type is #{registry_type}" do
        config = build(:private_registry_configuration, registry_type: registry_type)
        assert config.authenticates_with_username_and_password?
      end
    end

    test "returns false when registry_type is missing or unsupported" do
      config = build(:private_registry_configuration, registry_type: nil)
      refute config.authenticates_with_username_and_password?
    end
  end

  context "metrics" do
    test "records create metric" do
      config = build(
        :private_registry_configuration,
        owner_id: @org.id,
        owner_type: "Organization",
        registry_type: "maven_repository",
      )

      config.save!

      assert_dogstats_increment(1, "private_registry_configuration.create", tags: [
        "owner_type:Organization",
        "registry_type:maven_repository",
      ])
    end

    test "records update metric with tags for attributes of interest that changed" do
      config = create(
        :private_registry_configuration,
        owner_id: @org.id,
        owner_type: "Organization",
        registry_type: "maven_repository",
        url: "https://maven.pkg.github.com/test-org/repo1",
        username: "wrong-username",
      )

      config.update!(url: "https://maven.pkg.github.com/test-org/*")

      assert_dogstats_increment(1, "private_registry_configuration.update", tags: [
        "owner_type:Organization",
        "registry_type:maven_repository",
        "url_changed:true",
        "username_changed:false",
      ])

      config.update!(url: "https://maven.pkg.github.com/test-org/", username: "correct-username")

      assert_dogstats_increment(1, "private_registry_configuration.update", tags: [
        "owner_type:Organization",
        "registry_type:maven_repository",
        "url_changed:true",
        "username_changed:true",
      ])
    end

    test "records delete metric" do
      config = create(
        :private_registry_configuration,
        owner_id: @org.id,
        owner_type: "Organization",
        registry_type: "maven_repository",
      )

      config.destroy!

      assert_dogstats_increment(1, "private_registry_configuration.delete", tags: [
        "owner_type:Organization",
        "registry_type:maven_repository",
      ])
    end
  end
end
