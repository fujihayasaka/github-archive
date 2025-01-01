# typed: strict
# frozen_string_literal: true

module Orca
  class Model < ApplicationRecord::Copilot
    extend T::Sig

    self.table_name = "orca_models"

    SEPARATOR = "."

    belongs_to :organization

    validates :deployment, length: { in: 0..255, allow_nil: false }
    validates :organization, presence: true
    validates :pipeline_id, length: { in: 0..255, allow_nil: false }, uniqueness: true
    validates :resource, length: { in: 0..255, allow_nil: false }

    sig { params(organization: Organization).returns(T.nilable(Orca::Model)) }
    def self.latest_for_organization(organization)
      order(created_at: :desc).find_by(organization: organization)
    end

    # Returns the list of custom models that the user has access to. Models
    # from a single org are sorted by the order they were created (newest
    # first). Models across multiple orgs are sorted by org ID for stable
    # ordering. Only the first custom model in this list is used for legacy
    # client, but modern clients can use any of them.
    sig { params(copilot_user: Copilot::User).returns(T::Array[Orca::Model]) }
    def self.custom_model_list(copilot_user)
      unless copilot_user.user_object.feature_enabled?(:copilot_custom_models_token)
        return []
      end

      Orca::Model
        .where(organization: copilot_user.copilot_organizations.uniq)
        .order(organization_id: :asc, created_at: :desc)
        .group_by(&:organization_id)
        .map { |_, models| T.must(models.first) }
    end

    sig { returns(String) }
    def resource_deployment
      "#{resource}#{SEPARATOR}#{deployment}"
    end
  end
end
