# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class CodeSearchQueryProcessor < BaseProcessor
      DEFAULT_GROUP_ID = "github-#{Rails.env}-code_search_audit_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.v1\.Search\Z/

      options[:max_bytes_per_partition] = 0.5.megabytes
      options[:max_wait_time] = 0.25.seconds
      options[:min_bytes] = 1.bytes
      options[:session_timeout] = 60.seconds
      options[:socket_timeout] = 65.seconds
      options[:start_from_beginning] = false
      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      def batching?
        true
      end

      # Public: Process a single Hydro message
      #
      # message - The Hydro message to process
      #
      # Returns nothing
      def process_message(message)
        return unless message.value.dig(:search_type).first == :CODE
        GitHub.dogstats.increment("audit.code.search_query_count",
          {
            tags: ["Code Search Message Count"],
          })
        actor_id = message.value.dig(:actor, :id)
        actor = ::User.where(id: actor_id).first
        query = message.value.dig(:escaped_query)
        orgs = captured_orgs(query) + captured_repo_owners(query)
        orgs.uniq!

        found_orgs = ::Organization.includes(:business).where(login: orgs)

        if found_orgs.length == 0 && actor.enterprise_managed_business.present? && actor.enterprise_managed_business.audit_log_code_search_events_enabled?

          GitHub.dogstats.increment("audit.code.search_query_accepted",
              {
                tags: ["Code Search Query by EMU User"],
              })

          business = actor.enterprise_managed_business.slug
          business_id = actor.enterprise_managed_business.id
          timestamp = Time.at(message.timestamp.to_i)

          finished_event = {
              "@timestamp" => timestamp,
              "action" => "code.search",
              "actor" => actor&.display_login,
              "actor_id" => actor_id,
              "business" => business,
              "business_id" => business_id,
              "created_at" => timestamp,
              "search_string" => query,
              "target" => "global",
              "actor_ip" => message.value.dig(:request_context, :ip_address),
            }

          GitHub.instrument("code.search", finished_event.dup)

        else

          # Loop through orgs and owners and fire off an individual log entry
          found_orgs.map do |organization|
            next unless is_eligible(organization)
            GitHub.dogstats.increment("audit.code.search_query_accepted",
              {
                tags: ["Code Search Query Eligible Owner"],
              })

            business_id = organization.business.id

            search_string, target = filter_query_by_owner(query, organization.display_login)

            timestamp = Time.at(message.timestamp.to_i)

            finished_event = {
              "@timestamp" => timestamp,
              "action" => "code.search",
              "actor" => actor&.display_login,
              "actor_id" => actor_id,
              "business" => organization.business.slug,
              "business_id" => organization.business.id,
              "created_at" => timestamp,
              "search_string" => search_string,
              "target" => target,
              "org" => organization.display_login,
              "org_id" => organization.id,
              "actor_ip" => message.value.dig(:request_context, :ip_address),
            }

            GitHub.instrument("code.search", finished_event.dup)
          end
        end
      end

      private

      def captured_orgs(query)
        org_regex = /org:([^\/ ]+)/
        org_matches = query.scan(org_regex)
        org_matches.map(&:first)
      end

      def captured_repo_owners(query)
        repo_regex = /repo:([^\/ ]+)/
        repo_matches = query.scan(repo_regex)
        repo_matches.map(&:first)
      end

      def filter_query_by_owner(query, owner)
        query_segments = query.split
        filtered_segments = []
        targets = []
        owner_found = false

        query_segments.each do |segment|
          if segment == "OR" || segment == "AND"
            next
          elsif segment =~ /\A(repo|org):\b/
            if segment =~ /\A(repo|org):#{Regexp.escape(owner)}\b/
              owner_found = true
              targets << segment
            end
          else
            filtered_segments << segment
          end
        end

        return "", "" unless owner_found

        search_string = filtered_segments.join(" ")
        target = targets.join(", ")

        [search_string, target]
      end

      def is_eligible(organization)
        return false if organization.business.nil?
        organization.business.audit_log_code_search_events_enabled?
      end
    end
  end
end
