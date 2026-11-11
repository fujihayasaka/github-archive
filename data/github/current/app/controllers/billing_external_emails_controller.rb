# typed: true
# frozen_string_literal: true

class BillingExternalEmailsController < ApplicationController
  include OrganizationsHelper

  before_action :ensure_billing_enabled
  before_action :ensure_target
  before_action :ensure_target_is_billable

  def create
    billing_email = params[:billing_external_email]

    begin
      new_email = target.billing_external_emails.create(email: billing_email)
      if new_email.save
        flash[:notice] = "Email #{billing_email} is now a billing recipient."
      elsif billing_email == target.billing_email
        flash[:error] = "Email '#{billing_email}' is already primary billing email."
      else
        flash[:error] = new_email.errors.full_messages.to_sentence
      end
    rescue ActiveRecord::RecordNotUnique
      flash[:error] = "Email '#{billing_email}' is already in the list of email recipients."
    end

    redirect_to settings_org_billing_path(target)
  end

  def delete # rubocop:todo GitHub/UseRestfulActions
    billing_email = target.billing_external_emails.find(params[:id])
    billing_email.destroy
    if target.save
      flash[:notice] = "Successfully removed from billing recipients."
    else
      flash[:error] = target.errors.full_messages.to_sentence
    end

    redirect_to settings_org_billing_path(target)
  end

  def mark_primary # rubocop:todo GitHub/UseRestfulActions
    billing_primary_old = target.billing_email
    ApplicationRecord::Domain::ConfigurationEntries.transaction do
      email_to_delete = target.billing_external_emails.find(params[:id])
      target.billing_email = email_to_delete.email
      email_to_delete.destroy
      target.billing_external_emails.create(email: billing_primary_old) unless billing_primary_old.nil?
      if target.save
        flash[:notice] = "Successfully marked as primary recipients."
      else
        flash[:error] = target.errors.full_messages.to_sentence
      end
    end

    redirect_to settings_org_billing_path(target)
  end

  def update_primary # rubocop:todo GitHub/UseRestfulActions
    email = params[:organization][:billing_email]

    target.billing_email = email
    if target.save
      flash[:notice] = "Successfully updated billing email for #{target.display_login}."
    else
      flash[:error] = target.errors.full_messages.to_sentence
    end

    redirect_to settings_org_billing_path(target)
  end

  private

  def ensure_target
    render_404 if params[:target] && target.nil?
  end

  def target # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @target ||= target!
  end

  def target!
    if params[:target] == "organization"
      org = current_organization_for_member_or_billing
      if org && org.billing_manageable_by?(current_user)
        org
      end
    end
  end

  def ensure_target_is_billable
    render_404 unless target.billable?
  end
end
