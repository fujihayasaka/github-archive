# typed: true
# frozen_string_literal: true

require_relative "package_firewall_connection"

module PackageFirewall
  module Twirp
    # Typed wrappers for the PolicyConfigAPI Twirp service defined in
    # github/package-firewall (`proto/package_firewall/policy_api/v0/policy_config_api.proto`),
    # vendored as `monolith-twirp-packagefirewall-package_firewall`.
    class PackageFirewallClient < PackageFirewall::Twirp::PackageFirewallConnection
      sig do
        params(
          enterprise_id: Integer,
          org_id: T.nilable(Integer),
          repo_id: T.nilable(Integer),
        ).returns(T.untyped)
      end
      def read_policy(enterprise_id:, org_id: nil, repo_id: nil)
        rpc(:ReadPolicy, {
          enterprise_id: enterprise_id,
          org_id: org_id,
          repo_id: repo_id,
        }.compact)
      end

      sig do
        params(
          enterprise_id: Integer,
          policy: T::Hash[Symbol, T.untyped],
          org_id: T.nilable(Integer),
          repo_id: T.nilable(Integer),
        ).returns(T.untyped)
      end
      def update_policy(enterprise_id:, policy:, org_id: nil, repo_id: nil)
        rpc(:UpdatePolicy, {
          enterprise_id: enterprise_id,
          policy: policy,
          org_id: org_id,
          repo_id: repo_id,
        }.compact)
      end

      sig do
        params(
          enterprise_id: Integer,
          allow_list: T::Array[T::Hash[Symbol, String]],
          deny_list: T::Array[T::Hash[Symbol, String]],
          org_id: T.nilable(Integer),
          repo_id: T.nilable(Integer),
        ).returns(T.untyped)
      end
      def add_package_override(enterprise_id:, allow_list: [], deny_list: [], org_id: nil, repo_id: nil)
        rpc(:AddPackageOverride, {
          enterprise_id: enterprise_id,
          allow_list: allow_list,
          deny_list: deny_list,
          org_id: org_id,
          repo_id: repo_id,
        }.compact)
      end

      sig do
        params(
          enterprise_id: Integer,
          org_id: T.nilable(Integer),
          repo_id: T.nilable(Integer),
        ).returns(T.untyped)
      end
      def list_package_override(enterprise_id:, org_id: nil, repo_id: nil)
        rpc(:ListPackageOverride, {
          enterprise_id: enterprise_id,
          org_id: org_id,
          repo_id: repo_id,
        }.compact)
      end

      sig do
        params(
          enterprise_id: Integer,
          allow_list: T::Array[T::Hash[Symbol, String]],
          deny_list: T::Array[T::Hash[Symbol, String]],
          org_id: T.nilable(Integer),
          repo_id: T.nilable(Integer),
        ).returns(T.untyped)
      end
      def delete_package_override(enterprise_id:, allow_list: [], deny_list: [], org_id: nil, repo_id: nil)
        rpc(:DeletePackageOverride, {
          enterprise_id: enterprise_id,
          allow_list: allow_list,
          deny_list: deny_list,
          org_id: org_id,
          repo_id: repo_id,
        }.compact)
      end

      private

      def twirp_class
        MonolithTwirp::Packagefirewall::PolicyAPI::V0::PolicyConfigAPIClient
      end
    end
  end
end
