# typed: strict
# frozen_string_literal: true

module GH
  class DualWriter
    class Handler
      # Handles dual-write create operations by upserting the subject's
      # attributes into the secondary class.
      class Create < Handler
        sig { override.params(subject: ActiveRecord::Base).void }
        def perform_secondary_write(subject)
          secondary_class.upsert(subject.attributes)
        end
      end
    end
  end
end
