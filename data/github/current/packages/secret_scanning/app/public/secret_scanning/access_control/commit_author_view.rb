# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::AccessControl
  class CommitAuthorView
    extend T::Sig

    sig { params(repository: Repository).void }
    def initialize(repository)
      @repository = repository
    end

    sig { params(user: User).returns(T::Boolean) }
    def has_access_to_repository?(user)
      return true if @repository.adminable_by?(user)

      return false if @repository.owner.nil?
      owner = T.must(@repository.owner)

      if owner.organization?
        owner = T.cast(owner, Organization)
        return true if owner.member?(user)
        return true if owner.user_is_outside_collaborator?(user.id, [@repository.id])
      elsif owner.user?
        return true if @repository.member?(user)
      end

      false
    end
  end
end
