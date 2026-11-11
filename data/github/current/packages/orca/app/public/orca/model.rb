# typed: strict
# frozen_string_literal: true

module Orca
  class Model < ApplicationRecord::Copilot

    self.table_name = "orca_models"

    SEPARATOR = "."

    belongs_to :organization

    validates :deployment, length: { in: 0..255, allow_nil: false }
    validates :organization, presence: true
    validates :pipeline_id, length: { in: 0..255, allow_nil: false }, uniqueness: true
    validates :resource, length: { in: 0..255, allow_nil: false }

    sig { params(organizations: T::Array[Organization]).returns(T::Array[Orca::Model]) }
    def self.for_organizations(organizations)
      Orca::Model
        .where(organization: organizations)
        .order(organization_id: :asc, created_at: :desc)
        .group_by(&:organization_id)
        .map { |_, models| T.must(models.first) }
    end

    sig { returns(String) }
    def resource_deployment
      "#{resource}#{SEPARATOR}#{deployment}"
    end

    TargetForConditionalAccess = T.type_alias { T.any(T.nilable(Organization), Symbol) }

    sig { returns(TargetForConditionalAccess) }
    def target_for_conditional_access
      if organization&.feature_flag_enabled?(:copilot_custom_models_ip_cap_filter_organization, default: false)
        return organization
      end
      # CAP bypass is fine here if the flag is not enabled for the organization.
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end

    # Determines the target for conditional access for multiple Orca::Model instances
    #
    # models - an enumerable of Orca::Model
    #
    # returns Hash[Orca::Model] => organization
    sig { params(models: T::Array[Orca::Model]).returns(T::Hash[Orca::Model, TargetForConditionalAccess]) }
    def self.multiple_target_for_conditional_access(models)
      ConditionalAccess::Filter.ensure_with_class(models, Orca::Model)
      models.each_with_object({}) { |v, h| h[v] = v.target_for_conditional_access }
    end
  end
end
