# typed: strict
# frozen_string_literal: true

class Stafftools::Users::InvitationsController < StafftoolsController
  extend T::Sig

  before_action :enterprise_required
  before_action :ensure_user_invites_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:new]

  sig { void }
  def new
    render "stafftools/users/invitations/new", locals: { new_user: User.new }
  end

  sig { void }
  def create
    user_params[:login].strip!
    user_params[:email].strip!
    new_user = User.new(user_params)
    new_user.password = generated_password
    new_user.password_confirmation = generated_password
    new_user.plan = GitHub::Plan::ENTERPRISE

    if new_user.save
      reset = PasswordReset.new(
        user: new_user,
        email: new_user.email,
        force: true,
        expires: 24.hours.from_now,
      )

      if reset.valid?
        if GitHub.smtp_enabled?
          flash.now[:notice] = "Account created for #{new_user.login}. Email sent to "\
            "#{new_user.email}"
          EnterpriseMailer.invite_user(new_user, reset.link, reset.expires.to_s).deliver_later
        else
          flash.now[:notice] = "Account created for #{new_user.login}. This password reset link "\
            "must be manually sent to the new user: #{reset.link}"
        end
      else
        flash.now[:error] = reset.error_message
      end

      new_user = User.new
    else
      flash.now[:error] = "Could not invite user."
    end

    render "stafftools/users/invitations/new", locals: { new_user: new_user }
  end

  private

  sig { void }
  def ensure_user_invites_enabled
    render_404 unless GitHub.user_invites_enabled?
  end

  sig { returns(ActionController::Parameters) }
  def user_params
    params.require(:user).permit(:login, :email)
  end

  sig { returns(String) }
  def generated_password # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_generated_password ||= T.let(SecureRandom.hex(20), T.nilable(String))
  end
end
