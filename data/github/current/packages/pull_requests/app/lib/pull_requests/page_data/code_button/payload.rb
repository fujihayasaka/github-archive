# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::CodeButton
  class Payload
    extend T::Sig

    class RepositoryPolicyInfoPayload < T::Struct
      const :allowed, T::Boolean
      const :canBill, T::Boolean
      const :changesWouldBeSafe, T::Boolean
      const :disabledByBusiness, T::Boolean
      const :disabledByOrganization, T::Boolean
      const :hasIpAllowLists, T::Boolean
    end

    class CodeButtonPayload < T::Struct
      const :contactPath, String
      const :currentUserIsEnterpriseManaged, T::Boolean
      const :enterpriseManagedBusinessName, T.nilable(String)
      const :hasAccessToCodespaces, T::Boolean
      const :isLoggedIn, T::Boolean
      const :newCodespacePath, String
      const :repositoryPolicyInfo, T.nilable(RepositoryPolicyInfoPayload)
    end

    sig do
      params(
        code_button_data: PullRequests::PageData::CodeButton::Loader::CodeButtonData
      ).returns(CodeButtonPayload)
    end
    def self.call(code_button_data)
      new(
        contact_path: code_button_data.contact_path,
        current_user_is_enterprise_managed: code_button_data.current_user_is_enterprise_managed,
        enterprise_managed_business_name: code_button_data.enterprise_managed_business_name,
        has_access_to_codespaces: code_button_data.has_access_to_codespaces,
        is_logged_in: code_button_data.is_logged_in,
        new_codespace_path: code_button_data.new_codespace_path,
        repository_policy_info: code_button_data.repository_policy_info
      ).call
    end

    sig do
      params(
        contact_path: String,
        current_user_is_enterprise_managed: T::Boolean,
        enterprise_managed_business_name: T.nilable(String),
        has_access_to_codespaces: T::Boolean,
        is_logged_in: T::Boolean,
        new_codespace_path: String,
        repository_policy_info: T.nilable(PullRequests::PageData::CodeButton::Loader::RepositoryPolicyInfoData),
      ).void
    end
    def initialize(
      contact_path:,
      current_user_is_enterprise_managed:,
      enterprise_managed_business_name:,
      has_access_to_codespaces:,
      is_logged_in:,
      new_codespace_path:,
      repository_policy_info:
    )
      @contact_path = contact_path
      @current_user_is_enterprise_managed = current_user_is_enterprise_managed
      @enterprise_managed_business_name = enterprise_managed_business_name
      @has_access_to_codespaces = has_access_to_codespaces
      @is_logged_in = is_logged_in
      @new_codespace_path = new_codespace_path
      @repository_policy_info = repository_policy_info
    end

    sig { returns(CodeButtonPayload) }
    def call
      repository_policy_info = \
        if (@repository_policy_info).present?
          RepositoryPolicyInfoPayload.new(
            allowed: @repository_policy_info.allowed,
            canBill: @repository_policy_info.can_bill,
            changesWouldBeSafe: @repository_policy_info.changes_would_be_safe,
            disabledByBusiness: @repository_policy_info.disabled_by_business,
            disabledByOrganization: @repository_policy_info.disabled_by_organization,
            hasIpAllowLists: @repository_policy_info.has_ip_allowlists,
          )
        else
          nil
        end

      CodeButtonPayload.new(
        contactPath: @contact_path,
        currentUserIsEnterpriseManaged: @current_user_is_enterprise_managed,
        enterpriseManagedBusinessName: @enterprise_managed_business_name,
        hasAccessToCodespaces: @has_access_to_codespaces,
        isLoggedIn: @is_logged_in,
        newCodespacePath: @new_codespace_path,
        repositoryPolicyInfo: repository_policy_info,
      )
    end
  end
end
