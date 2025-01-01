# typed: true
# frozen_string_literal: true

class Integrations::SelectTargetView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include GitHub::Memoizer

  attr_reader :integration, :page

  delegate :name, :url, :description, :owner, :installed_on?, to: :integration, prefix: true

  PER_PAGE  = 10

  def can_see_install_button?
    installable? || internal_app_requestable?
  end

  def disabled_for?(target:)
    @disabled_for_cache ||= {}
    return @disabled_for_cache[target.id] if @disabled_for_cache.has_key?(target.id)
    @disabled_for_cache[target.id] = !integration.requestable_on_by?(target: target, actor: current_user) && !integration.installable_on_by?(target: target, actor: current_user) && !integration.installed_on?(target)
  end

  def integration_installed?
    accounts.any? { |account| integration.installed_on?(account) }
  end

  def installation_for_account(account)
    integration.installations.with_target(account).first
  end

  def integration_github_owned?
    integration.github_owned?
  end

  def verified_email_required?
    integration.verified_email_required?(current_user)
  end

  def open_requests
    return [] unless logged_in?
    @open_requests ||= IntegrationInstallationRequest.includes(:target).where(
      integration: integration,
      requester: current_user,
    ).index_by(&:target)
  end

  def request_on_target(target)
    open_requests[target]
  end

  # Public: Returns the full set of accounts that the user may have
  # installation rights against. For public integrations this includes any
  # account which they have admin rights for. For private integrations this
  # only includes the account which owns the integration.
  #
  # Returns an ActiveRecord Relation of User/Organizations.
  memoize def accounts
    accounts = \
      if !logged_in?
        Organization.none
      elsif integration.public_visibility?
        all_accounts
      elsif integration.internal_visibility?
        # TODO: Currently internal visibility is restricted to enterprise-owned
        # apps, which can only be installed on enterprise-owned organizations
        # or the enterprise itself (if the app requests enterprise-level
        # permissions).
        #
        # This will change when we allow any enterprise-owned organization to
        # create an internal-visibility app (that can be installed on its
        # sibling orgs).
        #
        # Also, enterprise-managed organizations currently use a
        # hack to simulate "internal" visibilty, which is to use the
        # `integrations.public` boolean flag and CAP policies to prevent
        # installation outside of the owning enterprise. Eventually this can
        # all be moved to internal visibility, which will make maintenance less
        # onerous and improve the approachability of this code.
        organization_ids = []
        if integration.owner.business?
          organization_ids.concat(integration.owner.organizations_for_member(current_user).pluck(:id))
        end
        organization_ids.append(current_user.id)

        User.where(id: organization_ids).order(type: "DESC", login: "ASC")
      elsif cannot_be_installed_or_requested_on_integration_owner?
        Organization.none
      elsif integration.owner_type == "Business"
        # This shouldn't be accessible with the Internal Visibility check above
        Business.where(id: integration.owner.id)
      else
        owner = User.find_by(id: integration.owner.id)
        if owner&.is_enterprise_managed?
          integration.installable_on?(owner) ? [owner] : []
        else
          [owner].compact
        end
      end

    if page.present?
      accounts.paginate(page: page, per_page: PER_PAGE)
    else
      accounts
    end
  end

  def selection_needed?
    (page.present? && page != 1) || accounts.many? || can_install_on_business?
  end

  # Public: which URL should configuration start at?
  #
  # Returns a path
  def configure_url
    if selection_needed?
      urls.gh_new_app_installation_path(integration, current_user)
    else
      configure_url_for(accounts.first)
    end
  end

  def configure_url_for(account)
    if (installation = installation_for_account(account))
      if installation.adminable_by?(current_user)
        urls.gh_settings_installation_path(installation)
      else
        urls.gh_edit_app_installation_path(integration, installation, current_user)
      end
    end
  end

  def can_install_on_business?
    return false unless integration_owner_business

    integration.installable_on_by?(target: integration_owner_business, actor: current_user)
  end

  memoize def integration_owner_business
    # If the integration owner is an EMU we can use this check
    business = integration.owner_enterprise_managed_business
    return business if business

    # If the integration owner is not in an EMU environment,
    # then only organizations and enterprise-owned apps can possibly have a
    # `business` owner.
    case integration.owner
    when Business; integration.owner
    when Organization; integration.owner.business
    else; nil
    end
  end

  private

  def installable?
    integration.installable_by?(current_user)
  end

  def internal_app_requestable?
    integration.internal_visibility? && \
      integration.owner.async_member?(current_user).sync && \
      integration.owner.user_is_member_of_owned_org?(current_user)
  end

  def cannot_be_installed_or_requested_on_integration_owner?
    !(integration.installable_on_by?(target: integration.owner, actor: current_user) || \
      integration.requestable_on_by?(target: integration.owner, actor: current_user))
  end

  def all_accounts
    return [] unless logged_in?

    organization_ids = []

    # Don't bother calculating the access to repositories if
    # the integration doesn't have repository permissions.
    if integration.latest_version.any_permissions_of_type?(Repository)
      repository_ids = current_user.associated_repository_ids(including: [:direct])

      # We can find repositories owned by organizations by seeing both
      # the organization_id is set and it matches the owner_id
      organization_ids = Repository.where("organization_id = owner_id AND id IN (?)", repository_ids).distinct.pluck(:organization_id)
    end

    organization_ids |= User::OrganizationFilter.new(current_user).unscoped_ids
    organization_ids.append(current_user.id) unless current_user.is_enterprise_managed? && !Apps::Privileged.capable?(:installable_on_emus, app: integration)

    User.where(id: organization_ids).order(type: "DESC", login: "ASC")
  end
end
