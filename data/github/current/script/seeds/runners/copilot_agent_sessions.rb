# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class CopilotAgentSessions < Seeds::Runner
      FEATURE_FLAGS = %w[
        enterprise_ai_controls
        agent_sessions_no_access_label
      ]

      def self.help
        <<~HELP
        Seeds Copilot agent session data for AI Controls development.

        Creates:
        - 16 organizations with 2 repositories each (32 repos total)
        - 1 pull request per repository (32 PRs total)
        - 100 agent sessions in the last 24 hours
        - 25 sessions per day for days 1-29 (covers 24h-30d ago, 725 sessions)
        - Sessions with various states (queued, in_progress, completed, failed, etc.)
        - Sessions from 4 different agent types (CCA, CCR, Claude, Codex)

        This seeds real database records so the development environment uses the same
        code path as production (instead of mock data).

        To run the seed script:
          1. script/server
          2. bin/seed copilot_agent_sessions

        To verify:
          Visit /enterprises/github-inc/ai-controls/agents/sessions
        HELP
      end

      def self.run(options = {})
        # Enable feature flags
        FEATURE_FLAGS.each do |flag|
          Seeds::Objects::FeatureFlag.enable(feature_flag: flag)
          puts "Enabled feature flag: #{flag}"
        end

        business = Seeds::Objects::Business.github

        # Get all agent types for testing filtering
        cca_agent = Apps::Privileged.integration(:copilot_swe_agent)
        ccr_agent = Apps::Privileged.integration(:copilot_pull_request_reviewer)
        claude_agent = Apps::Privileged.integration(:claude_agent)
        codex_agent = Apps::Privileged.integration(:codex_agent)

        unless cca_agent
          puts "⚠️  copilot_swe_agent integration not found. Creating a test integration..."
          cca_agent = Apps::Privileged::CopilotSWEAgent.seed_database!
          Apps::Privileged::Registry.instance.reload_caches!
        end

        unless ccr_agent
          puts "⚠️  copilot_pull_request_reviewer integration not found. Creating a test integration..."
          ccr_agent = Apps::Privileged::CopilotPullRequestReviewer.seed_database!
          Apps::Privileged::Registry.instance.reload_caches!
        end

        unless claude_agent
          puts "⚠️  claude_agent integration not found. Creating a test integration..."
          claude_agent = Apps::Privileged::ClaudeAgent.seed_database!
          Apps::Privileged::Registry.instance.reload_caches!
        end

        unless codex_agent
          puts "⚠️  codex_agent integration not found. Creating a test integration..."
          codex_agent = Apps::Privileged::CodexAgent.seed_database!
          Apps::Privileged::Registry.instance.reload_caches!
        end

        agents = [cca_agent, ccr_agent, claude_agent, codex_agent]

        puts "\nCreating organizations and repositories..."
        puts "  (Some orgs will be restricted to test access control)\n"

        # Create a second admin user for restricted organizations
        nebula = Seeds::Objects::User.create(login: "nebula-admin-#{rand(1000..9999)}")
        puts "  Created #{nebula.login} user for inaccessible organizations\n"

        org_configs = [
          { login: "acme-corp", repos: %w[platform api-gateway] },
          { login: "stellar-dynamics", repos: %w[core analytics] },
          { login: "quantum-labs", repos: %w[engine sdk] },
          { login: "nebula-systems", repos: %w[web-app mobile-app] },
          { login: "apex-technologies", repos: %w[backend frontend] },
          { login: "cirrus-innovations", repos: %w[microservices infrastructure] },
          { login: "vertex-solutions", repos: %w[data-pipeline ml-models] },
          { login: "zenith-digital", repos: %w[e-commerce payments] },
          { login: "phoenix-ventures", repos: %w[saas-platform admin-portal] },
          { login: "atlas-engineering", repos: %w[monorepo tools] },
          { login: "nova-software", repos: %w[client-portal api] },
          { login: "titan-industries", repos: %w[workflow-engine scheduler] },
          { login: "pulse-technologies", repos: %w[realtime-server websocket-api] },
          { login: "fusion-labs", repos: %w[research experiments] },
          { login: "orbit-systems", repos: %w[dashboard reporting] },
          { login: "jaffna-labs", repos: %w[services libraries] },
        ]

        repos = org_configs.flat_map.with_index do |config, index|
          # First 11 orgs are accessible to monalisa, last 5 are restricted
          # This creates a 70/30 split for testing the accessible field
          is_restricted = index >= 11
          admin = is_restricted ? nebula : Seeds::Objects::User.monalisa

          org = Seeds::Objects::Organization.create(
            login: config[:login],
            admin: admin
          )
          business.add_organization(org)

          config[:repos].map do |repo_name|
            repo = Seeds::Objects::Repository.create(
              owner_name: org.login,
              repo_name: repo_name,
              setup_master: true,
              is_public: false
            )

            # Create a pull request for each repository
            pr = Seeds::Objects::PullRequest.create(
              repo: repo,
              committer: admin,
              title: "Add new feature",
              body: "This is a test pull request for agent sessions"
            )

            access_label = is_restricted ? "[NO ACCESS]" : "[accessible]"
            puts "  Created #{org.login}/#{repo.name} with PR ##{pr.number} #{access_label}"

            { repo: repo, pr: pr, restricted: is_restricted }
          end
        end

        statuses = %w[queued in_progress completed failed idle waiting_for_user timed_out cancelled]

        session_titles = [
          "Debug authentication flow",
          "Implement new feature",
          "Fix performance issue",
          "Update dependencies",
          "Add unit tests",
          "Refactor legacy code",
          "Review pull request",
          "Deploy to production",
          "Investigate bug report",
          "Optimize database queries",
        ]

        puts "\nCreating 100 agent sessions in last 24 hours..."
        puts "  Mix of CCA, CCR, Claude, and Codex agents..."

        session_counter = 0
        100.times do |i|
          repo_data = repos.sample
          repo = repo_data[:repo]
          pr = repo_data[:pr]

          # Create sessions within last 24 hours
          hours_ago = rand(24)
          minutes_ago = rand(60)
          started_at = Time.current - hours_ago.hours - minutes_ago.minutes

          # Alternate between agents to get a good mix for testing filtering
          agent = agents[i % agents.length]

          Copilot::AgentSession.create!(
            business: business,
            organization: repo.owner,
            repository: repo,
            resource: pr,
            user: Seeds::Objects::User.monalisa,
            agent: agent,
            copilot_session_id: "seed_session_#{session_counter}_#{Time.current.to_i}",
            state: statuses.sample,
            name: session_titles.sample,
            created_at: started_at,
          )

          session_counter += 1
          print "." if (i + 1) % 10 == 0
        end

        puts "\n\nCreating 25 agent sessions per day for remaining days (1-29 days ago)..."

        # Create 25 sessions for each of the remaining 29 days (covers 24h-30d ago)
        (1..29).each do |day|
          25.times do
            repo_data = repos.sample
            repo = repo_data[:repo]
            pr = repo_data[:pr]

            # Create sessions within this day's 24h window (e.g., day=1 covers 24-48h ago)
            random_hours = rand(24)
            random_minutes = rand(60)
            started_at = Time.current - (day + 1).days + random_hours.hours + random_minutes.minutes

            # Alternate between agents to get a good mix for testing filtering
            agent = agents[session_counter % agents.length]

            Copilot::AgentSession.create!(
              business: business,
              organization: repo.owner,
              repository: repo,
              resource: pr,
              user: Seeds::Objects::User.monalisa,
              agent: agent,
              copilot_session_id: "seed_session_#{session_counter}_#{Time.current.to_i}",
              state: statuses.sample,
              name: session_titles.sample,
              created_at: started_at,
            )

            session_counter += 1
          end
          print "." if day % 5 == 0
        end

        accessible_repos = repos.count { |r| !r[:restricted] }
        restricted_repos = repos.count { |r| r[:restricted] }

        puts "\n\n✅ Successfully seeded Copilot agent sessions!"
        puts "\nSummary:"
        puts "  - #{org_configs.length} organizations with 2 repos each (#{repos.length} total repos)"
        puts "    • #{accessible_repos} repos accessible to monalisa (orgs: #{org_configs[0..10].map { |c| c[:login] }.join(', ')})"
        puts "    • #{restricted_repos} repos NOT accessible to monalisa (orgs: #{org_configs[11..15].map { |c| c[:login] }.join(', ')})"
        puts "  - #{repos.length} pull requests (1 per repo)"
        puts "  - 100 sessions in last 24 hours"
        puts "  - 725 sessions across remaining days (25 per day for days 1-29, covering 24h-30d ago)"
        puts "  - Total: 825 sessions"
        puts "    • Mixed across 4 agent types (CCA, CCR, Claude, Codex)"
        puts "    • Various states and timestamps for realistic data"
        puts "    • ~30% of sessions will show 'accessible: false' for monalisa (70/30 split)"
        puts "\nNext steps:"
        puts "  1. Visit /enterprises/github-inc/ai-controls/agents/sessions"
        puts "  2. Log in as 'monalisa' to see sessions with mixed access levels"
        puts "  3. Sessions from restricted orgs should show 'accessible: false'"
        puts "  4. Try filtering by date range, organization, or agent type"
      end
    end
  end
end
