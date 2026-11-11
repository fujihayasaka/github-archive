# typed: strict
# frozen_string_literal: true

module Attachments
  module Public
    TRANSFERABLE_BATCH_LIMIT = 100

    extend self

    # Transfer all attachments from one attacher (usually a mannequin) to another.
    sig { params(source_id: Integer, target_id: Integer).void }
    def transfer_to_attacher(source_id, target_id)
      if FeatureFlag.vexi.enabled?(:octoshift_mannequin_reclaiming_in_batches, default: false)
        ::Attachment.where(attacher_id: source_id).in_batches(of: TRANSFERABLE_BATCH_LIMIT) do |batch|
          ::Attachment.throttle { batch.update_all(attacher_id: target_id) }
        end
      else
        ::Attachment.where(attacher_id: source_id).update_all(attacher_id: target_id)
      end
    end
  end
end
