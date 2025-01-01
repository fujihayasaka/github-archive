# typed: true
# frozen_string_literal: true

module GitHub
  module LDAP
    class Search
      include GitHub::Ldap::Filter

      PERSONAS = Net::LDAP::Filter.eq("objectClass", "person") |
                 Net::LDAP::Filter.eq("objectClass", "inetOrgPerson") |
                (Net::LDAP::Filter.eq("objectClass", "user") &
                 Net::LDAP::Filter.ne("objectClass", "computer"))

      # Structure to wrap ldap search results and operations.
      # Currently only used by `find_personas`.
      class ResultSet
        attr_reader :entries, :code, :message

        def initialize(entries, code = 0, message = nil)
          @entries, @code, @message = entries, code, message
        end

        # Public - Check if the search returned an error.
        # `4` is not considered an error. It means
        # the search returned more elements than expected
        # and the results were truncated.
        #
        # Returns true if the search returned an error.
        def search_error?
          code != 0 && code != 4
        end
      end

      # Public - Get the ldap entry for a group with a given dn.
      #
      # dn: is the ldap dn for the group.
      #
      # Returns nil if the group doesn't exist.
      # Returns a Net::LDAP::Entry if the group exists.
      def find_group(dn)
        ldap.domain(dn).bind
      end

      # Public - Find users in github that map to members in an ldap group.
      #
      # dn: is the group dn.
      #
      # Returns an array of User
      def find_member_mappings(dn)
        member_mappings = ldap.group(dn).members.each_with_object({}) do |entry, hash|
          hash[entry.dn] = GitHub.auth.profile_info(entry, :uid).first
        end

        # XXX: Should we still look for logins?
        #      I feel like at this point we should have every user mapped to its ldap entry.
        users = Set.new(User.with_logins(*member_mappings.values))
        users.merge User.find_by_ldap_mappings(*member_mappings.keys)
      end

      # Public - Find groups in all the domains that match the query.
      # It does partial matching with CN.
      #
      # query: is the string to match in every domain.
      #
      # Returns the list of Net::LDAP::Entry found in every domain.
      def find_groups(query)
        domains.each_with_object([]) do |domain, rs|
          domain.filter_groups(query, size: 10) do |entry|
            rs << entry
          end
        end
      end

      # Public - Find groups in all the domains that have that CN.
      # It does exact matching with CN.
      #
      # group_name: is the CN to search for.
      #
      # Returns the list of Net::LDAP::Entry found in every domain.
      def groups(*group_name)
        domains.each_with_object([]) do |domain, rs|
          rs.concat domain.groups(group_name)
        end
      end

      # Public - Find all groups that a user is direct member of.
      #
      # entry: an instance of Net::LDAP::Entry
      #
      # Returns an array with the ldap groups.
      def find_all_memberships(entry)
        filter = member_filter(entry)

        if ldap.posix_support_enabled? && !entry[ldap.uid].empty?
          filter |= posix_member_filter(entry, ldap.uid)
        end

        filter &= ALL_GROUPS_FILTER

        domains.each_with_object([]) do |domain, rs|
          rs.concat domain.search(filter: filter)
        end
      end

      # Public - Find all members of the ldap domains that are considered personas.
      #
      # options: is a Hash with the options for the search. Options include:
      # * filter: additional filter to add to the search.
      # * attributes: Array of attributes to return for each entry.
      # * limit: number of entries to return, all of them by default.
      # block: additional block to filter results for.
      #
      # Return a ResultSet containing the array of Net::LDAP::Entry
      def find_personas(options = {}, &block)
        if options.key?(:filter)
          options[:filter] &= PERSONAS
        else
          options[:filter] = PERSONAS
        end

        # translation for Net::LDAP#search
        options[:size] ||= options[:limit]

        result =
          ldap.open do
            domains.each_with_object([]) do |domain, rs|
              domain.search(options) do |entry|
                valid = !block_given? || block.call(entry)
                rs << entry if valid
              end

              last_result = ldap.last_operation_result

              if last_result.code != 0
                GitHub::Authentication.logger.info("LDAP user search failed", "code.namespace" => self.class.name, "code.function" => __method__, "ldap.search.result.code" => last_result.code, "ldap.search.result.message" => last_result.message)

                return ResultSet.new(rs, last_result.code, last_result.message)
              end
            end
          end

        ResultSet.new(result)
      end

      def ldap
        GitHub.auth.strategy
      end

      def domains
        GitHub.auth.ldap_domains.values
      end
    end
  end
end
