# typed: strict
# frozen_string_literal: true

# Data source that wraps a User assigned to an issue or draft issue. This includes the user's profile name in addition
# to the standard user information.
class Assignee
  include MemexProjectColumn::IDataSource

  sig { returns(User) }
  attr_reader :user

  sig { returns(T::Boolean) }
  def include_name?
    @include_name
  end

  sig { params(user: User, include_name: T::Boolean).void }
  def initialize(user, include_name: false)
    @user = user
    @include_name = include_name
  end

  sig { override.returns(MemexProjectColumnValue::Assignee) }
  def memex_project_column_value
    profile_name = include_name? ? user.profile_name : nil
    MemexProjectColumnValue::Assignee.new(
      user_value: user.memex_project_column_value,
      profile_name: profile_name,
      include_name: include_name?,
    )
  end
end
