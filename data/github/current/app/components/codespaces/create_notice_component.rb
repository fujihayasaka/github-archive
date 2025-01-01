# typed: true
# frozen_string_literal: true

# This component returns notices for users about codespace creation as a plain div with text.
# You should wrap this component with your own container element and styling.
# You can use render? and is_error? to determine styling needed.
# Notices include:
#   Codespaces creation is disabled on the repo
#   Codespaces creation is disabled because the user does not have push/fork permissions
#   Codespaces creation is disabled because the user has too many codespaces
#   Codespaces creation is disabled because spending limits have been reached
#   Codespaces creation is disabled because payment method has issues
#   Codespaces creation is disabled because the sku is unavailable
#   Codespaces creation is disabled because of an unexpected error
#   The codespace will be paid for by a organization
class Codespaces::CreateNoticeComponent < ApplicationComponent
  include CodespacesHelper
  include ResilienceHelper

  attr_reader :billable_owner, :user, :repository, :access_result, :user_codespace_limit, :machine_type_unavailable, :closed_pull_request, :unexpected_error, :is_spoofed_commit, :base_image_unavailable, :show_billable_owner, :extra_classes, :show_user_errors, :show_repo_errors

  def initialize(billable_owner:, user:, at_codespace_limit: nil, codespace: nil, repository: nil, user_codespace_limit: nil, machine_type_unavailable: false, unexpected_error: false, is_spoofed_commit: false, base_image_unavailable: false, closed_pull_request: false, show_billable_owner: true, extra_classes: "", show_user_errors: true, show_repo_errors: true)
    @billable_owner = billable_owner
    @user = user
    @at_codespace_limit = at_codespace_limit
    @repository = codespace&.repository || repository
    @user_codespace_limit = user_codespace_limit
    @machine_type_unavailable = machine_type_unavailable
    @unexpected_error = unexpected_error
    @access_result = Codespaces::AccessChecker.new(billable_owner, user: user, repository: @repository).run_billing_check if billable_owner
    @is_spoofed_commit = is_spoofed_commit
    @base_image_unavailable = base_image_unavailable
    @show_billable_owner = show_billable_owner
    @closed_pull_request = closed_pull_request
    @extra_classes = extra_classes
    @show_user_errors = show_user_errors
    @show_repo_errors = show_repo_errors
  end

  def render?
    notice_partial.present?
  end

  # Is the notice an error?
  # Parent components can check this value and render styles accordingly
  memoize def is_error?
    at_codespace_limit ||
      machine_type_unavailable ||
      is_spoofed_commit ||
      unexpected_error ||
      codespace_creation_disabled? ||
      !can_push_or_fork_repo? ||
      access_result&.disallowed_by_billing? ||
      unable_to_bill_emu? ||
      has_ip_allowlists? ||
      closed_pull_request ||
      base_image_unavailable ||
      org_policy_disallows_codespaces?
  end

  def repository_level_info_notice_partial
    case
    when billable_owner.present?
      "codespaces/create_notice/paid_for_by"
    end
  end

  def repository_level_error_notice_partial
    case
    when safe_repository_is_empty?
      "codespaces/create_notice/repository_is_empty"
    when unable_to_bill_emu?
      "codespaces/create_notice/unable_to_bill_emu"
    when org_policy_disallows_codespaces?
      "codespaces/create_notice/org_policy_disallows_codespaces"
    when !can_push_or_fork_repo?
      "codespaces/create_notice/cannot_push_or_fork_repo"
    when has_ip_allowlists?
      "codespaces/create_notice/has_ip_allowlists"
    when access_result&.disallowed_by_spending_limit?
      "codespaces/create_notice/disallowed_by_spending_limit"
    when access_result&.disallowed_by_entitlements?
      "codespaces/create_notice/disallowed_by_entitlements"
    when access_result&.disallowed_by_payment_method?
      "codespaces/create_notice/disallowed_by_payment_method"
    when access_result&.disallowed_by_billing?
      "codespaces/create_notice/disallowed_by_billing"
    when at_codespace_limit
      "codespaces/create_notice/at_codespace_limit"
    when machine_type_unavailable
      "codespaces/create_notice/machine_type_unavailable"
    when base_image_unavailable
      "codespaces/create_notice/base_image_unavailable"
    when unexpected_error
      "codespaces/create_notice/unexpected_error"
    when is_spoofed_commit
      "codespaces/create_notice/is_spoofed_commit"
    when closed_pull_request
      "codespaces/create_notice/closed_pull_request"
    end
  end

  def user_level_notice_partial
    case
    when codespace_creation_disabled?
      "codespaces/create_notice/creation_disabled"
    end
  end

  memoize def notice_partial
    notice_partial = user_level_notice_partial if show_user_errors

    return notice_partial if notice_partial.present?

    notice_partial = repository_level_error_notice_partial if show_repo_errors
    return notice_partial if notice_partial.present?

    notice_partial = repository_level_info_notice_partial if show_billable_owner
    notice_partial
  end


  # Checks whether they are at their limit regardless of how that limit was set (policy, GH global limit etc)
  memoize def at_codespace_limit
    @at_codespace_limit.nil? ? Codespaces::Query.new(current_user: user).at_limit?(billable_owner) : @at_codespace_limit
  end

  memoize def org_is_paying?
    billable_owner&.organization?
  end

  memoize def user_can_manage_billing?
    billable_owner&.billing_manageable_by?(user)
  end

  memoize def codespace_creation_disabled?
    user&.feature_enabled?(:disable_codespace_creation)
  end

  memoize def can_push_or_fork_repo?
    repository.nil? ||
      repository.pushable_by?(user) ||
      user.can_fork?(repository)
  end

  memoize def unable_to_bill_emu?
    billable_owner.nil? && user.is_enterprise_managed?
  end

  memoize def org_policy_disallows_codespaces?
    return false unless repository
    owning_organization = Codespaces::OrgPolicy.owning_organization(repository)
    return false unless owning_organization

    !Codespaces::OrgPolicy.new(user: user, org: owning_organization, repo: repository).async_can_use_codespaces?.sync
  end

  memoize def has_ip_allowlists?
    return false if repository.nil?
    return false unless repository.owner&.organization?

    repository.owner&.ip_allowlist_enabled? || repository.owner&.ip_allowlist_enabled_on_business?
  end

  memoize def show_policy_codespaces_limit?
    show_limit = !policy_codespaces_limit.nil? && Codespaces::Query.new(current_user: user).all_accessible_codespaces_for_org(billable_owner).count >= policy_codespaces_limit
    if show_limit
      GitHub.dogstats.increment("codespaces.policy_enforcement.warning", tags: ["policy_constraint:#{Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS}"])
    end
    show_limit
  end

  memoize def policy_codespaces_limit
    @codespaces_policy_limit ||= Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(billable_owner)
  end

  memoize def codespaces_limit_policy_owner
    return billable_owner&.display_login unless billable_owner&.feature_enabled?(:codespaces_enterprise_policies) && billable_owner&.in_codespaces_salus_beta?

    limit, policy_owner = get_limit_and_policy_owner
    @codespaces_policy_limit ||= limit
    policy_owner&.name
  end

  memoize def show_org_policy_codespaces_limit?
    return true unless billable_owner&.feature_enabled?(:codespaces_enterprise_policies) && billable_owner&.in_codespaces_salus_beta?

    _, policy_owner = get_limit_and_policy_owner
    !policy_owner&.business?
  end

  private

  memoize def get_limit_and_policy_owner
    Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(billable_owner)
  end

  memoize def safe_repository_is_empty?
    with_database_error_fallback(fallback: false) { repository&.empty? }
  end
end
