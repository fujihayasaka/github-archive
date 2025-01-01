# typed: strict
# frozen_string_literal: true

module IssueEvents
  module Public
    extend self

    include Kernel

    sig { params(id: Integer, repository_id: Integer).returns(T.nilable(IssueEvent)) }
    def by_id(id, repository_id:)
      ::IssueEvent.find_by(id:, repository_id:)
    end

    # Transfer all issue events from one actor (usually a mannequin) to another.
    sig { params(source_id: Integer, target_id: Integer).void }
    def transfer_to_actor(source_id, target_id)
      ::IssueEvent.where(actor_id: source_id).update_all(actor_id: target_id)
    end

    # Export all issue events for a given repository.
    sig { params(pagination: GH::Pagination::Base, repository_id: Integer).returns(GH::Domain::Collection[IssueEvent]) }
    def for_export(pagination:, repository_id:)
      scope = ::IssueEvent.where(repository_id:)

      sorts = [
        # ascending, to avoid duplicates
        GH::Pagination::Sort.new(field: "created_at", direction: GH::Pagination::Sort::Direction::ASC),
        # by ID in the end, so that we can trust our order even in highly concurrent environments
        GH::Pagination::Sort.new(field: "id", direction: GH::Pagination::Sort::Direction::ASC),
      ]

      T.let(
        GH::Pagination::Paginator.paginate(
          scope:,
          pagination:,
          sorts:,
          lazy_total_entries: -> { scope.count }
        ),
        GH::Domain::Collection[IssueEvent]
      )
    end
  end
end
