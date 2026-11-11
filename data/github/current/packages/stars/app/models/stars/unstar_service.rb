# typed: true
# frozen_string_literal: true

module Stars
  # Public: Service object used by TreeController to unstar repositories. Handles required unstar confirmation
  # (if the repository is on any lists), the actual unstarring, and reporting DataDog stats.
  class UnstarService
    # inputs - Hash containing the following keys:
    # inputs[:repository] - Repository to be unstarred. Must be a repo that is visible to the user.
    # inputs[:actor] - User who is unstarring the repository.
    # inputs[:context] - String used to identify the source of the unstar request. Valid values may be found in
    #   the protobuf schema of the Hydro unstar event found at `lib/hydro/schemas/github/v1/repository_star_pb.rb`.
    # inputs[:confirm] - Boolean indicating if the user has accepted the unstar confirmation dialog.
    def self.call(**inputs)
      T.unsafe(self).new(**inputs).call
    end

    def initialize(repository:, actor:, context:, confirm:)
      @repository = repository
      @actor = actor
      @context = context
      @confirm = confirm
    end

    def call
      if !check_list_confirmation?
        return Result.unconfirmed(list_count: list_count)
      end

      if actor.unstar(repository, context: context)
        GitHub.dogstats.increment("star", tags: ["action:unstar"])
      end

      Result.success
    end

    private

    attr_reader :repository, :actor, :context

    def confirm?
      @confirm
    end

    def check_list_confirmation?
      confirm? || list_count.zero?
    end

    def list_count
      @list_count ||= actor.count_lists_with_item(repository)
    end

    class Result
      def self.success
        new(error_kind: nil)
      end

      def self.unconfirmed(list_count:)
        new(error_kind: :unconfirmed, list_count: list_count)
      end

      def initialize(error_kind:, list_count: nil)
        @error_kind = error_kind
        @list_count = list_count
      end

      # Public: Integer count of lists owned by the user that contain the repository, or nil if we didn't have to
      # query them (on success).
      attr_reader :list_count

      # Public: Symbol describing the encountered failure condition, or nil if the operation was successful. Valid
      # values are: nil, :unconfirmed.
      attr_reader :error_kind

      # Public: Did the unstarring operation succeed? True even if nothing was actually done (if the repository wasn't
      #   starred to begin with, for example).
      #
      # Returns a Boolean.
      def success?
        @error_kind.nil?
      end

      # Public: Was the unstarring operation not performed because the repository belongs to at least one UserList owned
      #   by the user? #list_count will be non-nil in this case.
      #
      # Returns a Boolean.
      def unconfirmed?
        @error_kind == :unconfirmed
      end
    end
  end
end
