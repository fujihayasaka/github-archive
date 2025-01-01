# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class PackageEvent < UserMetadataEvent
          def skip?
            false
          end

          alias :users :actors
        end
      end
    end
  end
end
