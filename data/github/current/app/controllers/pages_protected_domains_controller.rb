# typed: true
# frozen_string_literal: true

class PagesProtectedDomainsController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  include PagesProtectedDomainsHelper

  before_action :login_required
  before_action :ensure_feature_enabled
  before_action :ensure_owner
  before_action :ensure_this_domain, except: [:new, :create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show]

  def new
    if current_pages_owner.is_a?(Organization)
      render "settings/organization/pages_protected_domains/new"
    else
      render "settings/user/pages_protected_domains/new"
    end
  end

  def create
    # Get and validate the domain name
    domain_name = (params.require(:page_protected_domain)[:name]).strip.downcase

    # Create new domain protection entry
    new_domain = Page::ProtectedDomain.new(name: domain_name, owner: current_pages_owner)

    # Save model or display validation errors
    if new_domain.save
      redirect_to_domain(new_domain)
    else
      error_messages = new_domain.errors.full_messages.map { |message| message.gsub(/\AName/, "Domain name") }
      flash[:pages_protected_domain_error] = error_messages
      new_domain_path = if current_pages_owner.organization?
        new_settings_org_pages_protected_domain_path
      else
        new_settings_pages_protected_domain_path
      end
      redirect_to(new_domain_path)
    end
  end

  def show
    if current_pages_owner.is_a?(Organization)
      render "settings/organization/pages_protected_domains/show", locals: {
        domain: this_domain,
      }
    else
      render "settings/user/pages_protected_domains/show", locals: {
        domain: this_domain,
      }
    end
  end

  def update
    if this_domain.verify
      flash[:pages_protected_domain_info] = "Successfully verified #{this_domain.name}"
      # TODO: trigger async reverification jobs of any other records for the same domain name
      redirect_to_pages_settings
    else
      flash[:pages_protected_domain_error] = this_domain.errors.full_messages
      redirect_to_domain(this_domain)
    end
  end

  def destroy
    maybe_destroyed = this_domain.destroy
    if maybe_destroyed.try(:destroyed?)
      flash[:pages_protected_domain_info] = "Verified domain #{maybe_destroyed.name} was deleted"
      # TODO: are there any verification jobs scheduled for this domain? cancel them there
    end
    redirect_to_pages_settings
  end

  private

  def ensure_feature_enabled
    render_404 unless pages_domain_protection_enabled?(user: current_user)
  end

  def target_for_conditional_access
    return current_pages_owner if %w(new create).include?(action_name)
    # Bypass CAP if this_domain is missing, but this is safe because ensure_this_domain will 404
    return :no_target_for_conditional_access unless this_domain # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_domain.owner
  end

  def this_domain # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @this_domain ||= Page::ProtectedDomain.find_by(name: params[:id], owner: current_pages_owner)
  end

  def ensure_this_domain
    render_404 unless this_domain.present?
  end

  def ensure_owner
    render_404 unless current_pages_owner
  end

  def redirect_to_pages_settings
    if current_pages_owner.organization?
      redirect_to settings_org_pages_path(current_pages_owner)
    else
      redirect_to settings_pages_path
    end
  end

  def redirect_to_domain(domain)
    if current_pages_owner.organization?
      redirect_to settings_org_pages_protected_domain_path(current_pages_owner, domain)
    else
      redirect_to settings_pages_protected_domain_path(domain)
    end
  end

end
