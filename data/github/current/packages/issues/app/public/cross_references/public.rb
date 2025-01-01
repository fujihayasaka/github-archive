# typed: strict
# frozen_string_literal: true

module CrossReferences
  module Public
    extend self
    extend T::Sig

    include Kernel

    # Transfer all cross references from one actor (usually a mannequin) to another.
    sig { params(source_id: Integer, target_id: Integer).void }
    def transfer_to_actor(source_id, target_id)
      ::CrossReference.where(actor_id: source_id).update_all(actor_id: target_id)
    end
  end
end
