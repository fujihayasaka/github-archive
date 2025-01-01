# typed: false
# frozen_string_literal: true

module GitHub
  module LDAP
    # Synchronize a Team's memberships with the LDAP Group the Team is mapped
    # to.
    #
    # Syncing first searches for all the members of the LDAP Group, including
    # members of subgroups. Once we have a list of all of the members, we can
    # find the Users those members map to. With that list of User records, we
    # can add new members to the Team, or remove members that are no longer
    # members of the LDAP Group.
    #
    # If the LDAP Group the Team is mapped to is removed, the Team is also
    # removed.
    class TeamSync
      include GitHub::LDAP::Instrumentable

      class SyncError < StandardError; end

      class LdapError < SyncError
        attr_reader :op, :dn, :result

        def initialize(op, dn, result)
          @op     = op
          @dn     = dn
          @result = result
        end

        def error_message
          @error ||= begin
            msg = result.message
            msg = "#{msg}: #{result.error_message}" if result.error_message.present?
            msg
          end
        end

        def message
          "LDAP operation error (#{result.code}) encountered at #{op} (#{dn}): #{error_message}"
        end

        def payload
          { op: op, dn: dn, code: result.code, result: result }
        end
      end

      class MemberAdditionError < SyncError
        attr_reader :team_id, :user, :error

        def initialize(team, user, error)
          @team = team_id
          @user = user
          @error = error
        end

        def message
          "error adding `#{user.login}` to the team id `#{team_id}`: #{error}"
        end

        def payload
          { team_id: team_id, user: user, error: error }
        end
      end

      # Public: Synchronize all Teams mapped to the same LDAP Group.
      #
      # The LDAP Group is the cannonical source of membership. Adding members
      # to the LDAP Group results in them being added to synced Teams, and
      # removing them from the LDAP Group conversely removes them from Teams.
      #
      # dn: the Distinguished Name (DN) String one or more Teams are mapped to.
      #
      # The DN String must map to at least one Team subject.
      #
      # To reconcile membership, we first perform a *member search* for the
      # given LDAP Group. This uses the `GitHub::Ldap::MemberSearch` strategy
      # to find all members of the group, including members of subgroups.
      #
      # Sync targets *all* LdapMapping subjects that share the DN passed in.
      # This reduces the number of duplicate LDAP searches since all of the
      # Teams will have the same memberships.
      #
      # If the LDAP Group is removed (or moved) and the Team's mapping doesn't
      # resolve to an LDAP Group, all Team members are removed and an error
      # message will be displayed on the Team's Stafftools page.
      #
      # Emits event `tteam_sync.member_search` with:
      #  :dn - the LDAP entry Distinguished Name (DN) mapped to
      #
      # Returns nothing.
      def perform(dn)
        group   = nil
        members = []

        start = Time.now # track member search runtime

        # Optimization: open and use a persistent LDAP connection to pull the
        # mapped LDAP Group entry and its member entries.
        GitHub.instrument "team_sync.member_search", dn: dn do |payload|
          ldap.strategy.open do
            ldap_fail! :team_sync_bind, dn if fatal_ldap_error?

            # search for mapped LDAP Group entry
            if group = find_group(dn)
              # search for members of the LDAP Group entry
              # NOTE: this is network intensive operation
              members = member_search_strategy.perform(group)
              payload[:result_count] = members.try(:count)

              ldap_fail! :member_search, dn if fatal_ldap_error?
            else
              ldap_fail! :group_search, dn if fatal_ldap_error?
            end
          end
        end
        member_search_ms = (Time.now - start) * 1000

        # Lookup LDAP Group members with accounts and cache the Users as a Hash, keyed by DN
        group_members_dn = members.map { |member| member.dn.downcase }
        group_member_users = User.find_by_ldap_mappings(*group_members_dn)
        group_member_accounts = group_member_users.index_by { |user| LdapMapping.hash_dn(user.ldap_dn) }

        # NOTE: this caches the LDAP Group's members, including members from
        # its subgroups, solely for use by the NewMemberSync job.
        map = LdapMapping.by_dn(dn).where(subject_type: "Team").limit(1).first
        map.group_cache_set_members(group_members_dn) unless map.nil?

        # Find all IDs for Teams mapped to the LDAP Group by DN.
        team_ids = LdapMapping.by_dn(dn).where(subject_type: "Team").pluck(:subject_id)

        # Find all Teams mapped to the LDAP Group by DN, using the IDs.
        teams = Team.where(id: team_ids).includes(:ldap_mapping)

        # NOTE: see https://github.com/rails/rails/issues/950 for why
        #       LdapMapping.by_dn(dn).includes(:subject) could fail
        #       with a DN like `cn=group.name`.

        teams.each do |team|
          # the Team record's LDAP Mapping record to sync with
          map = team.ldap_mapping

          # Retrieve all the team members and remove any without a mapping
          mapped_members, non_mapped_members =
            team.members.includes(:ldap_mapping).partition { |member| member.ldap_mapped? }
          non_mapped_members.each { |member| remove_member_from_team(team, member) }

          # Collect Team members as a Hash, keyed by DN.
          # Ideally this will be identical to other teams mapped to the same
          # LDAP group, but this makes sure.
          team_members = mapped_members.index_by { |member| LdapMapping.hash_dn(member.ldap_dn) }

          map.sync add_runtime: member_search_ms do |payload|
            payload[:team_id]   = team.id
            payload[:team_name] = team.name

            if group
              payload[:entry_found] = true

              # reconcile Team members against the LDAP Group members with accounts
              remove_non_members(team, team_members, group_member_accounts)
              add_new_members(team, team_members, group_member_accounts)
            else
              payload[:entry_found] = false

              # remove all members from the team
              remove_non_members(team, team_members, {})

              # signal that the entry was missing and sync was not possible
              raise LdapMapping::MissingEntryError
            end

            # signal to LdapMapping if it should log activity about this sync
            payload[:ldap_fields_changed] = ldap_fields_changed
          end

          # Restore any user forks if team gains access to the original repo
          #
          # Teams may be granted access to repos after a sync is performed.
          # The subsequent sync will restore forks.
          #
          Restorable::LdapTeamSyncUser.team_restorables(team).each(&:restore)
        end
      rescue SyncError => error
        Failbot.report! error, error.payload
      end

      # Internal: Look up the LDAP Group by the String DN.
      def find_group(dn)
        ldap.strategy.domain(dn).bind
      end
      private :find_group

      # Internal: The member search strategy object used to find group members.
      #
      # Returns a `GitHub::Ldap::MemberSearch` strategy object.
      def member_search_strategy
        @member_search_strategy ||=
          ldap.strategy.member_search_strategy.new ldap.strategy,
            depth: GitHub.ldap_search_strategy_depth
      end
      private :member_search_strategy

      # Internal: Remove Team members that are not in the LDAP Group.
      #
      # team:          the Team object to be reconciled.
      # team_members:  Hash of the Team's member Users, keyed by DN hash
      # group_members: Hash of the Users mapped to the LDAP Group, keyed by DN hash.
      #
      # Returns nothing.
      def remove_non_members(team, team_members, group_members)
        team_member_dns  = team_members.keys
        group_member_dns = group_members.keys

        # remove any Team members if their DN isn't listed as a Group member
        to_remove = team_member_dns - group_member_dns

        to_remove.each do |dn_hash|
          user = team_members[dn_hash]
          # Removing can destroy forks, so only remove if dn matches LDAP
          entry = GitHub::LDAP::UserSync.new.find_ldap_entry(user)
          if entry.nil? || LdapMapping.hash_dn(entry.dn) == dn_hash
            remove_member_from_team(team, user)
            log_ldap_sync!("removed_non_members")
          end
        end
      end
      private :remove_non_members

      # Internal: Remove a user from a team after marking any private forks
      # as restorable.
      #
      # team:   Team to remove the member from.
      # user:   User to remove.
      #
      # Returns nothing.
      def remove_member_from_team(team, user)
        restorable = Restorable::LdapTeamSyncUser.start(team, user)
        restorable.save_user_forks
        team.remove_member(user, force: true)

        org = team.organization
        if org.teams_for(user).empty? && !org.adminable_by?(user)
          org.remove_member(user)
        end
      end
      private :remove_member_from_team

      # Internal: Add missing Team members that are in the LDAP Group.
      #
      # team:          the Team to be reconciled.
      # team_members:  Hash of the Team's member Users, keyed by DN.
      # group_members: Hash of the of Users mapped to the LDAP Group, keyed by DN.
      #
      # Returns nothing.
      def add_new_members(team, team_members, group_members)
        team_member_dns  = team_members.keys
        group_member_dns = group_members.keys

        # add any Users if their DN is listed as a Group member and isn't
        # currently a Team member

        dns_to_add = group_member_dns - team_member_dns

        dns_to_add.each do |user|
          response = team.add_member(group_members[user])

          if response.error?
            GitHub::Authentication::LDAPSync.logger.error(
              "Team sync: add_member error",
              "code.namespace" => "GitHub::LDAP::TeamSync",
              "code.function" => "add_new_members",
              "ldap.dn" => user,
              "gh.team.ability_description" => team.ability_description,
              "exception.message" => response.status,
              "gh.user.login" => group_members[user].login
            )
          else
            log_ldap_sync!("added_new_members")
          end
        end
      end
      private :add_new_members

      # Internal: Returns the GitHub::Authentication::LDAP adaptor object.
      def ldap
        GitHub.auth
      end

      FATAL_LDAP_ERRORS = [
        Net::LDAP::ResultCodeOperationsError,
        Net::LDAP::ResultCodeProtocolError,
        Net::LDAP::ResultCodeTimeLimitExceeded,
        Net::LDAP::ResultCodeSizeLimitExceeded,
        Net::LDAP::ResultCodeInvalidCredentials,
        Net::LDAP::ResultCodeInsufficientAccessRights,
        Net::LDAP::ResultCodeUnavailable,
        Net::LDAP::ResultCodeUnwillingToPerform,
        Net::LDAP::ResultCodeOther,
      ]

      # Internal: Check if there was a fatal error with the last LDAP operation.
      def fatal_ldap_error?
        FATAL_LDAP_ERRORS.include?(ldap.strategy.last_operation_result.code)
      end
      private :fatal_ldap_error?

      # Internal: Raise an LdapError with relevant operation, DN, and operation
      # result. Handled and logged in `perform`.
      def ldap_fail!(op, dn)
        result = ldap.strategy.last_operation_result
        GitHub::Authentication::LDAP.logger.error(
          "Sync aborted: fata LDAP error",
          "code.namespace" => "GitHub::LDAP",
          "code.function" => "perform",
          "code.op" => op,
          "ldap.dn" => dn,
          "ldap.operation.result.code" => result.code,
          "ldap.operation.result.message" => result.message,
          "exception.message" => result.error_message,
        )
        raise LdapError.new(op, dn, result)
      end
      private :ldap_fail!
    end
  end
end
