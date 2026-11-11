# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class OrganizationImporter < GitHub::Migrator::Importer
      def import(attributes, options = {})
        org = Organization.create! do |org|
          org.login = last_part_of_url(options[:target_url]) || attributes["login"]
          org.display_name = attributes["name"]
          org.billing_email = attributes["email"]
          org.plan = GitHub.enterprise? ? "enterprise" : "unlimited"
          org.created_at = attributes["created_at"]
          org.admin = actor || model_from_source_url(attributes["members"].find { |m| m["role"] == "admin" }["user"])

          org.save!

          if GitHub.single_business_environment? && GitHub.global_business
            GitHub.global_business.add_organization(org)
          end

          attributes["members"].each do |member|
            if user = model_from_source_url(member["user"])
              action = member["role"] == "admin" ? :admin : :read
              org.add_member(user, action: action)
            end
          end

          Array(attributes["webhooks"]).each do |webhook|
            payload_url = webhook["payload_url"]
            content_type = webhook["content_type"]
            event_types = webhook["event_types"]
            enable_ssl_verification = webhook["enable_ssl_verification"]
            active = webhook["active"]

            if payload_url && content_type && event_types && enable_ssl_verification && active
              org.hooks.create({
                name: "web",
                active: active,
                config: {
                  "url" => payload_url,
                  "insecure_ssl" => enable_ssl_verification ? "0" : "1",
                  "content_type" => content_type,
                },
                events: event_types,
              })
            end
          end
        end

        # Save profile in a separate transaction from the org save to avoid a
        # cross-cluster write (organizations/users: new cluster, profiles: mysql1).
        save_profile(org, {
          bio: attributes["description"],
          blog: attributes["website"],
          location: attributes["location"],
          email: attributes["email"],
        })

        org
      end

      private

      def save_profile(org, attrs)
        filtered = attrs.compact
        return if filtered.empty?
        org.find_or_create_profile.update!(filtered)
      end
    end
  end
end
