# typed: true
# frozen_string_literal: true

class Orgs::Settings::RepositoryCreationController < Orgs::Controller
  before_action :login_required
  before_action :check_trade_compliance
  before_action :org_members_only
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    enabled = current_organization.allow_members_can_create_repositories_with_visibilities(actor: current_user,
      public_visibility: public_creation_allowed?,
      private_visibility: org_hash[:members_can_create_private_repositories] == "1",
      internal_visibility: org_hash[:members_can_create_internal_repositories] == "1")
    notice = if enabled.length > 0
      "Members can now create #{to_sentence(enabled)} repositories."
    else
      "Members can no longer create #{available_repo_types_to_sentence("or")} repositories."
    end

    redirect_to :back, notice: notice
  end

  private

  def public_creation_allowed?
    # Ensure we set a valid value, preventing private-only policies for free/team orgs
    # regardless of any client-side shenanigans.
    if current_organization.can_restrict_only_public_repo_creation?
      org_hash[:members_can_create_public_repositories] == "1"
    else
      org_hash[:members_can_create_public_repositories] == "1" || org_hash[:members_can_create_private_repositories] == "1"
    end
  end

  def available_repo_types_to_sentence(conjunction = "and")
    types = %w[public private]
    types.append("internal") if current_organization.supports_internal_repositories?
    to_sentence(types, conjunction)
  end

  def to_sentence(items, conjunction = "and")
    return items.first if items.length == 1
    list = items[0..-2].join(", ")
    list += "," if items.length > 2 # Oxford commas keep it classy
    list += " #{conjunction} "
    list += items.last
  end
end
