# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityConfigurationDefaultTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers

  fixtures do
    @owner = create(:user, name: "org-owner")
    @org = create(:organization, admin: @owner)

    @business = create(:global_business) || create(:business, owners: [@owner])
    @business_org = create(:business_plus_organization, business: @business, admin: @owner)
  end

  setup do
    GitHub.flipper[:enterprise_security_configurations].enable
    @security_config = create(:security_configuration, target: @org)
    @enterprise_security_config = create(:security_configuration, target: @business)
  end

  context ".create_or_update_defaults" do
    test "does not create a security configuration default for org-owned config when defaults are set to false" do
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration: @security_config,
      )

      assert_empty SecurityConfigurationDefault.for_target(@org)
    end

    test "creates a security configuration default for enterprise-owned config when defaults are set to false" do
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration: @enterprise_security_config,
      )

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
    end

    test "keeps an ELC default override when setting OLC as default" do
      # Create an enterprise-level default config for all repos:
      biz_default = create(:security_configuration_default,
        :default_for_new_public_and_private_repos,
        target: @business,
        security_configuration: @enterprise_security_config
      )

      # Override the ELC default for the org:
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration: @enterprise_security_config,
      )
      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count

      # Set an org-level config as default:
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: false,
        security_configuration: @security_config,
      )
      assert_equal 2, SecurityConfigurationDefault.for_target(@org).count

      # Ensure that the biz-level config is still set to false:
      elc_override = T.must(SecurityConfigurationDefault.find_by(target: @org, security_configuration: @enterprise_security_config))
      refute elc_override.default_for_new_public_repos
      refute elc_override.default_for_new_private_repos

      # Ensure the new default is correct:
      org_default = T.must(SecurityConfigurationDefault.find_by(target: @org, security_configuration: @security_config))
      assert org_default.default_for_new_public_repos
      refute org_default.default_for_new_private_repos

      # Ensure that the IDs returned match our expectations:
      assert_equal({
        default_for_new_public_repos: @security_config.id,
        default_for_new_private_repos: nil,
      }, SecurityConfigurationDefault.default_security_configuration_ids_for(@org))
    end

    test "removes a stale ELC override when replaced" do
      # Create an enterprise-level default config for all repos:
      biz_default = create(:security_configuration_default,
        :default_for_new_public_and_private_repos,
        target: @business,
        security_configuration: @enterprise_security_config
      )

      # Override the ELC default for the org:
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration: @enterprise_security_config,
      )
      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count

      # And then change our minds and set an org-level config as default for the org:
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: true,
        security_configuration: @security_config,
      )
      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count

      default = SecurityConfigurationDefault.for_target(@org).sole
      assert_equal @security_config.id, default.security_configuration_id
      assert default.default_for_new_public_repos
      assert default.default_for_new_private_repos
    end

    test "persists an ELC override when setting another config as default for only one type of repo" do
      biz_default = create(:security_configuration_default,
        :default_for_new_public_and_private_repos,
        target: @business,
        security_configuration: @enterprise_security_config
      )

      # Override the ELC default for the org, making it default for public only:
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: false,
        security_configuration: @enterprise_security_config,
      )
      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count

      # Set an org level config as default for private:
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: true,
        security_configuration: @security_config,
      )
      assert_equal 2, SecurityConfigurationDefault.for_target(@org).count

      # Ensure that the IDs match what we set:
      assert_equal({
        default_for_new_public_repos: @enterprise_security_config.id,
        default_for_new_private_repos: @security_config.id,
      }, SecurityConfigurationDefault.default_security_configuration_ids_for(@org))
    end

    test "does not create/update defaults when a similar default already exists" do
      default = create(:security_configuration_default, :default_for_new_public_repos, security_configuration: @security_config)

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
      assert_no_changes -> { default.reload } do
        SecurityConfigurationDefault.create_or_update_defaults(
          target: @org,
          default_for_new_public_repos: true,
          default_for_new_private_repos: false,
          security_configuration: @security_config,
        )
      end
      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
    end

    test "deletes an existing security configuration default when defaults are set to false" do
      create(:security_configuration_default, :default_for_new_public_repos, security_configuration: @security_config)

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count

      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration: @security_config,
      )

      assert_empty SecurityConfigurationDefault.all
    end

    test "creates a security configuration default for new public repos" do
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: false,
        security_configuration: @security_config,
      )

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
      config_default = SecurityConfigurationDefault.last
      assert T.must(config_default).default_for_new_public_repos
      refute SecurityConfigurationDefault.default_for_new_private_repos.first
    end

    test "creates a security configuration default for new private & internal repos" do
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: true,
        security_configuration: @security_config,
      )

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
      config_default = SecurityConfigurationDefault.last
      assert T.must(config_default).default_for_new_private_repos
      refute SecurityConfigurationDefault.default_for_new_public_repos.first
    end

    test "creates a security configuration default for public and private & internal repos" do
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: true,
        security_configuration: @security_config,
      )

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
      config_default = SecurityConfigurationDefault.last
      assert T.must(config_default).default_for_new_public_repos
      assert T.must(config_default).default_for_new_private_repos
    end

    test "config A is default for new public repos, config B is created as default for new private repos" do
      security_config_default = create(:security_configuration_default, security_configuration: @security_config)

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
      assert security_config_default.default_for_new_public_repos
      refute security_config_default.default_for_new_private_repos

      another_security_config = create(:security_configuration, target: @org)
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: true,
        security_configuration: another_security_config,
      )

      assert_equal 2, SecurityConfigurationDefault.for_target(@org).count
      security_config_default.reload
      another_security_config_default = SecurityConfigurationDefault.where(security_configuration: another_security_config).first

      assert security_config_default.default_for_new_public_repos
      refute security_config_default.default_for_new_private_repos

      refute T.must(another_security_config_default).default_for_new_public_repos
      assert T.must(another_security_config_default).default_for_new_private_repos
    end

    test "config A is default for new public repos, config B is created as default for new public repos" do
      security_config_default = create(:security_configuration_default, security_configuration: @security_config)

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
      assert security_config_default.default_for_new_public_repos
      refute security_config_default.default_for_new_private_repos

      another_security_config = create(:security_configuration, target: @org)
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: false,
        security_configuration: another_security_config,
      )

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
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
        security_configuration: another_security_config,
      )

      assert_equal 2, SecurityConfigurationDefault.for_target(@org).count
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

      assert_equal 2, SecurityConfigurationDefault.for_target(@org).count
      assert security_config_default.default_for_new_public_repos
      refute security_config_default.default_for_new_private_repos

      refute another_security_config_default.default_for_new_public_repos
      assert another_security_config_default.default_for_new_private_repos

      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: true,
        security_configuration: @security_config,
      )

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
      assert_empty SecurityConfigurationDefault.where(security_configuration: another_security_config)

      default = SecurityConfigurationDefault.where(security_configuration: @security_config).first
      assert T.must(default).default_for_new_public_repos
      assert T.must(default).default_for_new_private_repos
    end

    test "config A is default for new public & private repos, config B is updated as default for new public & private repos" do
      security_config_default = create(:security_configuration_default, :default_for_new_public_and_private_repos, security_configuration: @security_config)
      another_security_config = create(:security_configuration, target: @org)

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
      assert security_config_default.default_for_new_public_repos
      assert security_config_default.default_for_new_private_repos

      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: true,
        security_configuration: another_security_config,
      )

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
      assert_empty SecurityConfigurationDefault.where(security_configuration: @security_config)

      default = SecurityConfigurationDefault.where(security_configuration: another_security_config).first
      assert T.must(default).default_for_new_public_repos
      assert T.must(default).default_for_new_private_repos
    end

    test "config A is default for new public & private repos, config A is updated as not a default config" do
      security_config_default = create(:security_configuration_default, :default_for_new_public_and_private_repos, security_configuration: @security_config)

      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count
      assert security_config_default.default_for_new_public_repos
      assert security_config_default.default_for_new_private_repos

      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration: @security_config,
      )

      assert_empty SecurityConfigurationDefault.where(security_configuration: @security_config)
    end

    test "set the GH config as default for all repos, then change it to default for only public repos", skip_enterprise: true do
      gh_config = T.must(SecurityConfiguration.github_recommended_configuration)
      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org,
        default_for_new_public_repos: true,
        default_for_new_private_repos: true,
        security_configuration: gh_config,
      )
      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count

      default = SecurityConfigurationDefault.for_target(@org).first
      assert T.must(default).default_for_new_public_repos
      assert T.must(default).default_for_new_private_repos

      SecurityConfigurationDefault.create_or_update_defaults(
        target: @org.reload,
        default_for_new_public_repos: true,
        default_for_new_private_repos: false,
        security_configuration: gh_config,
      )
      assert_equal 1, SecurityConfigurationDefault.for_target(@org).count

      default = SecurityConfigurationDefault.for_target(@org).first
      assert T.must(default).default_for_new_public_repos
      refute T.must(default).default_for_new_private_repos
    end
  end

  context ".find_for" do
    test "returns a Business default when supplied with a Business target" do
      default = create(:security_configuration_default, :default_for_new_public_repos, target: @business)
      result = SecurityConfigurationDefault.find_for(target: @business, visibility: :public)

      assert_equal default, result.first
    end

    test "returns an org default when supplied with an org that is not owned by an enterprise" do
      assert_nil @org.business
      default = create(:security_configuration_default, :default_for_new_public_repos, target: @org)
      result = SecurityConfigurationDefault.find_for(target: @org, visibility: :public)

      assert_equal default, result.first
    end

    test "returns enterprise default for an enterprise org business without an org default" do
      assert_equal @business, @business_org.business
      assert_nil SecurityConfigurationDefault.find_by(target: @business_org)

      business_default = create(:security_configuration_default, :default_for_new_public_repos, target: @business)
      result = SecurityConfigurationDefault.find_for(target: @business_org, visibility: :public)

      assert_equal business_default, result.first
    end

    test "returns org default for a enterprise org with an org default" do
      assert_equal @business, @business_org.business

      # Ensure there's a enterprise-level default:
      assert create(:security_configuration_default, :default_for_new_public_repos, target: @business)

      org_default = create(:security_configuration_default, :default_for_new_public_repos, target: @business_org)
      result = SecurityConfigurationDefault.find_for(target: @business_org, visibility: :public)

      assert_equal org_default, result.first
    end

    # This test can be removed when we remove the feature flag.
    # We are skipping enterprise since ELC is always enabled on enterprise
    test "with the enterprise configs flag disabled, return org default for an enterprise org with an enterprise default", skip_enterprise: true do
      GitHub.flipper[:enterprise_security_configurations].disable
      assert_equal @business, @business_org.business

      # Ensure there's a enterprise-level default:
      assert create(:security_configuration_default, :default_for_new_public_repos, target: @business)

      org_default = create(:security_configuration_default, :default_for_new_public_repos, target: @business_org)
      result = SecurityConfigurationDefault.find_for(target: @business_org, visibility: :public).first

      assert_equal org_default, result
    end

    # This test can be removed when we remove the feature flag.
    # We are skipping enterprise since ELC is always enabled on enterprise
    test "with the enterprise configs flag disabled, return nil for an enterprise org with an enterprise default", skip_enterprise: true do
      GitHub.flipper[:enterprise_security_configurations].disable
      assert_equal @business, @business_org.business

      # Ensure there's an enterprise-level default:
      assert create(:security_configuration_default, :default_for_new_public_repos, target: @business)

      result = SecurityConfigurationDefault.find_for(target: @business_org, visibility: :public)
      assert_nil result.first
    end

    test "returns nil when an enterprise default is overridden by an org" do
      assert_equal @business, @business_org.business

      # Create an enterprise-level default config for all repos:
      biz_default = create(:security_configuration_default, :default_for_new_public_and_private_repos, target: @business)

      # Override the ELC default for the org:
      create(:security_configuration_default,
        target: @business_org,
        security_configuration: biz_default.security_configuration,
        default_for_new_private_repos: false,
        default_for_new_public_repos: false
      )

      result = SecurityConfigurationDefault.find_for(target: @business_org, visibility: :public)
      assert_empty result
    end
  end

  context ".default_security_configuration_ids_for" do
    test "supports no defaults" do
      assert SecurityConfigurationDefault.where(target: @org).destroy_all
      assert_equal(
        { default_for_new_public_repos: nil, default_for_new_private_repos: nil },
        SecurityConfigurationDefault.default_security_configuration_ids_for(@org)
      )
    end

    test "supports returning enterprise defaults for a Business owner" do
      biz_default = create(:security_configuration_default, :default_for_new_public_repos, target: @business)

      expected_output = {
        default_for_new_public_repos: biz_default.security_configuration_id,
        default_for_new_private_repos: nil,
      }
      assert_equal expected_output, SecurityConfigurationDefault.default_security_configuration_ids_for(@business)
    end

    test "supports only org level defaults" do
      default_for_public = create(:security_configuration_default, :default_for_new_public_repos, target: @business_org)
      default_for_private = create(:security_configuration_default, :default_for_new_private_repos, target: @business_org)

      expected_output = {
        default_for_new_public_repos: default_for_public.security_configuration_id,
        default_for_new_private_repos: default_for_private.security_configuration_id
      }
      assert_equal expected_output, SecurityConfigurationDefault.default_security_configuration_ids_for(@business_org)
    end

    test "supports only enterprise level defaults" do
      default = create(:security_configuration_default, :default_for_new_public_and_private_repos, target: @business)

      expected_output = {
        default_for_new_public_repos: default.security_configuration_id,
        default_for_new_private_repos: default.security_configuration_id
      }
      assert_equal expected_output, SecurityConfigurationDefault.default_security_configuration_ids_for(@business_org)
    end

    test "supports combining org and enterprise level defaults" do
      org_default_for_private = create(:security_configuration_default, :default_for_new_private_repos, target: @business_org)
      assert_equal 1, SecurityConfigurationDefault.where(target: @business_org).count

      biz_default_for_public = create(:security_configuration_default, :default_for_new_public_repos, target: @business)

      expected_output = {
        default_for_new_public_repos: biz_default_for_public.security_configuration_id,
        default_for_new_private_repos: org_default_for_private.security_configuration_id
      }
      assert_equal expected_output, SecurityConfigurationDefault.default_security_configuration_ids_for(@business_org)
    end

    # Scenario 1: the org & enterprise have two default records each, representing different public/private defaults.
    test "org defaults supersede enterprise level defaults when both are present (scenario 1)" do
      org_default_for_public = create(:security_configuration_default, :default_for_new_public_repos, target: @business_org)
      org_default_for_private = create(:security_configuration_default, :default_for_new_private_repos, target: @business_org)

      # Create enterprise-level defaults:
      create(:security_configuration_default, :default_for_new_public_repos, target: @business)
      create(:security_configuration_default, :default_for_new_private_repos, target: @business)

      expected_output = {
        default_for_new_public_repos: org_default_for_public.security_configuration_id,
        default_for_new_private_repos: org_default_for_private.security_configuration_id,
      }
      assert_equal expected_output, SecurityConfigurationDefault.default_security_configuration_ids_for(@business_org)
    end

    # Scenario 2: the org has 2 default records (one each for public/private), the enterprise has 1 (both public & private)
    test "org defaults supersede enterprise level defaults when both are present (scenario 2)" do
      org_default_for_public = create(:security_configuration_default, :default_for_new_public_repos, target: @business_org)
      org_default_for_private = create(:security_configuration_default, :default_for_new_private_repos, target: @business_org)

      # Create enterprise-level defaults:
      create(:security_configuration_default, :default_for_new_public_and_private_repos, target: @business)

      expected_output = {
        default_for_new_public_repos: org_default_for_public.security_configuration_id,
        default_for_new_private_repos: org_default_for_private.security_configuration_id,
      }
      assert_equal expected_output, SecurityConfigurationDefault.default_security_configuration_ids_for(@business_org)
    end

    # Scenario 3: the org has 1 default record (both public & private), the enterprise has 1 default (both public & private)
    test "org defaults supersede enterprise level defaults when both are present (scenario 3)" do
      # Create org-level default:
      org_default = create(:security_configuration_default, :default_for_new_public_and_private_repos, target: @business_org)

      # Create enterprise-level default:
      create(:security_configuration_default, :default_for_new_public_and_private_repos, target: @business)

      expected_output = {
        default_for_new_public_repos: org_default.security_configuration_id,
        default_for_new_private_repos: org_default.security_configuration_id,
      }
      assert_equal expected_output, SecurityConfigurationDefault.default_security_configuration_ids_for(@business_org)
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
          security_configuration: security_config,
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
          security_configuration: security_config,
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
          security_configuration: security_config,
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
          security_configuration: security_config,
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
