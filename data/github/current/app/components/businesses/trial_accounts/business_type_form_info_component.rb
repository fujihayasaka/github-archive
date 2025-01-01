# typed: true
# frozen_string_literal: true

class Businesses::TrialAccounts::BusinessTypeFormInfoComponent < ApplicationComponent
  sig { returns(Symbol) }
  attr_reader :business_type

  sig { params(business_type: Symbol).void }
  def initialize(business_type:)
    @business_type = business_type
  end

  private

  sig { returns(T::Boolean) }
  def render?
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless current_user.feature_enabled?(:digital_front_door_ui_revamp)
    business_type == :default_managed || business_type == :enterprise_managed
  end

  sig { returns(String) }
  def default_managed_docs_url
    "#{GitHub.help_url}/admin/overview/about-github-enterprise-cloud"
  end

  sig { returns(String) }
  def enterprise_managed_docs_url
    "#{GitHub.help_url}/admin/managing-iam/understanding-iam-for-enterprises/about-enterprise-managed-users"
  end
end
