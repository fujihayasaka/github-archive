# typed: true
# frozen_string_literal: true

class DeveloperProgramMembershipController < ApplicationController
  include DeveloperHelper
  include AccountMembershipHelper

  before_action :login_required
  before_action :dotcom_required
  before_action :redirect_if_no_account, only: :new

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :new], optional: true

  stylesheet_bundle :signup

  def new
    load_membership
    render "developer_program_membership/new"
  end

  def create
    load_membership
    return render_404 if current_user.no_verified_emails?
    if @membership.update(membership_params)
      @membership.send_welcome_email
      redirect_to action: :show, account: @account
    else
      render "developer_program_membership/new"
    end
  end

  def show
    load_membership
    if T.must(@account).developer_program_member?
      render "developer_program_membership/show"
    else
      redirect_to action: :new, account: @account
    end
  end

  def update
    load_membership
    if @membership.update(membership_params)
      flash[:notice] = "Thanks for updating your Developer Program contact information!"
      redirect_to context_settings_path
    else
      redirect_to :back, flash: { error: @membership.errors.full_messages.to_sentence }
    end
  end

  def destroy
    load_membership.leave_program
    flash[:notice] = "You are no longer a part of the GitHub Developer Program. We're sorry to see you go!"
    redirect_to context_settings_path
  end

  private

  def load_membership
    @account    ||= T.let(load_account, T.nilable(User))
    @membership ||= @account.developer_program_membership ||
      @account.build_developer_program_membership
  end

  def membership_params
    keys = [:website, :support_email]
    params.slice(*keys).permit(*keys).to_h
      .merge(actor: current_user, user: load_account, active: true)
  end

  def redirect_if_no_account
    return unless request.get?
    return if params[:account]

    redirect_to action: :new, account: current_user
  end

  sig { returns(::User) }
  memoize def load_account
    T.must(find_account)
  end

  sig { returns(T.nilable(::User)) }
  def find_account
    account = params[:account] && User.find_by_login(params[:account])
    if account && adminable_accounts(include_businesses: false).include?(account)
      account
    else
      current_user
    end
  end
end
