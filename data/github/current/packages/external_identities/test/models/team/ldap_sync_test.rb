# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.enterprise?
  class LdapTeamDependencyTest < GitHub::TestCase
    include AuthenticationHelpers::LDAP

    setup_once { LdapHelper.setup_ldap_authentication }
    teardown_once { LdapHelper.teardown_ldap_authentication }

    fixtures do
      @owner = create(:user)
      @org = create :organization, admin: @owner
      @synced_team = create(:team, organization: @org)
      @synced_team.create_ldap_mapping dn: "dn=group,ou=test"
    end

    context "ldap_mapped?" do
      ldap_test "returns true when a Team has an LdapMapping" do
        assert @synced_team.ldap_mapped?, "team should be LDAP mapped"
      end

      test "returns false if not in LDAP authentication mode" do
        refute @synced_team.ldap_mapped?, "team should not be LDAP mapped"
        assert @synced_team.ldap_mapping, "team should still have LDAP mapping"
      end

      ldap_test "returns false if in LDAP authentication mode but without mapping" do
        synced_team = create(:team, organization: @org)
        refute synced_team.ldap_mapped?, "team should not be LDAP mapped"
      end
    end

    context "ldap_syncing?" do
      test "returns false when ldap is not enabled" do
        refute @synced_team.ldap_syncing?, "team should not be syncing"
      end

      ldap_test "returns false when there is no ldap mapping" do
        @synced_team.ldap_mapping.destroy
        refute @synced_team.ldap_syncing?, "team should not be syncing"
      end

      ldap_test "return false when ldap mapping is in a state that's not syncing" do
        @synced_team.ldap_mapping.sync_status = :synced
        refute @synced_team.ldap_syncing?, "team should not be syncing"

        @synced_team.ldap_mapping.sync_status = :error
        refute @synced_team.ldap_syncing?, "team should not be syncing"

        @synced_team.ldap_mapping.sync_status = :queued
        refute @synced_team.ldap_syncing?, "team should not be syncing"
      end

      ldap_test "return true when ldap mapping is syncing" do
        @synced_team.ldap_mapping.sync_status = :syncing
        assert @synced_team.ldap_syncing?, "team should be syncing"
      end
    end

    context "ldap_synced?" do
      test "returns false when ldap is not enabled" do
        refute @synced_team.ldap_synced?, "team should not be synced"
      end

      ldap_test "returns false when there is no ldap mapping" do
        @synced_team.ldap_mapping.destroy
        refute @synced_team.ldap_synced?, "team should not be synced"
      end

      ldap_test "return false when ldap mapping is in a state that's not sycned" do
        @synced_team.ldap_mapping.sync_status = :syncing
        refute @synced_team.ldap_synced?, "team should not be synced"

        @synced_team.ldap_mapping.sync_status = :error
        refute @synced_team.ldap_synced?, "team should not be synced"

        @synced_team.ldap_mapping.sync_status = :queued
        refute @synced_team.ldap_synced?, "team should not be synced"
      end

      ldap_test "return true when ldap mapping is synced" do
        @synced_team.ldap_mapping.sync_status = :synced
        assert @synced_team.ldap_synced?, "team should be synced"
      end
    end

    context "ldap_syncing_queued?" do
      test "returns false when ldap is not enabled" do
        refute @synced_team.ldap_syncing_queued?, "team should not be queued"
      end

      ldap_test "returns false when there is no ldap mapping" do
        @synced_team.ldap_mapping.destroy
        refute @synced_team.ldap_syncing_queued?, "team should not be queued"
      end

      ldap_test "return false when ldap mapping is in a state that's not queued" do
        @synced_team.ldap_mapping.sync_status = :syncing
        refute @synced_team.ldap_syncing_queued?, "team should not be queued"

        @synced_team.ldap_mapping.sync_status = :error
        refute @synced_team.ldap_syncing_queued?, "team should not be queued"

        @synced_team.ldap_mapping.sync_status = :synced
        refute @synced_team.ldap_syncing_queued?, "team should not be queued"
      end

      ldap_test "return true when ldap mapping is queued" do
        @synced_team.ldap_mapping.sync_status = :queued
        assert @synced_team.ldap_syncing_queued?, "team should be queued"
      end
    end
  end
end
