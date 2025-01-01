# typed: true
# frozen_string_literal: true

class Stafftools::PasswordsController < StafftoolsController

  before_action :ensure_user_exists

  # Send the user a password reset email
  #
  # email - Which address to send to.  Optional, if not passed the user's default email is used.
  def send_reset_email # rubocop:todo GitHub/UseRestfulActions
    reset = PasswordReset.create(
      user: this_user,
      email: params[:email],
      force: true,
      expires: 24.hours.from_now,
    )
    GlobalInstrumenter.instrument(
      "user.password_reset_create",
      {
        actor: current_user,
        account: reset.user,
        error_type: reset.error,
        email_address: params[:email],
      },
    )

    if reset.valid?
      if Rails.env.development? || Stafftools::AccessControl.authorized?(
        current_user,
        { controller: "Stafftools::TwoFactorCredentialsController", action: "destroy" })
        flash[:notice] = "Sent #{reset.email} a password reset link: #{reset.link}"
      else
        flash[:notice] = "Sent #{reset.email} a password reset link"
      end
    else
      flash[:error] = reset.error_message
    end
    redirect_to :back
  end

  # Scramble the user's password
  def randomize # rubocop:todo GitHub/UseRestfulActions
    this_user.set_random_password(actor: current_user)
    flash[:notice] = "Password randomized"
    redirect_to :back
  end
end
