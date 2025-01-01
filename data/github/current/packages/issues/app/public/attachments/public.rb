# typed: strict
# frozen_string_literal: true

module Attachments
  module Public
    extend self

    include Kernel

    # Transfer all attachments from one attacher (usually a mannequin) to another.
    sig { params(source_id: Integer, target_id: Integer).void }
    def transfer_to_attacher(source_id, target_id)
      ::Attachment.where(attacher_id: source_id).update_all(attacher_id: target_id)
    end
  end
end
