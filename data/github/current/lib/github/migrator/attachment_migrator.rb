# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    # Collects attachments for all the other things that are being exported.
    class AttachmentMigrator
      def initialize(export:)
        @export = export
      end

      attr_reader :export

      # Public: Record that this model's attachments should be exported.
      def push(model)
        ids_by_class[model.class] << model.id
      end

      # Public: Finish adding the models' attachments to the export.
      def complete
        ids_by_class.each do |attachable_type, ids|
          find_each(attachable_type, ids) do |attachment|
            export.add(attachment)
            export.add(user_id: attachment.attacher_id)
          end
        end
        reset
      end

      private

      def reset
        @ids_by_class = nil
      end

      def ids_by_class
        @ids_by_class ||= Hash.new { |h, k| h[k] = [] }
      end

      def find_each(attachable_type, attachable_ids)
        scope = Attachment.includes(:asset)
        scope = scope.where(attachable_type: attachable_type)
        attachable_ids.each_slice(1000) do |ids|
          scope.where(attachable_id: ids).find_each do |attachment|
            yield attachment
          end
        end
      end

      # Like an AttachmentMigrator, but ignore everything.
      class Null
        def push(*);  end
        def complete; end
      end
    end
  end
end
