# typed: true
# frozen_string_literal: true

class Stafftools::EnterpriseInstallationsController < StafftoolsController
  layout "layouts/stafftools/enterprise_installation"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:accounts]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:contributions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
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
    only: [:user_accounts_uploads]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:accounts, :contributions, :show, :user_accounts_uploads, :index], optional: true

  def index
    installations = EnterpriseInstallation
      .for_query(params[:query])
      .order("created_at desc")
      .paginate(page: params[:page])
    render "stafftools/enterprise_installations/index",
      layout: "stafftools", locals: { installations: installations }
  end

  def show
    render "stafftools/enterprise_installations/show",
      locals: { installation: this_enterprise_installation }
  end

  def user_accounts_uploads # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/enterprise_installations/user_accounts_uploads",
      locals: {
        installation: this_enterprise_installation,
        uploads: this_enterprise_installation
          .user_accounts_uploads
          .order(created_at: :desc)
          .paginate(page: current_page)
      }
  end

  def accounts # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/enterprise_installations/accounts",
      locals: {
        installation: this_enterprise_installation,
        accounts: this_enterprise_installation
          .user_accounts
          .includes(:emails)
          .order(login: :asc)
          .paginate(page: current_page)
      }
  end

  def contributions # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/enterprise_installations/contributions",
      locals: {
        installation: this_enterprise_installation,
        contributions: this_enterprise_installation
          .enterprise_contributions.order(updated_at: :desc)
          .group("user_id")
          .paginate(page: current_page)
      }
  end

  def enqueue_user_accounts_uploads # rubocop:todo GitHub/UseRestfulActions
    SyncEnterpriseServerUserAccountsJob.perform_later(this_enterprise_installation.owner, this_enterprise_installation, params[:upload_id], ::User.staff_user)
    redirect_to \
    user_accounts_uploads_stafftools_enterprise_installation_path(this_enterprise_installation),
      notice: "Enterprise Server license usage import job enqueued."
  end

  def destroy
    this_enterprise_installation.destroy
    redirect_to \
      stafftools_enterprise_installations_path,
      notice: "Enterprise Server installation removed."
  end

  def block # rubocop:todo GitHub/UseRestfulActions
    EnterpriseInstallation.block(this_enterprise_installation.license_hash)
    redirect_to \
      stafftools_enterprise_installation_path(this_enterprise_installation),
      notice: "Enterprise Server installation license blocked."
  end

  def unblock # rubocop:todo GitHub/UseRestfulActions
    EnterpriseInstallation.unblock(this_enterprise_installation.license_hash)
    redirect_to \
      stafftools_enterprise_installation_path(this_enterprise_installation),
      notice: "Enterprise Server installation license unblocked."
  end

  private

  def this_enterprise_installation # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @installation ||= EnterpriseInstallation.find(params[:id])
  end
  helper_method :this_enterprise_installation
end
