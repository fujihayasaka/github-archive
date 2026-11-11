# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class SponsorshipEvent < UserMetadataEvent
          attr_reader :linked_org_id

          def skip?
            false
          end

          def users
            with_read do
              users = User.where(id: [sponsor_id, sponsorable_id]).index_by(&:id)

              sponsor = users[sponsor_id]
              if sponsor&.organization? && linked_org = sponsor.sponsoring_linked_organization
                @linked_org_id = linked_org.id
                users[@linked_org_id] = linked_org
              end

              users.values
            end
          end

          def user_is_sponsor?(user)
            user.id == sponsor_id || user.id == linked_org_id
          end

          def user_is_sponsorable?(user)
            user.id == sponsorable_id
          end

          private

          def sponsor_id
            message.value.dig(:sponsorship, :sponsor, :id) || message.value.dig(:actor, :id)
          end

          def sponsorable_id
            message.value.dig(:listing, :sponsorable_id)
          end
        end
      end
    end
  end
end
