# typed: true
# frozen_string_literal: true

module BillingSettings
  class SignupFormView
    include ErrorsHelper

    # Initiate a SignupFormView object used to control the signup form.
    # Typically used by the billing/signup_customer_form partial when rendering
    # https://github.com/signup.
    #
    # user        - optional User object.
    # coupon_code - optional String Coupon code.
    # users_path  - users route path as a String.
    #
    # Returns the new instance.
    def initialize(user, coupon_code, users_path)
      @user = user
      @coupon_code = coupon_code
      @users_path  = users_path
    end

    # The destination URL of the form.
    #
    # Returns a String URL pointing to UsersController#create.
    def form_url
      @users_path
    end

    ##
    # Flags determining what gets rendered on the signup form. Most of these
    # are for Enterprise.

    # Should we render a form title.
    #
    # Returns a Boolean.
    def show_title?
      GitHub.billing_enabled?
    end

    def title
      "Join GitHub"
    end

    # Should we render the Terms of Service message?
    #
    # Returns a Boolean.
    def show_tos?
      GitHub.billing_enabled?
    end

    # Was there any User validation errors?
    #
    # Returns a Boolean. Always false prior to submitting the form.
    def user_errors?
      @user && @user.errors.any?
    end

    # The error message to show the user.
    #
    # Returns a String. Defaults to a generic error if no error is on the base
    # of the model.
    def user_error_message
      if @user.errors[:base].any?
        @user.errors[:base].to_sentence.capitalize
      else
        "There were problems creating your account."
      end
    end

    # Whether the user error message mentions contacting a system
    # administrator or not.
    #
    # Returns true if there is an error message and it matches.
    def error_requires_sys_admin?
      return false if !user_errors?
      user_error_message =~ /system administrator/i
    end

    ##
    # Form input fields controls. Be very careful when changing these as the
    # backend code depends on the name attributes being set correctly.

    def username_field
      "user[login]"
    end

    def username_hint
      "This will be your username. You can add the name of your organization later."
    end

    def email_field
      "user[email]"
    end

    def email_error
      return unless @user && @user.errors

      if @user.errors[:emails].any?
        "Email is invalid or already taken"
      elsif @user.errors[:email].any?
        error_for(@user, :email)
      end
    end

    def password_field
      "user[password]"
    end

    def password_confirmation_field
      "user[password_confirmation]"
    end
  end
end
