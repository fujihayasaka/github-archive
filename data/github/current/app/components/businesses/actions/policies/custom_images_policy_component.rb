# typed: strict
# frozen_string_literal: true

class Businesses::Actions::Policies::CustomImagesPolicyComponent < ApplicationComponent

  include ::AvatarHelper

  sig { params(entity: Business, action: String, bulk_org_action: String).void }
  def initialize(entity:, action:, bulk_org_action:)
    @entity = entity
    @action = action
    @bulk_org_action = bulk_org_action
  end

  sig { returns(T::Boolean) }
  def render?
    true
  end

  sig { returns(T::Array[T::Hash[String, String]]) }
  def orgs_for_props
    @entity.organizations.map do |org|
      {
        id: org.id,
        name: org.name,
        primaryAvatarUrl: helpers.avatar_url_for(org),
        selected: org.custom_images_allowed_by_owner?,
      }
    end
  end
end
