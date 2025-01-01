# typed: strict
# frozen_string_literal: true

module IRepositoryController
  extend T::Helpers
  extend T::Sig

  interface!

  sig { abstract.returns(T.nilable(Repository)) }
  def current_repository; end

  sig { abstract.returns(T.nilable(User)) }
  def owner; end
end
