# typed: strict
# frozen_string_literal: true

class Businesses::RulesetAvailableOrgPropertiesController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  depends_on_clusters \
    ApplicationRecord::Authnd,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
  only: [:show]

  sig { void }
  def show
    descriptors = RepositoryRulesets::PropertyDescriptors.get_org_descriptors(this_business)

    payload = {
      properties: descriptors.map do |descriptor|
        {
          name: descriptor.property_name,
          description: descriptor.description,
          valueType: descriptor.value_type,
          allowedValues: descriptor.allowed_values,
          source: descriptor.source,
          icon: descriptor.icon,
          displayName: descriptor.display_name,
        }
      end
    }
    render json: payload
  end
end
