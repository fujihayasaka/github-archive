# typed: strict
# frozen_string_literal: true

module IssueEvents
  module Public
    extend self
    extend T::Sig

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
  end
end
