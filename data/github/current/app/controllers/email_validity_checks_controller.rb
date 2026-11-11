# typed: true
# frozen_string_literal: true

class EmailValidityChecksController < ApplicationController
  set_statsd_sample_rate 0.01, only: :create

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def create
    email = params[:value].to_s
    # Sanitize null bytes to prevent validation failures and ArgumentError
    email = email.delete("\u0000")
    user = User.new(email: email)
    spellcheck_suggestion = EmailSpellchecker.suggestion_for(email)

    if !user.valid? && (email.blank? || user.errors[:emails].any?)
      if user.errors.where(:email, :sanctioned_email).any?
        return render partial: "email_validity_checks/sanctioned",
          status: :unprocessable_entity,
          locals: { spellcheck_suggestion: spellcheck_suggestion }
      elsif user.errors.where(:email, :disposable_email).any?
        return render partial: "email_validity_checks/disposable",
          status: :unprocessable_entity,
          locals: { spellcheck_suggestion: spellcheck_suggestion }
      elsif user.errors.where(:email, :reserved_domain).any?
        reserved_message = UserEmail::ReservedEmailDomainDependency.extract_reserved_error_message(user.errors)
        return render partial: "email_validity_checks/reserved_domains",
          status: :unprocessable_entity,
          locals: { spellcheck_suggestion: spellcheck_suggestion, message: reserved_message }
      elsif user.errors.where(:email, :taken).any? && !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?
        return render partial: "email_validity_checks/taken",
          status: :unprocessable_entity
      elsif user.emails.first&.errors&.where(:email, :claimed_email)&.any?
        return render partial: "email_validity_checks/claimed",
          status: :unprocessable_entity,
          locals: { spellcheck_suggestion: spellcheck_suggestion }
      end

      return render partial: "email_validity_checks/invalid_or_taken",
        status: :unprocessable_entity,
        locals: { spellcheck_suggestion: spellcheck_suggestion }
    end

    render partial: "email_validity_checks/available",
      locals: { spellcheck_suggestion: spellcheck_suggestion }
  end
end
