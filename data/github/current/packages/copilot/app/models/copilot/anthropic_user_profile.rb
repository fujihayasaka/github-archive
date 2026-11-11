# typed: strict
# frozen_string_literal: true

module Copilot
  class AnthropicUserProfile < ApplicationRecord::Copilot
    ApiResponseValue = T.type_alias { T.any(String, T::Boolean, T::Hash[String, T::Boolean]) }

    self.table_name = "copilot_anthropic_user_profiles"
    self.strict_loading_by_default = true

    belongs_to :owner, polymorphic: true, strict_loading: false

    validates :owner_id, presence: true
    validates :owner_type, presence: true, inclusion: { in: %w[Business Organization User] }

    sig { params(owner: T.any(::Business, ::Organization, ::User)).returns(T.nilable(Copilot::AnthropicUserProfile)) }
    def self.for_owner(owner)
      find_by(owner_id: owner.id, owner_type: owner.class.name)
    end

    sig { params(body: T::Hash[String, ApiResponseValue]).void }
    def update_from_api_response!(body)
      profile_id = body["id"].to_s.presence
      returned_external_id = body["external_id"].to_s.presence
      trust_grants = body["trust_grants"]

      self.anthropic_id = profile_id if profile_id.present?
      self.external_id = returned_external_id if returned_external_id.present?
      self.grants = trust_grants.is_a?(Hash) ? trust_grants : nil

      save!
    end

    sig { returns(String) }
    def status
      return "requested" if grants.blank?

      cyber_preview_grant = if grants.is_a?(Hash)
        grants["cyber_preview"] || grants[:cyber_preview]
      end

      cyber_preview_grant ? "approved" : "not approved"
    end
  end
end
