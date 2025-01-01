# typed: strict

# frozen_string_literal: true

class Businesses::AdvancedSecurity::SuggestionFlow::BaseController < ::Businesses::AdvancedSecurity::SelfServeController
  before_action :ensure_billing_enabled
  before_action :ensure_recommendation_enabled
  before_action :ensure_self_serve_advanced_security

  private

  sig { returns(String) }
  def selected_orgs_key
    "organizations:#{this_business.id}:ghas_suggestion_flow"
  end

  sig { returns(String) }
  def selected_repos_key
    "repositories:#{this_business.id}:ghas_suggestion_flow"
  end

  sig { returns(String) }
  def selected_org_ids
    Billing::Kv.store.get(selected_orgs_key).value!
  end

  sig { void }
  def ensure_self_serve_advanced_security
    render_404 unless this_business.eligible_for_self_serve_advanced_security?
  end

  sig { void }
  def ensure_recommendation_enabled
    render_404 unless GitHub.flipper[:ghas_self_serve_recommendation].enabled?(this_business)
  end
end
