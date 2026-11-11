# typed: strict
# frozen_string_literal: true

module CrossReferences
  module Public
    TRANSFERABLE_BATCH_LIMIT = 100

    extend self

    # Transfer all cross references from one actor (usually a mannequin) to another.
    sig { params(source_id: Integer, target_id: Integer).void }
    def transfer_to_actor(source_id, target_id)
      if FeatureFlag.vexi.enabled?(:octoshift_mannequin_reclaiming_in_batches, default: false)
        ::CrossReference.where(actor_id: source_id).in_batches(of: TRANSFERABLE_BATCH_LIMIT) do |batch|
          ::CrossReference.throttle { batch.update_all(actor_id: target_id) }
        end
      else
        ::CrossReference.where(actor_id: source_id).update_all(actor_id: target_id)
      end
    end
  end
end
