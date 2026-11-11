# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Helpers::Repository
  class Payload
    class Owner < T::Struct
      const :id, String
      const :login, String
      const :url, String
    end

    class Repository < T::Struct
      const :id, String
      const :isPrivate, T::Boolean
      const :name, String
      const :owner, Owner
    end

    sig { params(repository: T.nilable(::Repository)).returns(T.nilable(Repository)) }
    def self.build_repository(repository)
      return unless repository

      owner = repository.owner
      return unless owner

      Repository.new(
        id: repository.id.to_s,
        isPrivate: repository.private?,
        name: repository.name,
        owner: Owner.new(
          id: owner.id.to_s,
          login: owner.display_login,
          url: owner.async_url.to_s
        )
      )
    end
  end
end
