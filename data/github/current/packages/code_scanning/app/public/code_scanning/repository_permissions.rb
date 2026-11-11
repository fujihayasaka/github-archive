# typed: strict
# frozen_string_literal: true

module CodeScanning
  include Kernel

  # CodeScanning::RepositoryPermissions is meant to be a centralised place for methods that check permissions
  # related to code scanning results for a repository.At the moment this is still missing some methods that need to be
  # moved to here.
  class RepositoryPermissions

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
    end

    # Public: Returns users from the input list that have code scanning write access to the repository.
    #
    # Note that this method does not raise errors but instead logs them and treats them as denials.
    sig { params(users: T::Enumerable[T.nilable(User)]).returns(T::Array[User]) }
    def filter_code_scanning_writable_by(users)
      results = allowed_multi(:write_code_scanning, users)
      results.select { |_, allowed| allowed }.map(&:first).compact
    end

    private

    # allowed_multi checks authorization for multiple users in parallel. It returns an array of [user, allowed?] pairs.
    # An error during authorization lookup is logged but not raised.
    sig { params(action: Symbol, users: T::Enumerable[T.nilable(User)]).returns(T::Array[[T.nilable(User), T::Boolean]]) }
    def allowed_multi(action, users)
      promised_responses = users.map do |user|
        if user
          Platform::Loaders::Permissions::BatchAuthorize.load(
            action: action,
            actor: user,
            subject: @repo,
            )
        else
          Promise.resolve(Authzd::DENY)
        end
      end

      responses = Promise.all(promised_responses).sync
      pairs = users.zip(responses)

      # Collect errors and log only a single one
      error_counts = {}
      error_user_ids = []
      pairs.filter { |p| p[1].error? }.each do |p|
        error_counts[p[1].error] = (error_counts[p[1].error] || 0) + 1
        error_user_ids << p[0]&.id
      end
      if !error_counts.empty?
        msg = String.new("Error(s) for multiple auth lookups: ")
        error_counts.each do |error, count|
          msg << "#{count}x: #{error} "
        end
        error = StandardError.new(msg)
        error.set_backtrace(caller)
        Failbot.report(error,
                      "gh.code_scanning.authz_action": action,
                      "gh.repo.id": @repo.id,
                      "gh.actor.ids": error_user_ids)
      end

      # Finally return user/allow? pairs
      users.zip(responses.map { |r| r.allow? })
    end
  end
end
