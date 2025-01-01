# typed: strict
# frozen_string_literal: true

module Statuses
  class Domain < GH::Domain::Base
    # Given a repository ID, returns true if there are any statuses for that repository.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @return [Boolean] True if there are statuses for the repository, false otherwise.
    sig { params(repository_id: T.nilable(Integer)).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def repository_has_statuses?(repository_id:)
      return false if repository_id.nil?
      Status.exists?(repository_id: repository_id)
    end

    # Given a repository ID and a list of SHAs, returns the current statuses for those SHAs.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param shas [Array<String>, nil] The SHAs to check for statuses.
    # @return [Array<Status>, nil] The current statuses for the given SHAs.
    sig { params(repository_id: T.nilable(Integer), shas: T::Array[String]).returns(T::Array[Status]).checked(:always).on_failure(:raise) }
    def current_statuses_for_shas(repository_id:, shas:)
      return [] if shas.empty? || repository_id.nil?

      subquery = Status.from("#{Status.table_name} FORCE INDEX(index_statuses_on_repository_id_and_sha_and_context)")
        .where(repository_id: repository_id, sha: shas)
        .group(:sha, :context)
        .select("MAX(`id`)")

      # Here, we embed the subquery we built above, but we want to make sure that the subquery
      # is executed before the outer query is. If the outer query is executed first, MySQL loads
      # _all_ statuses for the given `repository_id`, which does not perform well at all.
      # We employ a "double nesting" trick that forces the subquery to be materialized first.
      Status.where(repository_id: repository_id).where(id: Status.from(subquery).select("*")).order(:id).to_a
    end

    # Given a repository ID and a list of SHAs, returns the current statuses for those SHAs, grouped by SHA.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param shas [Array<String>, nil] The SHAs to check for statuses.
    # @return [Hash<String, Array<Status>>, nil] The current statuses for the given SHAs, grouped by SHA.
    sig { params(repository_id: T.nilable(Integer), shas: T::Array[String]).returns(T::Hash[String, T::Array[Status]]).checked(:always).on_failure(:raise) }
    def current_statuses_for_shas_group_by_sha(repository_id:, shas:)
      return {} if shas.empty? || repository_id.nil?

      statuses = current_statuses_for_shas(repository_id: repository_id, shas: shas)
      statuses.group_by(&:sha)
    end

    # Create a new status
    # @param repository [Repository, nil] The repository to create the status for.
    # @param sha [String, nil] The commit SHA.
    # @param state [String, nil] The state of the status (success, pending, failure, error, expected).
    # @param user [User, nil] The user to create the status for.
    # @param context [String, nil] The context for the status.
    # @param oauth_application_id [Integer, nil] The ID of the OAuth application that created the status (optional).
    # @param target_url [String, nil] The target URL for the status (optional).
    # @param description [String, nil] The description of the status (optional).
    # @return [GH::Result<Status>] The created status, or an error.
    sig { params(repository: T.nilable(Repository), sha: T.nilable(String), state: T.nilable(String), user: T.nilable(User), context: T.nilable(String), oauth_application_id: T.nilable(Integer), target_url: T.nilable(String), description: T.nilable(String)).returns(GH::Result[Status]).checked(:always).on_failure(:raise) }
    def create(repository: nil, sha: nil, state: nil, user: nil, context: nil, oauth_application_id: nil, target_url: nil, description: nil)
      # TODO: Repository, sha, state, and user are required. We should raise an error if they are not provided.
      # We are allowing them to be nil for now to avoid breaking changes to the API. And allow ActiveRecord to raise
      # an error if they are not provided.
      ActiveRecord::Base.connected_to(role: :writing) do
        # Create a hash of the attributes and compact it to remove any nil values. This is necessary because the
        # `create!` method does not accept nil values for optional attributes. Specifically the `context` attribute
        # is optional but the model does not allow nil values. This is a workaround for that limitation until we can fix
        # the model to allow nil values for optional attributes. Related issue: https://github.com/github/github/pull/36781
        status = Status.create!({ repository: repository, sha: sha, state: state, creator: user, context: context, oauth_application_id: oauth_application_id, target_url: target_url, description: description }.compact)
        GitHub.dogstats.increment("domain.statuses.create", tags: ["result:ok"])
        GH::Result::Ok.new(status)
      end

    rescue ActiveRecord::RecordInvalid => error
      GitHub.dogstats.increment("domain.statuses.create", tags: ["result:error"])
      GH::Result::Error.new(error.message)
    end
    # Given a repository ID, a SHA, and a timestamp, returns the statuses for that SHA that were created before a given timestamp.
    # @param repository_id [Integer] The repository ID to check for statuses.
    # @param sha [String] The SHA to check for statuses.
    # @param timestamp [Time] The timestamp to check for statuses.
    # @return [Array<Status>] The statuses for the given SHA that were created before the given timestamp.
    sig { params(repository_id: T.nilable(Integer), sha: String, timestamp: Time).returns(T::Array[Status]).checked(:always).on_failure(:raise) }
    def statuses_created_before_timestamp(repository_id:, sha:, timestamp:)
      return [] if repository_id.nil?

      subquery = Status.from("#{Status.table_name} FORCE INDEX (index_statuses_on_repository_id_and_sha_and_context)")
        .where(repository_id: repository_id, sha: sha)
        .where("created_at < :timestamp", timestamp: timestamp)
        .group(:sha, :context)
        .select("max(`id`)")

      # Here, we embed the subquery we build above, but we want to make sure that the subquery
      # is executed before the outer query is. If the outer query is executed first, MySQL loads
      # _all_ statuses for the given `repository_id`, which does not perform well at all.
      # We employ a "double nesting" trick that forces the subquery to be materialized first.
      Status.where(repository_id: repository_id).where(id: Status.from(subquery).select("*")).order(id: :desc).to_a
    end
  end
end
