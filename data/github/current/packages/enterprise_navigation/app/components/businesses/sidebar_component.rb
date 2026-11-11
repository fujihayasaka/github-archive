# typed: strict
# frozen_string_literal: true

class Businesses::SidebarComponent < ApplicationComponent

  sig { returns T.nilable(Business) }
  attr_reader :business

  sig { returns T.nilable(User) }
  attr_reader :user

  sig { returns T::Array[EnterpriseNavigation::Group] }
  attr_reader :groups

  sig { returns T.nilable(T.any(String, Symbol)) }
  attr_reader :selected_link

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig { returns String }
  attr_reader :title

  sig do
    params(
      user: T.nilable(User),
      business: T.nilable(Business),
      title: String,
      groups: T::Array[EnterpriseNavigation::Group],
      selected_link: T.nilable(T.any(String, Symbol)),
      system_arguments: Primer::SystemArgumentsValue).void
  end
  def initialize(user: nil, business: nil, title: "", groups: [], selected_link: nil, **system_arguments)
    @user = user
    @business = business
    @title = title
    @groups = T.let(groups.filter { |group| group.links.any? }, T::Array[EnterpriseNavigation::Group])
    @selected_link = selected_link
    @system_arguments = system_arguments
  end

  sig { returns T::Boolean }
  def render?
    return false unless business && user && groups
    true
  end

  sig { returns T::Array[EnterpriseNavigation::Link] }
  memoize def all_items
    groups.flat_map(&:links)
  end

  sig { returns T.nilable(Symbol) }
  memoize def selected_item
    Array(all_items.find { |item| link_selected?(item.link_path, selected_link: selected_link, highlight: item.highlight) }&.highlight).first
  end

  sig { params(group: EnterpriseNavigation::Group).returns(T::Boolean) }
  def group_has_divider?(group)
    return true if group.type == EnterpriseNavigation::GroupType::DIVIDER
    return true if group.type == EnterpriseNavigation::GroupType::FOLDING_WITH_DIVIDER
    false
  end

  sig { params(group: EnterpriseNavigation::Group).returns(T::Boolean) }
  def group_is_folding?(group)
    return true if group.type == EnterpriseNavigation::GroupType::FOLDING
    return true if group.type == EnterpriseNavigation::GroupType::FOLDING_WITH_DIVIDER
    false
  end

end
