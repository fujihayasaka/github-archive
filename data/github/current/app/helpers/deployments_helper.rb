# typed: true
# frozen_string_literal: true

module DeploymentsHelper
  extend T::Helpers

  include GitHub::Memoizer

  abstract!

  # TODO: This should be T.nilable(::User) but sorbet complains about 20+ files that then need to be fixed
  # Since the parent class returns T.untyped, this matches the signature there for now
  sig { abstract.returns(T.untyped) }
  def current_user; end
end
