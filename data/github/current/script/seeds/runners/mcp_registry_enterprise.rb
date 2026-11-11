# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class McpRegistryEnterprise < Seeds::Runner
      DEFAULT_PAT_SCOPES = "repo"

      def self.help
        <<~HELP
        Seeds data for MCP Registry Enterprise features from a JSON seed file.

        This runner is designed to be invoked by an external service (mcp registry):
        - The external service owns the seed JSON file
        - The file is copied into the monolith environment
        - This runner reads the file, performs the creates, and prints a single JSON result

        Input JSON schema (versioned):
        {
          "version": 1,
          "users": [
            { "login": "mcp-registry-admin", "copilot_access": "none" },
            { "login": "some-user", "copilot_access": "limited" }
          ],
          "enterprises": [
            {
              "name": "MCP Registry Enterprise",
              "owners": ["mcp-registry-admin"],
              "organizations": [
                {
                  "login": "mcp-registry-org",
                  "admins": ["mcp-registry-admin"],
                  "members": ["some-user"]
                }
              ]
            }
          ]
        }

        Notes:
        - "copilot_access" may be one of:
          - "none"
          - "free" (creates Copilot::FreeUser)
          - "limited" (creates Copilot::LimitedUser)
          - "cfi" (creates an individual Copilot subscription item)
          - "cfb" (creates a Copilot seat in an org)
          - "cfe" (creates a Copilot Enterprise seat in an org; implies cfb)

        Output:
        - Prints a single JSON document to stdout containing created IDs and seeded Copilot access.

        Output JSON schema:
        {
          "version": 1,
          "seed_name": "mcp_registry_enterprise",
          "users": [
            { "login": "mcp-registry-admin", "id": 123, "copilot_access": "limited", "token": "ghp_..." }
          ],
          "organizations": [
            {
              "login": "mcp-registry-org",
              "id": 456,
              "enterprise_name": "MCP Registry Enterprise",
              "admins": ["mcp-registry-admin"],
              "members": ["some-user"]
            }
          ],
          "enterprises": [
            {
              "name": "MCP Registry Enterprise",
              "slug": "mcp-registry-enterprise",
              "id": 789,
              "owners": ["mcp-registry-admin"]
            }
          ]
        }

        Notes:
        - Arrays are sorted by login/name for stable output.
        - The output includes a token per seeded user; handle it as a secret.

        Options:
          --seed-file, -f    Path to input JSON seed file (required)
          --output-file, -o  Path to write JSON output file (optional)

        Usage:
          bin/seed mcp_registry_enterprise --seed-file /path/to/seed.json
          bin/seed mcp_registry_enterprise --seed-file /path/to/seed.json --output-file /path/to/output.json
        HELP
      end

      def self.run(options = {})
        require "json"

        seed_file = options[:seed_file] || options["seed_file"] || options[:"seed-file"] || options["seed-file"]
        output_file = options[:output_file] || options["output_file"] || options[:"output-file"] || options["output-file"]
        raise ArgumentError, "seed_file is required" if seed_file.blank?
        raise ArgumentError, "seed_file not found: #{seed_file}" unless File.exist?(seed_file)

        seed = JSON.parse(File.read(seed_file))
        version = seed["version"]
        raise ArgumentError, "unsupported seed version: #{version.inspect}" unless version == 1

        users_by_login = {}
        user_specs_by_login = {}
        created = {
          "version" => 1,
          "seed_name" => "mcp_registry_enterprise",
          "users" => [],
          "organizations" => [],
          "enterprises" => [],
        }

        Array(seed["users"]).each do |raw_user_spec|
          user_spec = normalize_user_spec(raw_user_spec)
          login = user_spec.fetch("login")
          unless user_spec.key?("copilot_access")
            raise ArgumentError, "user #{login.inspect} must include copilot_access"
          end

          unknown_keys = user_spec.keys - %w[login copilot_access copilot_org copilot_organization]
          raise ArgumentError, "user #{login.inspect} has unsupported keys: #{unknown_keys.sort.join(", ")}" if unknown_keys.any?

          user = Seeds::Objects::User.create(login: login, email: "#{login}@example.com")
          token, _access = Seeds::Objects::User.create_pat(user: user, scopes: DEFAULT_PAT_SCOPES)
          users_by_login[login] = user
          user_specs_by_login[login] = user_spec

          created["users"] << {
            "login" => user.login,
            "id" => user.id,
            "copilot_access" => user_spec.fetch("copilot_access"),
            "token" => token,
          }
        end

        organizations_by_login = {}
        organizations_initial_admin_by_login = {}
        enterprises_by_name = {}

        Array(seed["enterprises"]).each do |enterprise_spec|
          name = enterprise_spec.fetch("name")
          owner_logins = Array(enterprise_spec["owners"])
          org_specs = Array(enterprise_spec["organizations"])

          primary_owner_login = owner_logins.first
          primary_owner = primary_owner_login ? users_by_login.fetch(primary_owner_login) : Seeds::Objects::User.monalisa

          orgs_for_business = []

          org_specs.each do |org_spec|
            org_login = org_spec.fetch("login")
            admin_logins = Array(org_spec["admins"])
            member_logins = Array(org_spec["members"])

            initial_admin_login = admin_logins.first || primary_owner.login
            initial_admin = users_by_login.fetch(initial_admin_login)

            org = Seeds::Objects::Organization.create(login: org_login, admin: initial_admin)
            organizations_by_login[org_login] = org
            organizations_initial_admin_by_login[org_login] = initial_admin
            orgs_for_business << org

            admin_logins.each do |admin_login|
              admin_user = users_by_login.fetch(admin_login)
              next if admin_user.id == initial_admin.id
              org.add_admin(admin_user, adder: initial_admin)
            end

            member_logins.each do |member_login|
              member_user = users_by_login.fetch(member_login)
              next if admin_logins.include?(member_login)
              org.add_member(member_user, action: :read, adder: initial_admin)
            end

            created["organizations"] << {
              "login" => org.login,
              "id" => org.id,
              "enterprise_name" => name,
              "admins" => admin_logins.presence || [initial_admin.login],
              "members" => member_logins,
            }
          end

          business = Seeds::Objects::Business.create(name: name, owner: primary_owner, organizations: orgs_for_business)

          owner_logins.drop(1).each do |owner_login|
            owner_user = users_by_login.fetch(owner_login)
            business.add_owner(owner_user, actor: primary_owner)
          end

          enterprises_by_name[name] = business
          created["enterprises"] << {
            "name" => business.name,
            "slug" => business.slug,
            "id" => business.id,
            "owners" => owner_logins.presence || [primary_owner.login],
          }
        end

        user_specs_by_login.each do |login, user_spec|
          desired_access = user_spec.fetch("copilot_access").to_s
          next if desired_access == "none" || desired_access.blank?

          seed_copilot_access!(
            user: users_by_login.fetch(login),
            desired_access: desired_access,
            user_spec: user_spec,
            organizations_by_login: organizations_by_login,
            organizations_initial_admin_by_login: organizations_initial_admin_by_login,
          )
        end

        created["users"].sort_by! { |u| u.fetch("login") }
        created["organizations"].sort_by! { |o| o.fetch("login") }
        created["enterprises"].sort_by! { |e| e.fetch("name") }

        json = JSON.pretty_generate(created)
        if output_file.present?
          require "fileutils"
          FileUtils.mkdir_p(File.dirname(output_file))
          File.write(output_file, "#{json}\n")
        end

        puts json
      end

      def self.normalize_user_spec(raw_user_spec)
        case raw_user_spec
        when Hash
          raw_user_spec
        else
          raise ArgumentError, "invalid user spec: #{raw_user_spec.inspect}"
        end
      end
      private_class_method :normalize_user_spec

      def self.seed_copilot_access!(user:, desired_access:, user_spec:, organizations_by_login:, organizations_initial_admin_by_login:)
        case desired_access
        when "free"
          Copilot::FreeUser.find_or_create_by!(user_id: user.id) do |free_user|
            free_user.free_user_type = Copilot::FreeUser::COMPLIMENTARY_ACCESS.name
            free_user.subscribed = true
            free_user.subscribed_at = Time.current
            free_user.last_checked_date = 1.year.from_now.to_date
          end
        when "limited"
          Copilot::LimitedUser.find_or_create_by!(user_id: user.id) do |limited_user|
            limited_user.subscribed_at = Time.current
          end
        when "cfi"
          product_identifier = Billing::Public::Product::ProductIdentifier.new(
            product_type: Copilot::PRODUCT_TYPE,
            product_key: Copilot::INDIVIDUAL_PRO_PRODUCT_KEY,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
          )
          result = Billing::Public::SubscriptionItem.create(
            product: product_identifier,
            account: user,
            actor: user,
            free_trial_length: 0.days,
            perform_authorization: false,
          )
          raise result.error unless result.ok?
        when "cfb", "cfe"
          org = find_org_for_copilot_seat!(
            user: user,
            user_spec: user_spec,
            organizations_by_login: organizations_by_login,
          )

          # Ensure organization is configured for the desired plan before creating seats.
          copilot_org = Copilot::Organization.new(org)
          if desired_access == "cfe"
            copilot_org.copilot_plan_enterprise!(false)
          else
            copilot_org.copilot_plan_business!(false)
          end

          assigning_user = organizations_initial_admin_by_login.fetch(org.login)

          seat_assignment = Copilot::SeatAssignment.create!(
            owner: org,
            organization: org,
            assignable: user,
            assigning_user: assigning_user,
            skip_delayed_converter_job: true,
          )

          Copilot::Seat.create!(
            organization: org,
            assigned_user: user,
            seat_assignment: seat_assignment,
          )
        else
          raise ArgumentError, "unsupported copilot_access: #{desired_access.inspect}"
        end
      end
      private_class_method :seed_copilot_access!

      def self.find_org_for_copilot_seat!(user:, user_spec:, organizations_by_login:)
        explicit_org_login = user_spec["copilot_org"] || user_spec["copilot_organization"]
        if explicit_org_login.present?
          return organizations_by_login.fetch(explicit_org_login)
        end

        org = organizations_by_login.values.find { |o| o.member?(user) }
        return org if org

        raise ArgumentError, "cannot determine org for copilot seat for user #{user.login.inspect}; specify copilot_org"
      end
      private_class_method :find_org_for_copilot_seat!
    end
  end
end
