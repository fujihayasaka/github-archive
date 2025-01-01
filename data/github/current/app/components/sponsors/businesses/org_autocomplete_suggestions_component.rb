# typed: true
# frozen_string_literal: true

class Sponsors::Businesses::OrgAutocompleteSuggestionsComponent < ApplicationComponent
  include AvatarHelper

  sig { params(business: Business, actor: User, query: String).void }
  def initialize(business:, actor:, query:)
    @business = business
    @actor = actor
    @query = query
  end

  private

  attr_reader :business, :actor, :query

  sig { returns(ActiveRecord::Relation) }
  memoize def suggestions
    orgs = business.organizations.with_prefix("login", query).limit(10)
    GitHub::PrefillAssociations.prefill_associations(orgs, :profile)
    orgs
  end

  sig { returns(T::Boolean) }
  def render?
    suggestions.present?
  end
end
