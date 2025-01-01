# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class SecurityCampaign < Seeds::Runner
      TURBOMOCK_REPO_ID_FOR_GROUP_COUNT = 351
      def self.help
        <<~HELP
        Creates a repo with a seeded security campaign for security campaign development.

        - Runs the seed for code scanning on the org level
        - Creates a new campaign
        - Creates campaign alerts in turboscan if turboscan is running
        - Creates a repo for turbomock if not created already

        HELP
      end

      def self.run(options = {})
        puts "\n"

        print "Running code scanning seed..."
        ## Running the seed script in a separate process to make sure it does not abort the current process when turboscan is not running
        pid = Process.fork do
          Seeds::Runner::CodeScanning.execute(
            repo_path: "script/seeds/data/code_scanning/default.git",
            organization: true,
          )
        end

        Process.wait(pid)
        if $?.exitstatus != 0
          Rails.logger.warn "Code scanning seed failed with status #{$?.exitstatus}"
        end

        @owner = find_owner(options)
        @repo = T.must(Repository.last)
        @manager = find_manager(options)

        opening_details = ::SecurityCampaigns::CampaignOpeningDetails.new(
          org: @owner,
          name: options[:campaign_name] || "User-controlled injection",
          description: options[:campaign_description] || "Directly using user input (for example, an HTTP request parameter) without first sanitizing the input might allow a user to inject SQL, HTML, JavaScript, or other code into your application.",
          query_string: "is:open autofix:supported autofilter:true tag:external/cwe/cwe-089",
          alerts: {
            @repo.id => (1..13).map { |number| Turboscan::Proto::Result.new(number:, tool: ::Turboscan::Proto::ToolDescription.new(name: "CodeQL")) }
          },
          ends_at: (options[:campaign_duration] || 30).days.from_now,
          managers: [@manager],
          team_managers: [],
          contact_link: "https://example.com",
          generate_autofix_pull_requests: false,
          generate_issues: true,
          source_campaign_id: nil
        )
        security_campaign = SecurityCampaigns::CreationService.call(opening_details:, actor: @owner)

        ## Create Repos for turbomock if not provided
        if Repository.where(id: TURBOMOCK_REPO_ID_FOR_GROUP_COUNT).empty?
          r = Seeds::Objects::Repository.create(
            owner_name: @owner.login,
            repo_name: "security-campaign-repo-#{Time.now.to_i}",
            setup_master: true,
          )
          RepositorySecurityCenterConfig.find_by(repository_id: r.id)&.update(repository_id: TURBOMOCK_REPO_ID_FOR_GROUP_COUNT)
          r.update(id: TURBOMOCK_REPO_ID_FOR_GROUP_COUNT)
        end

        puts "\n"
        puts "Your security campaign is ready:\n"
        puts "    http://#{GitHub.host_name}/#{@repo.nwo}/security/campaigns/#{security_campaign.number}"
        puts "\n"
      end

      def self.find_owner(options = {})
        return ::Organization.find_by!(login: options[:organization_name]) if options[:org]

        Seeds::Objects::Organization.github
      end

      def self.find_manager(options = {})
        return ::User.find_by!(login: options[:manager_name]) if options[:manager]

        Seeds::Objects::User.monalisa
      end
    end
  end
end
