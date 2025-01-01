# typed: strict
# frozen_string_literal: true

# Components that inherit from this class have test coverage
# instead, since no view is associated with `BaseComponent`.
# rubocop:disable ViewComponent/ComponentsHaveUnitTests
class Closables::Buttons::BaseComponent < Closables::BaseComponent
  extend T::Sig

  private

  sig { returns(Reason) }
  memoize def default_option
    T.must(options.first)
  end

  sig { returns(String) }
  memoize def closable_name
    T.must(closable.class.name).downcase
  end
end
