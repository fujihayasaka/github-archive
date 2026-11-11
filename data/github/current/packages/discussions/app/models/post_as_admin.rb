# typed: true
# frozen_string_literal: true

# PostAsAdmin is an interface both describing and enforcing the contract for models
# that support the "post as admin" feature in Discussions.
#
# This interface is used to ensure that any model supporting the "post as admin"
# feature adheres to a consistent API, allowing for easier integration and
# management of posts made by admins on behalf of other users.
module PostAsAdmin
  extend T::Helpers

  interface!

  requires_ancestor { Kernel }

  sig { abstract.returns(T::Boolean) }
  def post_as_admin?; end

  sig { abstract.returns(T.nilable(User)) }
  def user; end

  sig { abstract.returns(T.nilable(Repository)) }
  def repository; end
end
