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

      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      def batching?
        true
      end

      def process_message(message)
        return unless message.value.dig(:search_type).first == :CODE

        GitHub.dogstats.increment("audit.code.search_query_count", { tags: ["Code Search Message Count"] })

        actor = find_actor(message)
        return if actor.nil?
        query = message.value.dig(:escaped_query)
        orgs = captured_orgs(query) + captured_repo_owners(query)
        orgs.uniq!

        found_orgs = find_organizations(orgs)

        if is_emu?(actor)
          process_emu_message(actor, message, found_orgs, query)
        else
          process_standard_message(actor, message, found_orgs, query)
        end
      end

      private

      def process_emu_message(actor, message, found_orgs, query)
        GitHub.dogstats.increment("audit.code.search_query_accepted", { tags: ["Code Search Query by EMU User"] })

        actor_business = actor.enterprise_managed_business.slug
        actor_business_id = actor.enterprise_managed_business.id
        timestamp = Time.at(message.timestamp.to_i)

        if found_orgs.empty?
          send_finished_event(
            message, actor, query, "global",
            { business: actor_business, business_id: actor_business_id },
            timestamp
          )
        else
          found_orgs.each do |organization|
            next unless is_eligible(organization, actor)

            search_string, target = filter_query_by_owner(query, organization.display_login)

            send_finished_event(
              message, actor, search_string, target,
              { org: organization.display_login, org_id: organization.id, business: organization.business.slug, business_id: organization.business.id },
              timestamp
            )

            send_finished_event(
              message, actor, search_string, target,
              { business: actor_business, business_id: actor_business_id },
              timestamp
            )
          end
        end
      end

      def process_standard_message(actor, message, found_orgs, query)
        found_orgs.each do |organization|
          next unless is_eligible(organization, actor)

          GitHub.dogstats.increment("audit.code.search_query_accepted", { tags: ["Code Search Query Eligible Owner"] })

          search_string, target = filter_query_by_owner(query, organization.display_login)
          timestamp = Time.at(message.timestamp.to_i)

          send_finished_event(
            message, actor, search_string, target,
            { org: organization.display_login, org_id: organization.id, business: organization.business.slug, business_id: organization.business.id },
            timestamp
          )
        end
      end

      def send_finished_event(message, actor, search_string, target, entity_info, timestamp)
        finished_event = {
          "@timestamp" => timestamp,
          "action" => "code.search",
          "actor" => actor&.display_login,
          "actor_id" => actor.id,
          "created_at" => timestamp,
          "search_string" => search_string,
          "target" => target,
          "actor_ip" => message.value.dig(:request_context, :ip_address),
        }.merge(entity_info) # Merging business/org specific info

        GitHub.instrument("code.search", finished_event.dup)
      end

      def find_actor(message)
        actor_id = message.value.dig(:actor, :id)
        ::User.where(id: actor_id).first
      end

      def find_organizations(orgs)
        ::Organization.includes(:business).where(login: orgs)
      end

      def is_emu?(actor)
        actor.enterprise_managed_business.present? && actor.enterprise_managed_business.audit_log_code_search_events_enabled?
      end

      def captured_orgs(query)
        org_regex = /org:([^\/ ]+)/
        query.scan(org_regex).map(&:first)
      end

      def captured_repo_owners(query)
        repo_regex = /repo:([^\/ ]+)/
        query.scan(repo_regex).map(&:first)
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

      def is_eligible(organization, actor)
        return false if organization.business.nil?
        return true if actor.organizations.where(login: organization.login).present? && organization.business.audit_log_code_search_events_enabled?
        true if organization.user_is_outside_collaborator?(actor) && organization.business.audit_log_code_search_events_enabled?
      end
    end
  end
end
