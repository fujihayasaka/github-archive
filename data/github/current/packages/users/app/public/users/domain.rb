# typed: strict
# frozen_string_literal: true

module Users
  class Domain < GH::Domain::Base

    # find a user by id
    sig { params(id: Integer).returns(T.nilable(IUser)) }
    def by_id(id)
      return nil if id <= 0

      ::User.find_by(id: id.to_i)
    end

    # find multiple users by id
    sig { params(ids: T::Array[T.nilable(Integer)]).returns(T::Array[IUser]) }
    def by_ids(ids)
      ::User.where(id: ids.uniq).to_a
    end

    # find a user by
    sig { params(login: String).returns(T.nilable(IUser)) }
    def by_login(login)
      return nil if login.blank?

      ::User.find_by(login:)
    end
  end
end
