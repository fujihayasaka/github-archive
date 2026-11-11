# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::ReviewRequests
  # Synchronizes the set of pending reviewers on a PullRequest in a single call.
  class ModifyReviewers
    # Parsed, validated representation of one input entry.
    class ReviewerInput < T::Struct
      const :reviewer_id, Integer
      const :is_team, T::Boolean
    end

    # Result types — pattern-matched by the caller.
    class Result
      extend T::Helpers
      abstract!
      sealed!
    end

    class Success < Result; end

    class InvalidPayload < Result
      sig { returns(String) }
      attr_reader :message

      sig { params(message: String).void }
      def initialize(message:)
        @message = message
        super()
      end
    end

    class NotFound < Result
      sig { returns(String) }
      attr_reader :message

      sig { params(message: String).void }
      def initialize(message:)
        @message = message
        super()
      end
    end

    class Failure < Result
      sig { returns(String) }
      attr_reader :message

      sig { params(message: String).void }
      def initialize(message:)
        @message = message
        super()
      end
    end

    sig do
      params(
        pull_request: ::PullRequest,
        actor: ::User,
        add_reviewers: T.untyped,
        remove_reviewers: T.untyped,
      ).returns(Result)
    end
    def self.call(pull_request:, actor:, add_reviewers:, remove_reviewers:)
      new(
        pull_request:,
        actor:,
        add_reviewers:,
        remove_reviewers:,
      ).call
    end

    sig do
      params(
        pull_request: ::PullRequest,
        actor: ::User,
        add_reviewers: T.untyped,
        remove_reviewers: T.untyped,
      ).void
    end
    def initialize(pull_request:, actor:, add_reviewers:, remove_reviewers:)
      @pull_request = pull_request
      @actor = actor
      @raw_add = add_reviewers
      @raw_remove = remove_reviewers
    end

    sig { returns(Result) }
    def call
      add_entries = parse_entries(@raw_add)
      remove_entries = parse_entries(@raw_remove)

      if add_entries.nil? || remove_entries.nil?
        return InvalidPayload.new(message: "Invalid reviewer payload.")
      end

      reviewers_to_add = resolve_reviewers(add_entries)
      if add_entries.any? && reviewers_to_add.size != add_entries.size
        return NotFound.new(message: "One or more reviewers to add could not be found.")
      end

      reviewers_to_remove = resolve_reviewers(remove_entries)
      if remove_entries.any? && reviewers_to_remove.size != remove_entries.size
        return NotFound.new(message: "One or more reviewers to remove could not be found.")
      end

      new_set = compute_new_reviewer_set(
        reviewers_to_add: reviewers_to_add,
        reviewers_to_remove: reviewers_to_remove,
      )

      if @pull_request.request_review_from(reviewers: new_set, actor: @actor)
        Success.new
      else
        Failure.new(message: @pull_request.errors.full_messages.to_sentence)
      end
    end

    # Parse raw input into validated `ReviewerInput` structs.
    sig { params(raw: T.untyped).returns(T.nilable(T::Array[ReviewerInput])) }
    def parse_entries(raw)
      return [] if raw.nil?
      return nil unless raw.respond_to?(:to_a)

      result = T.let([], T::Array[ReviewerInput])
      raw.to_a.each do |entry|
        parsed = parse_entry(entry)
        return nil if parsed.nil?
        result << parsed
      end
      result
    end

    private

    sig { params(entry: T.untyped).returns(T.nilable(ReviewerInput)) }
    def parse_entry(entry)
      hash = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry
      return nil unless hash.is_a?(Hash)

      id_value = hash["reviewerId"] || hash[:reviewerId]
      return nil if id_value.nil?

      id = T.let(Integer(id_value.to_s, exception: false), T.nilable(Integer))
      return nil if id.nil? || id <= 0

      is_team = hash["isTeam"] || hash[:isTeam]
      ReviewerInput.new(reviewer_id: id, is_team: !!is_team)
    end

    # Batched, ID-based lookup of User / Team records
    sig { params(entries: T::Array[ReviewerInput]).returns(T::Array[T.any(::User, ::Team)]) }
    def resolve_reviewers(entries)
      user_ids = entries.reject(&:is_team).map(&:reviewer_id).uniq
      team_ids = entries.select(&:is_team).map(&:reviewer_id).uniq

      users_by_id = user_ids.any? ? ::User.where(id: user_ids).index_by(&:id) : {}
      teams_by_id = team_ids.any? ? find_teams(team_ids) : {}

      entries.filter_map do |entry|
        if entry.is_team
          teams_by_id[entry.reviewer_id]
        else
          users_by_id[entry.reviewer_id]
        end
      end
    end

    sig { params(team_ids: T::Array[Integer]).returns(T::Hash[Integer, ::Team]) }
    def find_teams(team_ids)
      organization = @pull_request.repository&.organization
      return {} if organization.nil?

      ::Team.where(id: team_ids, organization_id: organization.id).index_by(&:id)
    end

    sig do
      params(
        reviewers_to_add: T::Array[T.any(::User, ::Team)],
        reviewers_to_remove: T::Array[T.any(::User, ::Team)],
      ).returns(T::Array[T.untyped])
    end
    def compute_new_reviewer_set(reviewers_to_add:, reviewers_to_remove:)
      organization = @pull_request.repository&.organization
      existing_pending = T.unsafe(@pull_request.review_requests).pending.reviewers(organization).to_a
      remove_keys = reviewers_to_remove.map { |r| reviewer_key(r) }

      kept = existing_pending.reject { |r| remove_keys.include?(reviewer_key(r)) }
      new_set = kept + reviewers_to_add
      new_set.uniq { |r| reviewer_key(r) }
    end

    # Helper function to ensure there isn't any duplicated reviewerId among team and user ids
    sig { params(reviewer: T.untyped).returns(String) }
    def reviewer_key(reviewer)
      "#{reviewer.class.name}:#{reviewer.id}"
    end
  end
end
