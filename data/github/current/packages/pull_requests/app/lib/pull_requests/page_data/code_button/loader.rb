# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::CodeButton
  class Loader
    extend T::Sig
    include GitHub::ResilienceMixin

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class RepositoryPolicyInfoData < T::Struct
      const :allowed, T::Boolean
      const :can_bill, T::Boolean
      const :changes_would_be_safe, T::Boolean
      const :disabled_by_business,  T::Boolean
      const :disabled_by_organization,  T::Boolean
      const :has_ip_allowlists,  T::Boolean
    end

    class CodeButtonData < T::Struct
      const :contact_path, String
      const :current_user_is_enterprise_managed, T::Boolean
      const :enterprise_managed_business_name, T.nilable(String)
      const :has_access_to_codespaces, T::Boolean
      const :is_logged_in, T::Boolean
      const :new_codespace_path, String
      const :repository_policy_info, T.nilable(RepositoryPolicyInfoData)
    end

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
      ).returns(CodeButtonData)
    end
    def self.load(current_user:, pull_request:)
      new(current_user:, pull_request:).load
    end

    sig { params(current_user: T.nilable(User), pull_request: PullRequest).void }
    def initialize(current_user:, pull_request:)
      @current_user = current_user
      @pull_request = pull_request
    end

    sig { returns(CodeButtonData) }
    def load
      repository = T.must(pull_request.repository)
      repository_policy = nil
      repository_policy_info = nil

      if current_user
        repository_policy = with_database_error_fallback(fallback: nil) do
          Codespaces::RepositoryPolicy.async_with_prefill(current_user, repository).sync
        end
      end

      if repository_policy.present?
        repository_policy_info = RepositoryPolicyInfoData.new(
          allowed: repository_policy.allowed?,
          can_bill: repository_policy.can_bill?,
          changes_would_be_safe: repository_policy.changes_would_be_safe?,
          disabled_by_business: repository_policy.disabled_by_business?,
          disabled_by_organization: repository_policy.disabled_by_organization?,
          has_ip_allowlists: repository_policy.has_ip_allowlists?,
        )
      end

      codespaces_menu_visibility = Codespaces::MenuVisibility.new(
        pull_request:,
        repository_policy:,
        user: current_user,
      )
      has_access_to_codespaces = with_database_error_fallback(fallback: false) do
        codespaces_menu_visibility.has_access_to_codespaces?
      end

      current_user_is_enterprise_managed = !!current_user&.is_enterprise_managed?
      enterprise_managed_business_name = current_user&.enterprise_managed_business&.name || ""

      contact_path = Rails.application.routes.url_helpers.contact_path
      new_codespace_path = Rails.application.routes.url_helpers.new_codespace_path(
        repo: repository.id,
        hide_repo_select: true,
        ref: pull_request.head_ref
      )

      CodeButtonData.new(
        contact_path:,
        current_user_is_enterprise_managed:,
        enterprise_managed_business_name:,
        has_access_to_codespaces:,
        is_logged_in: current_user.present?,
        new_codespace_path:,
        repository_policy_info:,
      )
    end
  end
end
