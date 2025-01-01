# typed: strict
# frozen_string_literal: true

class Sponsors::Explore::SidebarComponent < ApplicationComponent
  include ReactHelper

  delegate :render_react_partial, :avatar_url_for, to: :helpers

  sig { params(filter_set: SponsorsExploreFilterSet).void }
  def initialize(filter_set:)
    @filter_set = filter_set
  end

  sig { returns String }
  def call
    content_tag(:div,
      class: "flex-order-1 flex-md-order-none py-6 pr-6 col-md-4 col-lg-3",
      **test_selector_data_hash("sponsors-explore-sidebar")
    ) do
      render_react_partial(
        name: "sponsors-explore-filter",
        ssr: true,
        props: {
           accounts: account_data,
           selectedAccount: filter_set.account_login || current_user&.display_login,
           ecosystems: ecosystems,
           selectedEcosystems: filter_set.ecosystems,
           orderings: orderings,
           selectedOrdering: filter_set.sort_by,
           directDependenciesOnly: filter_set.direct_dependencies_only?,
        },
      )
    end
  end

  private

  sig { returns SponsorsExploreFilterSet }
  attr_reader :filter_set

  sig { returns T::Boolean }
  def render?
    logged_in?
  end

  # Private: Accounts to explore as, ordered by relevance
  sig { returns T::Array[T.any(User, Organization)] }
  def accounts
    viewer = T.must_because(current_user) { "#render? checks presence" }
    orgs = T.cast(
      T.unsafe(Organization).ranked_for(
          current_user,
          scope: viewer.member_or_billing_manager_organizations
        )
        .limit(50).to_a,
      T::Array[Organization]
    )
    [viewer] + orgs
  end

  sig { returns T::Hash[String, { avatarUrl: String, isOrganization: T::Boolean }] }
  def account_data
    accounts.each_with_object({}) do |user, hash|
      hash[user.display_login] = { avatarUrl: avatar_url_for(user, 20), isOrganization: user.organization? }
    end
  end

  sig { returns T::Hash[String, { label: String }] }
  def ecosystems
    SponsorsExploreFilterSet::ECOSYSTEM_NAMES.each_with_object({}) do |(key, label), hash|
      hash[key] = { label: label } if key.present?
    end
  end

  sig { returns T::Hash[String, { label: String }] }
  def orderings
    SponsorsHelper::MAINTAINER_SORT_OPTIONS.each_with_object({}) do |(key, label), hash|
      hash[key] = { label: label } if key.present?
    end
  end
end
