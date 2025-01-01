# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  class Link < T::Struct
    const :link_name, String
    const :link_path, String
    const :highlight, T.nilable(T.any(Symbol, T::Array[Symbol]))
    const :icon, T.nilable(Symbol)
    const :label, Label, default: Label::PUBLIC
  end
end
