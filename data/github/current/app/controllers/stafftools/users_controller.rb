# typed: true
# frozen_string_literal: true

class Stafftools::UsersController < StafftoolsController
  include EnterpriseManagedUsersHelper
  include StafftoolsHelper
  include Stafftools::Users::ControllerMethods
  include Stafftools::Users::ControllerLayoutMethods
  include Stafftools::Users::ControllerPackageRegistryMethods

  before_action :enterprise_required, only: [:index]
  before_action :ensure_user_exists, except: %i(index destroy)

  layout "stafftools"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Permissions,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    index_view = Stafftools::User::IndexView.new(title: "All users")
    users = paginate(User, user_query)
    render "stafftools/users/index", locals: { view: index_view, users: users }
  end

  def show

    fetch_error_states

    @counts = {
      total_repos: this_user.repository_counts.total_repositories,
      private_repos: this_user.repository_counts.private_repositories,
      internal_repos: this_user.repository_counts.internal_repositories,
      public_repos: this_user.repository_counts.public_repositories,
      disabled_repos: this_user.repository_counts.disabled_repositories,
      locked_repos: this_user.repository_counts.locked_repositories,
      repos_with_pages: repos_with_pages,
      repos_with_deleted_pages: repos_with_deleted_pages,
      blocked_users: this_user.ignored.size,
      owned_apps: this_user.oauth_applications.size,
      owned_integrations: this_user.integrations.size,
      installed_integrations: this_user.integration_installations.size,
      ignored_by: this_user.ignored_by.size,
      pinned_repos: this_user.total_pinned_repositories,
      minimized_comments: Stafftools::RecentComments.minimized_comment_count(this_user, current_user),
      unmigrated_packages: unmigrated_package_count,
      organization_packages: organization_package_count,
      owned_projects_beta: this_user.memex_projects.size,
      reminders: Reminder.for_remindable(this_user).count + PersonalReminder.where(user: this_user).count
    }

    if ProjectsClassicSunset.projects_classic_ui_enabled?(this_user)
      classic_projects_counts = {
        total_projects: this_user.projects.size,
        public_projects: this_user.projects.open_projects.where(public: true).size,
        private_projects: this_user.projects.open_projects.where(public: false).size,
        closed_projects: this_user.projects.closed_projects.size,
      }

      @counts.merge! classic_projects_counts
    end

    # repository_counts above already exclude soft-deleted repos in their counts.
    # include them in the deleted count here
    deleted = Repositories::Public.deleted_owned_by(this_user.id).size
    @counts[:archived_repos] = deleted
    @counts[:total_repos] += deleted

    @last_transaction = this_user.billing_transactions.sales.last

    if GitHub.user_abuse_mitigation_enabled?
      options = {
        phrase: this_user.recent_abuse_reports_query,
        current_user: current_user,
      }
      if driftwood_ade_query?(current_user)
        options[:phrase] = this_user.recent_abuse_reports_kql_query
      end
      abuse_query = Audit::Driftwood::Query.new_stafftools_query(options)
      @counts[:recent_abuse_reports] = abuse_query.execute.size
    end

    gists = {
      public_gists: this_user.public_gists.size,
      secret_gists: this_user.private_gists.size,
      deleted_gists: this_user.gists.deleted.size,
    }
    @counts.merge! gists
    @counts[:gists] = gists.values.sum

    if this_user.user?
      @counts.merge! \
        emails: this_user.emails.user_entered_emails.size,
        gpg_keys: this_user.gpg_keys.primary_keys.size,
        ssh_keys: this_user.public_keys.size,
        security_keys: this_user.u2f_registrations.security_keys.size,
        trusted_devices: this_user.u2f_registrations.passkeys.size

      # only fetch mobile device auth keys from authnd if not in an enterprise environment
      unless GitHub.enterprise?
        @counts[:github_mobile_2fa_registrations] = this_user.display_mobile_device_auth_keys.size
      end

      enterprises = {
        owned_enterprises: this_user.businesses(membership_type: :admin).size,
        billing_enterprises: this_user.businesses(membership_type: :billing_manager).size,
        member_enterprises: this_user.guest_collaborator? ? 1 : this_user.businesses.size,
        unaffiliated_enterprises: BusinessUserAccount.where(user: this_user).exclusive_unaffiliated_role.size,
        guest_collaborator_enterprises: this_user.guest_collaborator? ? 1 : 0,
      }
      @counts.merge! enterprises
      @counts[:enterprises] = enterprises.values.sum
      orgs = {
        member_orgs: this_user.organizations.size,
        owned_orgs: this_user.owned_organizations.size,
        billing_orgs: this_user.billing_manager_organizations.size,
      }
      @counts.merge! orgs
      @counts[:orgs] = orgs.values.sum

      @counts[:authed_integrations] = this_user.oauth_authorizations.github_apps.size

      if current_user.patsv2_enabled?
        @counts[:personal_access_tokens] = ProgrammaticAccess.for(this_user).size
      end

      oauths = {
        owned_apps: @counts[:owned_apps],
        authed_third_party_apps: this_user.oauth_authorizations.third_party.oauth_apps.size,
        authed_github_owned_apps: this_user.oauth_authorizations.github_owned.size,
        tokens: this_user.oauth_accesses.personal_tokens.size,
      }

      @counts.merge! oauths
      @counts[:oauths] = oauths.values.sum
    else
      @counts[:webhooks] = this_user.hooks.size if GitHub.hookshot_enabled?

      @counts[:enterprise_installations] = this_user.enterprise_installations.size
      @counts[:owned_projects] = this_user.projects.size
      @counts[:teams] = this_user.teams.size
      @counts[:members] = this_user.member_count
      @counts[:admins] = this_user.admins.size

      if GitHub.billing_enabled?
        @counts[:billing_managers] = this_user.billing_managers.size
      end

      if current_user.patsv2_enabled?
        @counts[:personal_access_tokens] = ProgrammaticAccessGrant.with_target(this_user).count
        @counts[:personal_access_token_requests] = ProgrammaticAccessGrantRequest.with_target(this_user).count
      end
    end

    case this_user.site_admin_context
    when "organization"
      render "stafftools/organizations/show", layout: "stafftools/organization"
    when "user"
      render "stafftools/users/show", layout: "stafftools/user", locals: {
        view: Stafftools::User::ShowView.new(user: this_user, current_user: current_user),
        layout: "stafftools/user",
        counts: @counts,
        error_states: @error_states,
        obfuscated_dupe_emails: @obfuscated_dupe_emails,
        spam_flag_timestamp: @spam_flag_timestamp,
        last_transaction: @last_transaction,
        user: this_user,
      }
    else
      render_404
    end
  end

  # Deletes an account directly, with failsafes to block deleting paying users
  def destroy
    return render_404 unless this_user.present?

    if this_user.system_account?
      flash[:error] = "This account is a system account and can't be deleted."
      return redirect_to :back
    end

    if GitHub.enterprise? && !this_user.organization?
      last_admin_of = this_user.solitarily_owned_organizations.pluck(:login)

      if last_admin_of.any?
        flash[:error] = "This user is the only admin in the following organizations and can't be deleted: #{last_admin_of.to_sentence}"
        return redirect_to :back
      end
    end

    if GitHub.billing_enabled?
      if this_user.paid_plan? && !soft_deleted_organization?
        flash[:error] = "This is a paying user, what do you think you're doing?"
        return redirect_to :back
      elsif this_user.organizations.any? { |org| org.paid_plan? }
        flash[:error] = "This user is in a paid org, it can't be deleted."
        return redirect_to :back
      end
    end

    this_user.async_destroy(current_user, site_admin_deletion: true)
    flash[:notice] = "#{this_user.type} deleted"
    redirect_to stafftools_path
  end

  private

  def soft_deleted_organization?
    this_user.organization? && this_user.soft_deleted?
  end

  def repos_with_pages
    this_user.repositories.joins(:page).count
  end

  def repos_with_deleted_pages
    this_user.repositories.joins(:page).where.not(page: { deleted_at: nil }).count
  end
end
