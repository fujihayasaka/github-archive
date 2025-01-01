# typed: true
# frozen_string_literal: true

# Helpers to access a repository in the controller.
#
# These helpers provide access to a repository if one is specified in
# `params[:repository]`, but do not require it. Depends on `#current_user`.
module RepositoryControllerMethods
  extend T::Helpers

  include ApplicationHelper
  include CurrentRepositoryInteractionsHelper
  include PlatformHelper

  requires_ancestor { ApplicationController }

  def self.included(base)
    base.before_action :privacy_check
    base.before_action :network_privilege_check
  end

  # Every controller action and view that checks if a repository is locked for
  # migration should trace back to this method.
  #
  # Returns false unless current_repository.locked_on_migration? is true.
  def current_repository_locked_for_migration?
    return false unless current_repository
    current_repository.locked_on_migration?
  end

  # Every controller action and view that checks if a repository is writable
  # should trace back to this method.
  #
  # Returns true unless current_repository.locked_on_migration? or
  # current_repository.archived? are true.
  def current_repository_writable?
    return @current_repository_writable if defined?(@current_repository_writable)
    return @current_repository_writable = true unless current_repository
    @current_repository_writable = current_repository.writable?
  end

  private

  # Returns true if the current action is exempt from conditional access
  # requirements such as an external identity session or allowed IP.
  #
  # This will be true for all actions specified in a controller by a
  # `CONDITIONAL_ACCESS_BYPASS_ACTIONS` constant.
  #
  # If the current repo is public, this will be true for actions specified in
  # a controller by the `CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS`
  # constant.
  def conditional_access_exempt?
    bypass_constant_name = "CONDITIONAL_ACCESS_BYPASS_ACTIONS"
    if self.class.const_defined?(bypass_constant_name) && exempt_actions = self.class.const_get(bypass_constant_name)
      return true if exempt_actions.include?(action_name)
    end
    return false unless current_repository && current_repository.public?
    bypass_public_constant_name = "CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS"
    if self.class.const_defined?(bypass_public_constant_name) && exempt_actions = self.class.const_get(bypass_public_constant_name)
      return exempt_actions.include?(action_name)
    end

    false
  end

  # Bypass conditional access requirements for the specified actions if the
  # current action is exempt.
  def ip_allowlist_enforceable
    return :no if conditional_access_exempt?
    super
  end

  # Bypass external conditional access policy requirements for the specified actions if the
  # current action is exempt.
  def external_conditional_access_policy_enforceable
    return :no if conditional_access_exempt?
    super
  end

  def require_active_external_identity_session?
    return false if conditional_access_exempt?
    super
  end

  def two_factor_enforceable
    return :no if conditional_access_exempt?
    :yes
  end

  # Controllers with actions that change a repository that should be disabled
  # on an e.g. migrating repository but enabled on an e.g. archived repository
  # should use this helper instead. For example, we want to allow users to
  # delete their own comments on an archived repository.
  #
  # Returns nil or renders error json or migrating template with status :forbidden.
  def non_migrating_repository_required
    return unless current_repository_locked_for_migration?

    respond_to do |format|
      format.json do
        render json: { error: "repository locked for migration" },
               status: :forbidden
      end
      format.all do
        render "repositories/states/migrating",
               status: :forbidden,
               locals: { repo: current_repository }
      end
    end
  end

  # Controllers with actions that change a repository or any models that belong
  # to a repository should use this before filter to disable write access when
  # current_repository_writable? is false.
  #
  # Returns nil or renders error json or relevant template with status :forbidden.
  def writable_repository_required
    return if current_repository_writable?

    if current_repository.locked_on_migration?
      non_migrating_repository_required
    elsif current_repository.archived?
      respond_to do |format|
        format.json do
          render json: { error: "repository archived" },
                 status: :forbidden
        end
        format.all do
          render "repositories/states/archived",
                 status: :forbidden
        end
      end
    end
  end

  def repository_specified?
    params[:user_id].present? && params[:repository].present?
  end

  def current_repository
    return @current_repository if defined?(@current_repository)

    @current_repository = if owner && params[:repository].present?
      repo = Repositories.domain.by_name_and_owner(name: params[:repository], owner_id: owner.id)
      if repo
        GitHub::PrefillAssociations.prefill_associations(repo, :owner, available_records: [owner])
      end
      if repo && owner.organization? && repo.organization_id == owner.id
        GitHub::PrefillAssociations.prefill_associations(repo, :organization, available_records: [owner])
      end
      repo
    end

    @current_repository
  end

  def owner
    return @owner if defined?(@owner)
    @owner = if params[:user_id].present?
      User.find_by_login(params[:user_id])
    end
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end

  def resource_for_conditional_access
    # default to target_for_conditional_access if repo isn't available
    return self unless current_repository
    current_repository
  end

  # Restrict a page to those with read-access (or greater) only.
  # TODO: Horrible name!
  def privacy_check
    return if current_repository.nil?
    return if current_user_can_read_repo?

    respond_to do |format|
      format.html do
        # If the user is trying to view a private repo after receiveing an invitation,
        # redirect to the associated invitation instead.
        if logged_in? && invitation = current_repository.repository_invitations.where(invitee_id: current_user.id).first
          redirect_to invitation.permalink
        elsif logged_in? && current_user.site_admin?
          render_locked_repo_for_staff
        else
          render_404
        end
      end

      format.all do
        render_404
      end
    end
  end

  def render_locked_repo_for_staff
    render "admin/locked_repo"
  end

  def opt_in_kv_key
    "opt_in_to_flagged_repo.#{current_user.id}.#{current_repository.id}"
  end

  # Checks to see if user needs to log in to view repo or if repo is locked
  # and accessable to collaborators only
  def network_privilege_check
    return if current_repository.nil?
    return if current_repository.private?
    return unless current_repository.network_privilege

    # writable_by? is more expensive than #network_privilege,
    # so guard on this only after we know this repo has a network_privilege.
    return if current_repository.writable_by?(current_user)

    interstitial_content_warning = GitHub.opt_in_to_restricted_repo_enabled? && current_repository.should_render_content_warning_for?("interstitial")

    if !logged_in? && (current_repository.network_privilege.require_login? || interstitial_content_warning)
      redirect_to_login(return_to_path)
    elsif current_repository.network_privilege.collaborators_only?
      render_404
    elsif interstitial_content_warning && !associated_with_repo? && !opted_in?
      GitHub.dogstats.increment("network_privileges.warn_about_repo", tags: ["category:#{current_repository.network_privilege.content_warning_category}"])
      render "repositories/opt_in_interstitial", locals: {
        return_to: return_to_path,
        category: current_repository.network_privilege.content_warning_category
      }
    end
  end

  def opted_in?
    (
      Repositories::Kv.store.get(opt_in_kv_key).value { nil } ||
      GitHub::Result.new { ActiveModel::Type::Boolean.new.cast(params[:opt_in_to_view]) }.value { nil }
    )
  end

  def network_privilege_for_opt_in
    return render_404 if current_repository.nil? || current_repository.private?
    return render_404 unless GitHub.opt_in_to_restricted_repo_enabled?

    return unless current_repository.network_privilege

    if !logged_in?
      redirect_to_login(return_to_path)
    elsif current_repository.network_privilege.collaborators_only? && !current_repository.writable_by?(current_user)
      render_404
    end
  end

  def associated_with_repo?
    (current_repository.owner.is_a?(Organization) && current_repository.owner.member?(current_user)) || current_repository.contributor?(current_user)
  end

  # Restrict a page to those with read/write-access (or greater) only.
  def pushers_only
    return if current_repository.nil?
    return if current_user_can_push?

    if logged_in?
      redirect_home
    else
      redirect_to_login(return_to_path)
    end
  end

  def adequate_oauth_scope(scopes)
    Api::AccessControl.oauth_allows_access?(current_user, current_repository)
  end

  # There are many reasons we may not be able to show a repository. This
  # filter goes through all possible scenarios and renders the appropriate
  # template if we cannot show the code.
  #
  # nonexist     - The repo straight up doesn't exist. Or has been deleted.
  # disabled     - You haven't paid your bills, so we've disabled the repo.
  # dmca         - You're hosting material that's not yours.
  # spammy       - Repository's owner has been marked as Spammy
  # abusive      - Access to the repo is disabled due to abusive size.
  # staff_locked - Access to the repo is disabled by staff.
  # billing_locked - The repo has been locked by an admin due to billing issues
  #
  # You can fake each of these states with params[:fakestate] equal to the
  # words listed above.
  #
  # Please see GitContentController#ask_the_gitkeeper! It checks for similar
  # ideas, but specific to showing content from Git and runs after this one.
  #
  # Returns nothing.
  def ask_the_gatekeeper
    GitHub.tracer.in_span("RepositoryControllerMethods#ask_the_gatekeeper", kind: :internal) do
      repo = current_repository
      return unless repository_specified?
      state = params[:fakestate] if real_user_site_admin?

      repo_nonexist = (repo.nil? || !repo.active?) || state == "nonexist"

      if repo_nonexist
        redirect_to_name_based_url || redirect_to_new_repository_location || render_404
        return
      end

      country = request.headers["HTTP_X_COUNTRY"]
      repo_spammy                   = repo.hide_from_user?(current_user) || state == "spammy"
      repo_disabled                 = repo.disabled?(viewer: current_user) || state == "disabled"
      repo_access_disabled          = repo.access.disabled? || state == "access_disabled"
      repo_dmca                     = repo.access.dmca? || state == "dmca"
      repo_abusive                  = repo.access.abusive? || state == "abusive"
      repo_broken                   = repo.access.broken? || state == "broken"
      repo_sensitive_data           = repo.access.sensitive_data_violation? || state == "sensitive_data"
      repo_private_information      = repo.access.private_information_violation? || state == "private_information"
      repo_trademark_locked         = repo.access.trademark_violation? || state == "trademark"
      repo_staff_locked             = repo.access.tos_violation? || repo.access.disabled_by_admin? || state == "staff_locked"
      repo_country_block            = repo.access.country_block?(country)
      repo_billing_locked           = repo.locked_on_billing? || state == "billing_locked"
      repo_trade_restriction_locked = repo.locked_on_trade_restriction?

      response.header["X-Disabled"] = "true" if repo.access.disabled?

      # Deny access to fork when root repository owner IP allowlist condition not met
      # Temporary for Intel. See https://github.com/github/reponauts/issues/53.
      repo_ip_restricted = repo.ip_restricted_private_fork?

      repo_inaccessible = repo.private? && !current_user.try(:site_admin?) && !current_user_can_read_repo?
      if (repo_disabled || repo_access_disabled || repo_billing_locked || repo_trade_restriction_locked) && repo_inaccessible
        render_404
      elsif repo_spammy
        GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:spammy"])
        render_404
      elsif repo_disabled
        unless action_name == "set_visibility" && repo.has_any_trade_restrictions?
          GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:disabled"])
          render "repositories/states/disabled"
        end
      elsif repo_billing_locked
        GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:billing_locked"])
        render "repositories/states/disabled"
      elsif repo_trade_restriction_locked
        GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:trade_restriction_locked"])
        render "repositories/states/disabled"
      elsif repo_dmca
        GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:dmca"])
        render "repositories/states/dmca", layout: "layouts/repository_disabled", status: 451
      elsif repo_abusive
        GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:abusive"])
        render "repositories/states/abusive", layout: "layouts/repository_disabled"
      elsif repo_broken
        GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:broken"])
        render "repositories/states/broken", layout: "layouts/repository_disabled"
      elsif repo_sensitive_data
        GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:sensitive_data"])
        render "repositories/states/sensitive_data", layout: "layouts/repository_disabled"
      elsif repo_private_information
        GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:private_information"])
        render "repositories/states/private_information", layout: "layouts/repository_disabled"
      elsif repo_trademark_locked
        GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:trademark"])
        render "repositories/states/trademark_locked", layout: "layouts/repository_disabled"
      elsif repo_staff_locked
        GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:staff_locked"])
        render "repositories/states/staff_locked", layout: "layouts/repository_disabled"
      elsif repo_access_disabled
        # In general, when a repo is disabled, one of the above cases should
        # render a view that targets the specific reason it was disabled. This
        # case exists as a safety check to protect against scenarios where a repo
        # is disabled but isn't caught by the more specific checks.
        GitHub.dogstats.increment("repo", tags: ["action:ask_the_gatekeeper", "state:access_disabled"])
        render "repositories/states/access_disabled", layout: "layouts/repository_disabled"
      elsif repo_country_block
        country_block_url = current_repository.country_blocks[repo_country_block]
        if GitRepositoryBlock::COUNTRY_BLOCK_DESCRIPTIONS.has_key?(repo_country_block)
          render "repositories/states/nation_blocklist", locals: { country_block_url: country_block_url }, layout: "layouts/repository_disabled", status: 451
        else
          render_404
        end
      # Temporary for Intel. See https://github.com/github/reponauts/issues/53.
      elsif repo_ip_restricted
        cap_enforcer.enforce_conditional_access_policies(
          repo.network_owner, policies: [:ip_allowlist]
        )
      end
    end
  end

  # Tries to redirect an URL containing database IDs (e.g. "/123/456/issues")
  # to the usual one containing org/repo names ("/github/github/issues").
  #
  # This allows us to use URLs constructed with IDs in internal applications.
  # That type of URL is useful for, say, caching, because it is stable in the
  # face of organization or repository renames.
  #
  # The redirect will only be issued if:
  #   1. We've already missed when looking up the current repo by name.
  #   2. The user has read access to the resolved repository.
  def redirect_to_name_based_url
    return if current_repository

    # This isn't necessarily fully-permissive, so we might choose to expand it
    # in the future. For now, it matches the following cases:
    #
    # /123/456
    # /123/456?q=1
    # /123/456#foo
    # /123/456/foo
    # /123/456.json
    #
    # But will not match something like:
    #
    # /123/456foo
    id_based_url_match = request.fullpath.match(%r{\A/(\d+)/(\d+)([/?#.].*)?\z})
    return unless id_based_url_match

    user_id, repo_id, suffix = id_based_url_match[1..3]

    repository = Repository.find_by(owner_id: user_id, id: repo_id)
    return unless repository&.readable_by?(current_user)

    rewritten_url = "/#{repository.name_with_display_owner}#{suffix.present? ? suffix : ""}"
    safe_redirect_to rewritten_url
    true
  end

  # Look for a repository redirect record for the repository name given and
  # redirect there if found. This should only be called when a repository with
  # the current repository name does not exist.
  #
  # When a redirect record exists but points to a private repository, the current
  # user must have pullable access or the redirect does not take place. This is
  # to prevent surfacing the existence of private repos via redirect.
  #
  # Returns true if a redirect was made.
  def redirect_to_new_repository_location
    return unless match = canonical_request.fullpath.scan(%r{\A/([\w.-]+/[\w.-]+)(.*)\z}).first
    redirect_to_new_repository_location_with match[0], nil, match[1]
  end

  # old_name - "Name with owner" String that identifies a moved or renamed Repository.
  # prefix   - String prefix to the redirected URL.
  # suffix   - String suffix to the redirected URL.
  def redirect_to_new_repository_location_with(old_name, prefix, suffix)
    repository = RepositoryRedirect.find_redirected_repository(old_name)
    return unless repository && repository.pullable_by?(current_user)

    rewritten_url = "#{prefix}/#{repository.name_with_display_owner}".dup
    rewritten_url << suffix if !suffix.empty?
    redirect_to rewritten_url, status: 301

    true
  end

  PDF_HEADERS = %w(%PDF %!PS)
  PDF_REGEX   = Regexp.union PDF_HEADERS.map { |h| Regexp.escape(h) }

  # Return 403 if PDF headers are present in the text. See #36923.
  #
  # text - A String.
  #
  # Renders a 403 and returns true if the text includes PDF header bytes.
  def render_error_for_pdf_headers(text)
    if text =~ PDF_REGEX
      message = "Content containing PDF or PS header bytes cannot be rendered from this domain for security reasons."
      render status: 403, plain: message
    end
  end

  # Create a unique key for scoping AuthorizationTokens to pull request.
  #
  # Returns a String with the repo and pull request id in it.
  def pull_request_authorization_token_scope_key
    "PullRequest:#{current_repository}:#{params[:id]}"
  end

  # Public: Check if the viewer has write access to the repository being viewed.
  #
  # A helper method is exposed for use in views via `AbstractRepositoryController`.
  #
  # Returns a Boolean.
  def current_user_can_write_to_repo?
    if defined?(@current_user_can_write_to_repo)
      @current_user_can_write_to_repo
    else
      @current_user_can_write_to_repo = current_repository.writable_by?(current_user)
    end
  end
end
