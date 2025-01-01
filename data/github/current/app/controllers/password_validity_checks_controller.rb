# typed: true
# frozen_string_literal: true

class PasswordValidityChecksController < ApplicationController

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def create
    user = User.new(password: params[:value])
    user.valid?
    password_errors = user.errors[:password]

    if password_errors.include?(User::PasswordDependency::TOO_SHORT_MESSAGE)
      render partial: "password_validity_checks/too_short",
        status: :unprocessable_entity
    elsif password_errors.include?(User::PasswordDependency::TOO_LONG_MESSAGE)
      render partial: "password_validity_checks/too_long",
        status: :unprocessable_entity
    elsif password_errors.include?(User::PasswordDependency::LOWERCASE_NEEDED_MESSAGE) ||
          password_errors.include?(User::PasswordDependency::NUMBER_NEEDED_MESSAGE)
      render partial: "password_validity_checks/needs_number_and_lowercase_letter",
        status: :unprocessable_entity
    elsif password_errors.include?(User::PasswordDependency::WEAK_PASSWORD_MESSAGE)
      render partial: "password_validity_checks/weak",
        status: :unprocessable_entity
    else
      render partial: "password_validity_checks/strong"
    end
  end
end
