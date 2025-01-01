# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityConfigurationDefaultTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers

  fixtures do
    @owner = create(:user, name: "org-owner")
    @org = create(:organization, admin: @owner)
  end

  setup do
    @security_config = create(:security_configuration, target: @org)
  end

  context ".create_or_update_defaults" do
    test "does not create a security configuration default when defaults are set to false" do
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration_id: @security_config.id,
      )

      assert_empty SecurityConfigurationDefault.for_organization(@org)
    end

    test "does not create/update defaults when a similar default already exists" do
      default = create(:security_configuration_default, :default_for_new_public_repos, security_configuration: @security_config)

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
      assert_no_changes -> { default.reload } do
        SecurityConfigurationDefault.create_or_update_defaults(
          target: @org,
          default_for_new_public_repos: true,
          default_for_new_private_repos: false,
          security_configuration_id: @security_config.id,
        )
      end
      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
    end

    test "deletes an existing security configuration default when defaults are set to false" do
      create(:security_configuration_default, :default_for_new_public_repos, security_configuration: @security_config)

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count

      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration_id: @security_config.id,
      )

      assert_empty SecurityConfigurationDefault.all
    end

    test "creates a security configuration default for new public repos" do
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: false,
        security_configuration_id: @security_config.id,
      )

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
      config_default = SecurityConfigurationDefault.last
      assert T.must(config_default).default_for_new_public_repos
      refute SecurityConfigurationDefault.default_for_new_private_repos.first
    end

    test "creates a security configuration default for new private & internal repos" do
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: true,
        security_configuration_id: @security_config.id,
      )

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
      config_default = SecurityConfigurationDefault.last
      assert T.must(config_default).default_for_new_private_repos
      refute SecurityConfigurationDefault.default_for_new_public_repos.first
    end

    test "creates a security configuration default for public and private & internal repos" do
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: true,
        security_configuration_id: @security_config.id,
      )

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
      config_default = SecurityConfigurationDefault.last
      assert T.must(config_default).default_for_new_public_repos
      assert T.must(config_default).default_for_new_private_repos
    end

    test "config A is default for new public repos, config B is created as default for new private repos" do
      security_config_default = create(:security_configuration_default, security_configuration: @security_config)

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
      assert security_config_default.default_for_new_public_repos
      refute security_config_default.default_for_new_private_repos

      another_security_config = create(:security_configuration, target: @org)
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: true,
        security_configuration_id: another_security_config.id,
      )

      assert_equal 2, SecurityConfigurationDefault.for_organization(@org).count
      security_config_default.reload
      another_security_config_default = SecurityConfigurationDefault.where(security_configuration: another_security_config).first

      assert security_config_default.default_for_new_public_repos
      refute security_config_default.default_for_new_private_repos

      refute T.must(another_security_config_default).default_for_new_public_repos
      assert T.must(another_security_config_default).default_for_new_private_repos
    end

    test "config A is default for new public repos, config B is created as default for new public repos" do
      security_config_default = create(:security_configuration_default, security_configuration: @security_config)

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
      assert security_config_default.default_for_new_public_repos
      refute security_config_default.default_for_new_private_repos

      another_security_config = create(:security_configuration, target: @org)
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: false,
        security_configuration_id: another_security_config.id,
      )

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
      assert_empty SecurityConfigurationDefault.where(security_configuration: @security_config)

      another_security_config_default = SecurityConfigurationDefault.where(security_configuration: another_security_config).first
      assert T.must(another_security_config_default).default_for_new_public_repos
      refute T.must(another_security_config_default).default_for_new_private_repos
    end

    test "config A is default for new public & private repos, config B is created as default for new public repos" do
      security_config_default = create(
        :security_configuration_default, :default_for_new_public_and_private_repos, security_configuration: @security_config
      )

      assert_equal 1, SecurityConfigurationDefault.count
      assert security_config_default.default_for_new_public_repos
      assert security_config_default.default_for_new_private_repos

      another_security_config = create(:security_configuration, target: @org)
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: false,
        security_configuration_id: another_security_config.id,
      )

      assert_equal 2, SecurityConfigurationDefault.for_organization(@org).count
      security_config_default.reload
      another_security_config_default = SecurityConfigurationDefault.where(security_configuration: another_security_config).first

      refute security_config_default.default_for_new_public_repos
      assert security_config_default.default_for_new_private_repos

      assert T.must(another_security_config_default).default_for_new_public_repos
      refute T.must(another_security_config_default).default_for_new_private_repos
    end

    test "config A is default for new public repos, config B is default for new private repos and config A is updated as default for both" do
      security_config_default = create(:security_configuration_default, security_configuration: @security_config)

      another_security_config = create(:security_configuration, target: @org)
      another_security_config_default = create(
        :security_configuration_default, :default_for_new_private_repos, security_configuration: another_security_config
      )

      assert_equal 2, SecurityConfigurationDefault.for_organization(@org).count
      assert security_config_default.default_for_new_public_repos
      refute security_config_default.default_for_new_private_repos

      refute another_security_config_default.default_for_new_public_repos
      assert another_security_config_default.default_for_new_private_repos

      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: true,
        security_configuration_id: @security_config.id,
      )

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
      assert_empty SecurityConfigurationDefault.where(security_configuration: another_security_config)

      default = SecurityConfigurationDefault.where(security_configuration: @security_config).first
      assert T.must(default).default_for_new_public_repos
      assert T.must(default).default_for_new_private_repos
    end

    test "config A is default for new public & private repos, config B is updated as default for new public & private repos" do
      security_config_default = create(:security_configuration_default, :default_for_new_public_and_private_repos, security_configuration: @security_config)
      another_security_config = create(:security_configuration, target: @org)

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
      assert security_config_default.default_for_new_public_repos
      assert security_config_default.default_for_new_private_repos

      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: true,
        security_configuration_id: another_security_config.id,
      )

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
      assert_empty SecurityConfigurationDefault.where(security_configuration: @security_config)

      default = SecurityConfigurationDefault.where(security_configuration: another_security_config).first
      assert T.must(default).default_for_new_public_repos
      assert T.must(default).default_for_new_private_repos
    end

    test "config A is default for new public & private repos, config A is updated as not a default config" do
      security_config_default = create(:security_configuration_default, :default_for_new_public_and_private_repos, security_configuration: @security_config)

      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count
      assert security_config_default.default_for_new_public_repos
      assert security_config_default.default_for_new_private_repos

      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration_id: @security_config.id,
      )

      assert_empty SecurityConfigurationDefault.where(security_configuration: @security_config)
    end

    test "set the GH config as default for all repos, then change it to default for only public repos", skip_enterprise: true do
      gh_config = T.must(SecurityConfiguration.github_recommended_configuration)
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: true,
        security_configuration_id: T.must(gh_config.id),
      )
      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count

      default = SecurityConfigurationDefault.for_organization(@org).first
      assert T.must(default).default_for_new_public_repos
      assert T.must(default).default_for_new_private_repos

      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org.reload,
        default_for_new_public_repos: true,
        default_for_new_private_repos: false,
        security_configuration_id: T.must(gh_config.id),
      )
      assert_equal 1, SecurityConfigurationDefault.for_organization(@org).count

      default = SecurityConfigurationDefault.for_organization(@org).first
      assert T.must(default).default_for_new_public_repos
      refute T.must(default).default_for_new_private_repos
    end
  end

  context "instrumentation" do
    test "creates an audit log entry when a security configuration default for new public repos is applied" do
      security_config = create(:security_configuration, target: @org)

      events = assert_performed_audit_entries(count: 1, only: "security_configuration_default.update") do
        SecurityConfigurationDefault.create_or_update_defaults(
          target: @org,
          default_for_new_public_repos: true,
          default_for_new_private_repos: false,
          security_configuration_id: security_config.id,
        )
      end

      assert_equal last_performed_audit_entries, events
      expected_payload = {
        target: @org.display_login,
        security_configuration_name: security_config.name,
        default_for_new_public_repos: true,
        default_for_new_private_repos: false,
      }

      assert_subset_hash expected_payload, events.first
    end

    test "creates an audit log entry when a security configuration default for new private and internal repos is applied" do
      security_config = create(:security_configuration, target: @org)

      events = assert_performed_audit_entries(count: 1, only: "security_configuration_default.update") do
        SecurityConfigurationDefault.create_or_update_defaults(
          target: @org,
          default_for_new_public_repos: false,
          default_for_new_private_repos: true,
          security_configuration_id: security_config.id,
        )
      end

      assert_equal last_performed_audit_entries, events
      expected_payload = {
        target: @org.display_login,
        security_configuration_name: security_config.name,
        default_for_new_public_repos: false,
        default_for_new_private_repos: true,
      }

      assert_subset_hash expected_payload, events.first
    end

    test "creates an audit log entry when a security configuration default for all repos is applied" do
      security_config = create(:security_configuration, target: @org)

      events = assert_performed_audit_entries(count: 1, only: "security_configuration_default.update") do
        SecurityConfigurationDefault.create_or_update_defaults(
          target: @org,
          default_for_new_public_repos: true,
          default_for_new_private_repos: true,
          security_configuration_id: security_config.id,
        )
      end

      assert_equal last_performed_audit_entries, events
      expected_payload = {
        target: @org.display_login,
        security_configuration_name: security_config.name,
        default_for_new_public_repos: true,
        default_for_new_private_repos: true,
      }

      assert_subset_hash expected_payload, events.first
    end

    test "creates an audit log entry when security configuration default changed to None" do
      security_config = create(:security_configuration, target: @org)
      create(:security_configuration_default,
        security_configuration: security_config,
        target: @org,
        default_for_new_private_repos: true,
        default_for_new_public_repos: false
      )

      events = assert_performed_audit_entries(count: 1, only: "security_configuration_default.delete") do
        SecurityConfigurationDefault.create_or_update_defaults(
          target: @org,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          security_configuration_id: security_config.id,
        )
      end

      assert_equal last_performed_audit_entries, events
      expected_payload = {
        target: @org.display_login,
        security_configuration_name: security_config.name,
      }

      assert_subset_hash expected_payload, events.first
    end
  end
end
