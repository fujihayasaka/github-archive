# typed: true
# frozen_string_literal: true

class Stafftools::CopilotByokController < StafftoolsController
  depends_on_clusters ApplicationRecord::Authnd,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    only: [:index]

  before_action :dotcom_required

  sig { void }
  def index
    query = params[:query].to_s.strip
    results = lookup_byok_info(query) if query.present?

    render "stafftools/copilot_byok/index", locals: {
      query: query,
      results: results,
    }
  end

  private

  sig { params(query: String).returns(T::Hash[Symbol, T.untyped]) }
  def lookup_byok_info(query)
    org = Organization.find_by(login: query)
    user = org ? nil : User.find_by(login: query)
    business = Business.find_by(slug: query)

    results = {}

    if org
      results[:organization] = build_org_byok_info(org)
    elsif user
      results[:user] = build_user_byok_info(user)
    end

    if business
      results[:enterprise] = build_enterprise_byok_info(business)
    end

    results
  end

  sig { params(user: User).returns(T::Hash[Symbol, T.untyped]) }
  def build_user_byok_info(user)
    copilot_user = Copilot::User.new(user)
    custom_models = copilot_user.byok_custom_models.to_a
    ActiveRecord::Associations::Preloader.new(records: custom_models, associations: [:custom_key, :organization, :business, :capability]).call

    orgs = copilot_user.copilot_organizations.map(&:organization_object)
    ActiveRecord::Associations::Preloader.new(records: orgs, associations: :business).call
    org_byok_statuses = orgs.map do |o|
      { org: o, enabled: o.copilot_custom_models_enabled? }
    end

    {
      user: user,
      custom_models: custom_models,
      org_byok_statuses: org_byok_statuses,
    }
  end

  sig { params(org: Organization).returns(T::Hash[Symbol, T.untyped]) }
  def build_org_byok_info(org)
    custom_models = org.enabled_custom_models.to_a
    ActiveRecord::Associations::Preloader.new(records: custom_models, associations: [:custom_key, :capability]).call

    {
      org: org,
      enabled: org.copilot_custom_models_enabled?,
      custom_models: custom_models,
      custom_keys: custom_models.map(&:custom_key).compact.uniq,
      business: org.business,
      business_enabled: org.business&.copilot_custom_models_enabled?,
    }
  end

  sig { params(business: Business).returns(T::Hash[Symbol, T.untyped]) }
  def build_enterprise_byok_info(business)
    {
      business: business,
      enabled: business.copilot_custom_models_enabled?,
      custom_models: business.copilot_custom_models.includes(:custom_key, :capability).to_a,
      custom_keys: business.copilot_custom_keys.to_a,
    }
  end
end
