# typed: strict
# frozen_string_literal: true

class Repositories::AccessManagement::ChooseRoleComponent < ApplicationComponent

  sig { returns(T.any(User, Team)) }
  attr_reader :member

  sig { returns(Repository) }
  attr_reader :repository

  sig { params(member: T.any(User, Team), repository: Repository).void }
  def initialize(member:, repository:)
    @repository = repository
    @member = member
  end

  private

  sig { returns(T.nilable(String)) }
  def member_display_name
    case member
    when User
      user = T.cast(member, User)
      user.display_login || user.email
    when Team
      T.cast(member, Team).name
    end
  end

  sig { returns(String) }
  def member_param
    case member
    when User
      user = T.cast(member, User)
      user.persisted? ? "user/#{user.id}" : "user/#{user.email}"
    when Team
      team = T.cast(member, Team)
      "team/#{team.id}"
    end
  end
end
