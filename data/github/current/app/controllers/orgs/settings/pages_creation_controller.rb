# typed: true
# frozen_string_literal: true

class Orgs::Settings::PagesCreationController < Orgs::Controller
  before_action :login_required
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    if current_organization.feature_flag_enabled?(:private_pages_org_toggle, default: false)
      # This is a transitionary step for orgs that have disabled pages and are now re-enabling it. https://github.com/github/pages-engineering/issues/366
      if !current_organization.members_can_create_pages? && (params[:create_public_pages_enabled] == "1" || params[:create_private_pages_enabled] == "1")
        current_organization.allow_members_to_create_pages(actor: current_user)
      end

      if params[:create_public_pages_enabled] == "1"
        current_organization.allow_members_to_create_public_pages(actor: current_user)
      else
        current_organization.block_members_from_creating_public_pages(actor: current_user)
      end

      if params[:create_private_pages_enabled] == "1"
        current_organization.allow_members_to_create_private_pages(actor: current_user)
      else
        current_organization.block_members_from_creating_private_pages(actor: current_user)
      end
    else
      if params[:create_pages_enabled] == "1"
        current_organization.allow_members_to_create_pages(actor: current_user)
      else
        current_organization.block_members_from_creating_pages(actor: current_user)
      end
    end

    redirect_to :back, notice: "Pages settings updated for this organization."
  end
end
