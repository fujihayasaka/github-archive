# typed: true
# frozen_string_literal: true

module GitHub
  module LDAP
    # Class to add new users to the teams mapped to the groups they are member.
    class NewMemberSync
      # Reuse the error class from TeamSync.
      MemberAdditionError = GitHub::LDAP::TeamSync::MemberAdditionError

      # Public - Get the groups a user belongs to and map them to the teams she can be member of.
      #
      # user - is the github user.
      #
      # Returns nothing.
      def perform(user)
        return unless map = user.ldap_mapping

        map.sync do |_payload|
          LdapMapping.where(subject_type: "Team").includes(:subject).find_each do |team_mapping|
            if team_mapping.group_cache_member?(user.ldap_dn)
              team = team_mapping.subject

              response = team.add_member(user)

              if response.error?
                raise MemberAdditionError.new(team.id, user, response.status)
              end
            end
          end
        end
      end
    end
  end
end
