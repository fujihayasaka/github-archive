# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  class Group < T::Struct
    const :type, GroupType, default: GroupType::DIVIDER
    const :name, T.nilable(String)
    const :icon, T.nilable(Symbol)
    const :label, Label, default: Label::PUBLIC
    const :links, T::Array[T.any(EnterpriseNavigation::Link, EnterpriseNavigation::Group)]

    sig { returns(T::Array[EnterpriseNavigation::Link]) }
    def flat_links
      links.flat_map do |item|
        case item
        when EnterpriseNavigation::Group
          item.flat_links
        else
          item
        end
      end
    end
  end
end
