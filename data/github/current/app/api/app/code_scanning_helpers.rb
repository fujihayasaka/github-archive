# typed: strict
# frozen_string_literal: true
require "turboscan"

module Api::App::CodeScanningHelpers
  ADVANCED_SECURITY_DISABLED_MESSAGE = "Advanced Security must be enabled for this repository to use code scanning."
  CODE_SCANNING_DISABLED_ENTERPRISE_MESSAGE = "Code scanning is not available within this GitHub Enterprise. For more information, please contact your application security team."
  CODE_SCANNING_REPOSITORY_DISABLED_MESSAGE = "Code scanning is not enabled for this repository. Please enable code scanning in the repository settings."
  MAX_ALERT_NUMBER = 4294967295 # We limit the maximum alert number you can request, to prevent overflow when serializing the alert number as protobuf.

  extend T::Helpers
  requires_ancestor { Api::App }

  include Api::App::CodeScanningCategoryHelper

  sig { returns(String) }
  def self.code_scanning_disabled_message
    if GitHub.enterprise?
      "Code scanning is not enabled. Please contact your local GitHub Enterprise site administrator for assistance."
    else
      CODE_SCANNING_REPOSITORY_DISABLED_MESSAGE
    end
  end

  # Check that the current user has read access to the given repo, and that
  # code scanning is usable on that repo.
  #
  # Use "forbid" to give a 403 vs a 404 response in the case that the user
  # does not have read access to the repository.
  sig { params(repo: Repository, forbid: T::Boolean).void }
  def ensure_read_access_and_code_scanning_enabled!(repo, forbid: false)
    can_read = access_allowed? :v4_get_repo,
                                resource: repo,
                                repo: repo,
                                allow_integrations: true,
                                allow_user_via_granular_actor: true

    deliver_error!(forbid ? 403 : 404) if !can_read

    # Report a user-friendly message if the repo is not opted in to advanced security / code scanning
    # We clear the accepted scopes, otherwise some clients misinterpret the 403 error in comination with the `X-Accepted-Oauth-Scopes` header as meaning you need more scopes.
    if repo.code_scanning_enterprise_disabled?
      @accepted_scopes = T.let([], T.nilable(T::Array[Symbol]))
      deliver_error!(403, message: CODE_SCANNING_DISABLED_ENTERPRISE_MESSAGE)
    end
    if repo.code_scanning_disabled_by_advanced_security?
      @accepted_scopes = T.let([], T.nilable(T::Array[Symbol]))
      deliver_error!(403, message: ADVANCED_SECURITY_DISABLED_MESSAGE)
    end
    if !repo.code_scanning_usable?
      @accepted_scopes = T.let([], T.nilable(T::Array[Symbol]))
      deliver_error!(403, message: Api::App::CodeScanningHelpers.code_scanning_disabled_message)
    end
  end

  sig { void }
  def ensure_non_conflicting_cursor_params!
    if params.key?(:after) && params.key?(:before)
      deliver_error!(400, message: "Please do not provide both 'before' and 'after' parameters.")
    end
  end

  sig { void }
  def ensure_non_conflicting_tool_params!
    if params[:tool_name].present? && params[:tool_guid].present?
      deliver_error!(400, message: "Please do not provide both 'tool_name' and 'tool_guid' parameters.")
    end
  end

  sig { returns(T.noreturn) }
  def deliver_code_scanning_unavailable_error!
    deliver_error!(503, message: "Code scanning unavailable. Please try again later.")
  end

  sig { returns(String) }
  def code_scanning_forbid_read_message
    "You are not authorized to read code scanning alerts."
  end

  sig { returns(String) }
  def code_scanning_forbid_write_message
    "You are not authorized to write code scanning alerts."
  end

  sig { params(repo: Repository).returns(T::Boolean) }
  def logged_into_public_repo_as_code_scanning_bot(repo)
    @remote_token_auth = T.let(@remote_token_auth, T.nilable(T::Boolean))
    !!(@remote_token_auth && repo.public && GitHub.is_code_scanning_bot?(current_user))
  end

  sig { params(visibilities: T::Array[String]).returns(T::Array[Integer]) }
  def from_repo_visibilities_to_proto_enums(visibilities)
    visibilities.map { |visibility| from_repo_visibility_to_proto_enum(visibility) }.compact
  end

  sig { params(visibility: String).returns(T.nilable(Integer)) }
  def from_repo_visibility_to_proto_enum(visibility)
    case visibility
    when Repository::PUBLIC_VISIBILITY
      Turboscan::Proto::RepositoryVisibility::REPOSITORY_VISIBILITY_PUBLIC
    when Repository::PRIVATE_VISIBILITY
      Turboscan::Proto::RepositoryVisibility::REPOSITORY_VISIBILITY_PRIVATE
    when Repository::INTERNAL_VISIBILITY
      Turboscan::Proto::RepositoryVisibility::REPOSITORY_VISIBILITY_INTERNAL
    end
  end

  sig { params(alert_number: Integer).void }
  def ensure_valid_alert_number!(alert_number)
    deliver_error!(400, message: "alert_number must be greater than zero") if alert_number < 1
    deliver_error!(400, message: "alert_number must be less than #{MAX_ALERT_NUMBER + 1}") if alert_number > MAX_ALERT_NUMBER
  end
end
