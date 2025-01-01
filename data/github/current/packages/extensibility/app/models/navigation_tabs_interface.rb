# typed: strict
# frozen_string_literal: true

module NavigationTabsInterface
  extend T::Helpers
  interface!

  sig { abstract.returns(T::Array[Site::Header::UnderlineNavTab]) }
  def tabs; end

  sig { abstract.returns(T.nilable(String)) }
  def tab_counts_url; end

  sig { abstract.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def popover; end
end
