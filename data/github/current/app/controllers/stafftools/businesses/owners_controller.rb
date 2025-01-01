# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::OwnersController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required, only: %w(index)
  before_action :check_for_owners, only: %w(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    owners = this_business.admins(query: params[:query], role: :owner)
      .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
    render "stafftools/businesses/admins", locals: { owners: owners }
  end

  def create
    if ::User.valid_email?(params[:owner])
      begin
        if this_business.enterprise_managed_user_enabled?
          owner = this_business.find_first_emu_owner

          if owner
            flash[:notice] = "User #{owner} is already an owner of #{this_business.name}, and there \
              can be only one non-IdP managed owner.".squish
          else
            this_business.create_and_add_first_emu_owner(email: params[:owner], actor: current_user)

            flash[:notice] = <<~NOTICE
              You've added #{params[:owner]} as an
              owner of #{this_business.name}!
              They'll be receiving an email shortly.
            NOTICE
          end

          redirect_to owners_redirect_path
        else
          this_business.invite_admin(email: params[:owner], inviter: current_user,
            role: "owner", stafftools_invite: true)

          notice = <<~NOTICE
            You've invited #{params[:owner]} to become an
            owner of #{this_business.name}!
            They'll be receiving an email shortly.
          NOTICE

          redirect_to owners_redirect_path(
            default_redirect_path: stafftools_enterprise_pending_owners_path(this_business)
          ), notice: notice
        end
      rescue BusinessAdministratorInvitation::AlreadyAcceptedError,
             BusinessAdministratorInvitation::InvalidError,
             ActiveRecord::RecordInvalid,
             Business::UnableToCreateAdminUserError,
             Business::AdminAlreadyExistsError => error
        flash[:error] = error.message
        redirect_to owners_redirect_path(
          default_redirect_path: stafftools_enterprise_pending_owners_path(this_business)
        )
      end
    else
      # For EMU enabled enterprises, we continue to read from global directory which should be
      # scoped to only provisioned user in the enterprise.
      # https://github.com/github/external-identities/issues/392
      owner = owner_from_param
      unless owner
        flash[:error] = "User #{params[:owner]} does not exist."
        return redirect_to owners_redirect_path
      end

      unless owner.try(:user?)
        flash[:error] = "Owner must be a user."
        return redirect_to owners_redirect_path
      end

      if this_business.owners.include? owner
        flash[:notice] = "User #{owner.login} is already an owner of #{this_business.name}."
        return redirect_to owners_redirect_path
      end

      begin
        this_business.add_owner(owner, actor: current_user, send_email_notification: true)
        flash[:notice] = "Added owner #{owner.login} and notified them by email."
      rescue Business::UserHasNoExternalIdentityError,
        Business::InvalidAdminStateError => error
        flash[:error] = error.message
      end
      redirect_to owners_redirect_path
    end
  end

  def destroy
    owner = owner_from_param

    unless owner
      flash[:error] = "User #{params[:owner]} does not exist."
      return redirect_to owners_redirect_path
    end

    begin
      this_business.remove_owner(owner, actor: current_user)
      flash[:notice] = "Removed owner #{owner.login}."
    rescue ::Business::NoAdminsError
      flash[:error] = "You cannot remove the last owner of this enterprise account."
    rescue ::Business::ManagedUserDependency::CannotRemoveFirstEmuOwnerError
      flash[:error] = "User #{owner.login} is the first EMU owner and cannot be removed."
    end
    redirect_to owners_redirect_path
  end

  private

  def owner_from_param
    ::User.find_by login: params[:owner]
  end

  def owners_redirect_path(default_redirect_path: stafftools_enterprise_owners_path(this_business))
    return stafftools_enterprise_complete_path(this_business) if params[:complete_page] == "1"
    default_redirect_path
  end
end
