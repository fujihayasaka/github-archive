# typed: true
# frozen_string_literal: true

# This component is used for rendering a single domain and its menu with
# associated actions, in a list of domains owned by an enterprise or org.
class VerifiableDomains::DomainComponent < ApplicationComponent
  include VerifiableDomainsHelper
  # `owner` is the Business or Organization that is the owner of the page where
  # the VerifiableDomain (`domain`) is being listed.
  attr_reader :owner, :domain

  def initialize(owner:, domain:)
    @owner = owner
    @domain = domain
  end

  def show_enterprise_label?
    domain.owner.is_a?(Business) && owner != domain.owner
  end

  memoize def available_actions
    @available_actions = []
    if domain.owner == owner
      unless domain.verified?
        @available_actions << :verify
        @available_actions << :approve unless domain.approved?
      end
      if need_policy_checks?(domain) && domain.required_for_policy_enforcement?
        @available_actions << :delete_warn
      elsif need_policy_checks?(domain) && domain.maybe_required_for_org_policy_enforcement?
        @available_actions << :children_warn
      else
        @available_actions << :delete
      end
    else
      @available_actions << :enterprise_admin if domain.owner.adminable_by?(current_user)
    end

    @available_actions
  end

  def action_available?(action)
    available_actions.include?(action)
  end

  def owner_domain_path_for_action(action:)
    helpers.owner_domain_path_for_action(action: action, owner: owner, domain: domain)
  end

  memoize def owner_email_eligible_domains_count
    owner.verifiable_domains.verified_or_approved.count
  end

  def need_policy_checks?(domain)
    domain.eligible_for_emails? && owner_email_eligible_domains_count == 1
  end
end
