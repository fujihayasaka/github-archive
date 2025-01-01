# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  class Group < T::Struct
    const :type, GroupType, default: GroupType::DIVIDER
    const :name, T.nilable(String)
    const :icon, T.nilable(Symbol)
    const :label, Label, default: Label::PUBLIC
    const :links, T::Array[EnterpriseNavigation::Link]
  end
end
