# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class SemanticRetrieval < Seeds::Runner
      # Configuration for the semantic retrieval test dataset
      REPO_COUNT = 5
      ISSUES_PER_REPO = 6  # 2-3 issues per theme
      PRS_PER_REPO = 6    # Increased to support multiple PR shapes
      USERS_COUNT = 4

      # Semantic themes for testing concept clustering and synonym detection
      SEMANTIC_THEMES = [
        {
          name: "authentication_timeout",
          shared_concepts: ["token expiry", "session timeout", "auto-logout", "credential refresh"],
          issues: [
            {
              title_template: "Token refresh fails when expiry approaches",
              body_template: lambda do |_|
                <<~BODY
                ## Problem
                When access tokens approach expiration (within 5 minutes), the refresh endpoint
                returns 401 instead of issuing a new token.

                ```
                2024-01-29T10:32:45Z ERROR: GET /api/auth/refresh => 401 Unauthorized
                Response: {"error": "token_expired"}
                ```

                Users get disconnected without warning. Background jobs fail silently.

                ## Observed Behavior
                - Fresh tokens work fine
                - Tokens within 5 min of expiry: always fail
                - Refresh endpoint state is inconsistent
                - Logs show race condition in token validation

                ## Context
                This affects mobile clients worst because network latency adds unpredictable delays.
                BODY
              end
            },
            {
              title_template: "Session silently times out after period of inactivity",
              body_template: lambda do |_|
                <<~BODY
                ## Description
                Users report getting "Unauthorized" errors after being idle for ~30 minutes,
                even though the session should still be valid.

                Investigation shows:
                1. Session cookies are deleted client-side
                2. Server doesn't send refresh token proactively
                3. User gets logged out without notification

                ```
                NetworkError: Session Invalid
                Last successful request: 29m ago
                Cookie timestamp: now - 30m
                ```

                ## Impact
                - Async tasks lose auth mid-operation
                - No error message to user
                - Particularly bad on mobile/unstable networks
                BODY
              end
            }
          ]
        },
        {
          name: "pagination_correctness",
          shared_concepts: ["pagination", "result truncation", "offset", "cursor", "duplicate results"],
          issues: [
            {
              title_template: "API returns maximum 100 items regardless of limit parameter",
              body_template: lambda do |_|
                <<~BODY
                ## Bug Report
                The list endpoint is hardcoded to return max 100 results, ignoring the `limit` parameter.

                Reproduction:
                ```bash
                GET /api/repos?owner=monalisa&limit=500

                Response:
                {
                  "data": [ /* 100 items */ ],
                  "total": 1250,
                  "returned": 100
                }
                ```

                Expected: 500 items or error if not supported
                Actual: Always 100

                ## Code Location
                `internal/api/repos/handler.go:42` hardcodes `pageSize := 100`

                ## Workaround
                Making 13 requests with default limit to get all results
                BODY
              end
            },
            {
              title_template: "Offset-based pagination returns duplicate records when data changes",
              body_template: lambda do |_|
                <<~BODY
                ## Summary
                Using offset pagination causes items to appear twice when database is modified between requests.

                ## Steps to Reproduce
                1. GET /api/items?offset=0&limit=50 → items 1-50
                2. Some items inserted by background job
                3. GET /api/items?offset=50&limit=50 → items that were 40-89 become new items 50-99
                4. Items 40-49 appear in both responses

                ## Expected
                Consistent ordering regardless of concurrent inserts

                ## Actual
                Duplicates appear, items skipped

                ## Root Cause
                We use `OFFSET` which moves with table size. Cursor-based pagination would fix this.
                BODY
              end
            }
          ]
        },
        {
          name: "webhook_reliability",
          shared_concepts: ["webhook", "delivery", "retry", "duplicate", "idempotency", "event processing"],
          issues: [
            {
              title_template: "Webhook delivery retries infinitely on transient errors",
              body_template: lambda do |_|
                <<~BODY
                ## Issue
                When a webhook endpoint returns 500, our system retries indefinitely instead of giving up after N attempts.

                Observed:
                - Customer webhook endpoint returns 500 (server error)
                - Our system enqueues retry job
                - Retry job runs, endpoint still 500
                - Another retry enqueued
                - **Pattern continues forever**, creating massive queue backlog

                ```
                Queue growth: 100 jobs → 1000 → 10000 in 2 hours
                CPU spike from retry workers
                Database connection pool exhausted
                ```

                ## Expected
                Exponential backoff with max_retries = 5, then dead-letter queue

                ## Root Cause
                Missing circuit breaker and retry limit logic in webhook.go
                BODY
              end
            },
            {
              title_template: "Duplicate events processed when webhook receiver times out",
              body_template: lambda do |_|
                <<~BODY
                ## Problem
                If a webhook receiver takes >30s to respond, we timeout and requeue.
                Receiver eventually processes the first request, then processes the retry.

                Impact: Database constraint violations, duplicate analytics events, confused users

                Example:
                ```
                Event: payment_completed (idempotency_key: abc123)

                Time 0s:  POST webhook → processing
                Time 25s: still processing
                Time 30s: timeout, we requeue
                Time 35s: receiver finishes processing first request, increments counter
                Time 36s: retry arrives, increments counter again

                Result: User charged twice or analytics shows 2x revenue
                ```

                ## Solution Required
                Idempotency key support + client-side deduplication
                BODY
              end
            }
          ]
        },
        {
          name: "memory_performance",
          shared_concepts: ["memory", "memory leak", "RSS", "heap", "garbage collection", "background job"],
          issues: [
            {
              title_template: "Memory usage grows over time in async job worker process",
              body_template: lambda do |_|
                <<~BODY
                ## Observation
                Background job worker process exhibits slow memory growth:

                ```
                Start of day:    RSS = 200 MB
                After 4 hours:   RSS = 450 MB
                After 8 hours:   RSS = 680 MB
                After 24 hours:  RSS = 1.2 GB (restart forced)
                ```

                No spike, just slow creep. Suggests memory leak.

                ## Debugging
                - Heap dumps show retained objects increasing
                - GC runs but doesn't free memory
                - Goroutines stable (~150 constant)
                - No obvious cache bloat

                ## Impact
                Running out of memory, workers crash after ~18 hours

                ## Logs
                ```
                go version: 1.20
                GOMAXPROCS: 8
                goroutine stack (last 100 goroutines):
                  [truncated stack traces...]
                ```
                BODY
              end
            }
          ]
        },
        {
          name: "concurrent_load_behavior",
          shared_concepts: ["load", "timeout", "hanging", "traffic spike", "request timeout", "performance"],
          issues: [
            {
              title_template: "API request hangs indefinitely under heavy traffic",
              body_template: lambda do |_|
                <<~BODY
                ## Issue
                When traffic spikes (>1000 req/s), requests stop responding. Not errors—just hang forever.

                Behavior:
                ```
                Normal load: p99 latency = 50ms
                Spike begins: requests stop receiving responses
                Logs show: "request queued, awaiting worker"
                After 5 minutes of queuing: client timeout
                ```

                ## Root Cause Investigation
                - Load balancer is healthy
                - Database connections not exhausted
                - **Worker pool hard-coded at 100**, queue unlimited
                - High concurrency in auth validation blocking on lock

                ## Evidence
                ```
                pprof dump shows:
                - 5000+ goroutines blocked on RWMutex
                - auth validator holding lock for credential check
                - Cascading lock contention
                ```

                ## Required Fix
                Reduce lock scope, increase worker pool, add request timeout
                BODY
              end
            }
          ]
        }
      ].freeze

      # Decoy topics - semantically unrelated despite lexical similarity
      DECOY_TOPICS = [
        {
          title: "Cache invalidation strategy for user preferences",
          body: "We need a better UX for cache invalidation notifications. When we clear a user's cache, they should be notified immediately rather than discovering stale data."
        },
        {
          title: "User invalidation process for deactivated accounts",
          body: "When a user deactivates their account, we need to invalidate all their sessions, tokens, and API keys. This is different from cache management."
        },
        {
          title: "Large file uploads failing for files over 100MB",
          body: "Multipart uploads work for files up to ~100MB but fail for larger archives. Chunking logic might have an off-by-one error."
        },
        {
          title: "Large API responses timing out under normal conditions",
          body: "When retrieving large result sets (>10k records) the query response time exceeds our timeouts. This is different from upload issues."
        },
        {
          title: "Redis connection pool exhaustion during cache warmup",
          body: "The cache warmup job exhausts the Redis connection pool, starving other services of connections."
        }
      ].freeze

      def self.help
        <<~HELP
        Seed a rich, semantic-focused dataset of repos, issues, and PRs for testing
        semantic retrieval behavior in code review and analysis tools.

        This dataset is designed specifically for semantic search testing, NOT keyword matching:

        Features:
        - Concept clusters: Multiple issues across repos about same problem with different phrasing
        - Synonym variations: Token refresh, session timeout, auto-logout (same concept, different words)
        - Hard cases: "memory leak" vs "RSS grows over time" (semantic match, zero keyword overlap)
        - False positives: "cache invalidation bug" vs "user session invalidation UX" (look similar, unrelated)
        - Implicit links: PRs fixing issues without explicit IssueLink relationships
        - Multi-issue PRs: PRs that fix multiple issues but link to only one
        - Messy realism: Logs, stack traces, code snippets, narratives
        - Negative cases: Issues completely unrelated to any others

        Creates:
        - #{REPO_COUNT} repositories
        - ~#{ISSUES_PER_REPO * REPO_COUNT} issues (distributed across semantic themes + decoys)
        - #{PRS_PER_REPO * REPO_COUNT} PRs (some with links, some without, some multi-issue)
        - Realistic, messy issue bodies with technical depth

        Issues are created by various test users (semantic-tester-*), and PRs are committed by monalisa.
        All data is safe to recreate at any time.

        Options:
          -rand_seed, -s
            Integer seed value for reproducible generation.
            Defaults to current time.
            Example: bin/seed semantic_retrieval -s 12345
          -repos, -r
            Integer number of test repos to create (default: #{REPO_COUNT}).
            Example: bin/seed semantic_retrieval -r 10
        HELP
      end

      def self.run(options = {})
        # Parse options with defaults
        # Support both :seed and :rand_seed for consistency with other runners
        rand_seed = options[:rand_seed] || options[:seed] || Time.current.to_i
        repo_count = options[:repos] || REPO_COUNT

        rng = Random.new(rand_seed)
        Faker::Config.random = rng

        puts "Seeding semantic-focused dataset for testing retrieval..."
        puts "  Seed: #{rand_seed}"
        puts "  Repos: #{repo_count}"
        puts "  Concept clusters: #{SEMANTIC_THEMES.length}"
        puts "  Decoy topics: #{DECOY_TOPICS.length}"
        puts

        # Create users
        mona = Seeds::Objects::User.monalisa
        users = [mona]
        USERS_COUNT.times do |i|
          user = Seeds::Objects::User.create(login: "semantic-tester-#{i}", email: "semantic-tester-#{i}@github.com")
          users << user
        end

        # Create repos
        repos = []
        repo_count.times do |i|
          repo_name = "semantic-test-repo-#{i}"
          puts "Creating repository: #{repo_name}..."
          repo = Seeds::Objects::Repository.create(
            owner_name: mona.login,
            repo_name: repo_name,
            setup_master: true,
            is_public: true,
            description: "Semantic retrieval test repo - evaluates synonym detection, concept clustering, and implicit relationships"
          )
          repos << repo
        end

        all_issues = {}
        all_prs = {}

        # Create issues from semantic themes (concept clustering)
        puts "\nCreating semantic theme issues (concept clusters)..."
        theme_issues = {}
        repos.each do |repo|
          all_issues[repo.id] = []
          all_prs[repo.id] = []

          # Distribute themes across repos
          SEMANTIC_THEMES.each do |theme|
            theme_issues[theme[:name]] ||= []

            # Pick 1-2 issue templates from theme for this repo
            theme_issue_count = rng.rand(1..2)
            theme_issue_count.times do
              issue_template = theme[:issues].sample(random: rng)

              # Generate issue with theme-specific body
              body = if issue_template[:body_template].is_a?(Proc)
                issue_template[:body_template].call(rng)
              else
                issue_template[:body_template]
              end

              issue = Seeds::Objects::Issue.create(
                repo: repo,
                actor: users.sample(random: rng),
                title: issue_template[:title_template],
                body: body
              )

              all_issues[repo.id] << issue
              theme_issues[theme[:name]] << issue
              puts "  [#{theme[:name]}] Created: #{repo.nwo}##{issue.number}"
            end
          end
        end

        # Create decoy topics (false positives)
        puts "\nCreating decoy topics (false positives)..."
        decoy_count = (repo_count * 1.5).to_i  # 50% more decoys than themes
        decoy_count.times do |i|
          repo = repos[i % repos.length]
          decoy = DECOY_TOPICS[i % DECOY_TOPICS.length]

          issue = Seeds::Objects::Issue.create(
            repo: repo,
            actor: users.sample(random: rng),
            title: decoy[:title],
            body: decoy[:body]
          )

          all_issues[repo.id] << issue
          puts "  [DECOY] Created: #{repo.nwo}##{issue.number}"
        end

        # Create PRs: diverse shapes (bugfix, feature, refactor, API change) with various link strategies
        puts "\nCreating PRs (diverse types: bugfix, feature, refactor, API change)..."
        repos.each_with_index do |repo, _repo_idx|
          PRS_PER_REPO.times do |pr_idx|
            committer = users.sample(random: rng)

            case pr_idx
            when 0
              # BUGFIX with explicit link - the "control" case
              related_issue = all_issues[repo.id].sample(random: rng)
              title = "Fix: #{related_issue.title.downcase}"
              body = "Fixes ##{related_issue.number}\n\n" + fix_pr_body(rng)

              pr = create_pr(repo, committer, users, title, body, rng)
              all_prs[repo.id] << pr

              begin
                IssueLink.create!(
                  source_issue_id: related_issue.id,
                  target_issue_id: pr.issue.id,
                  actor: committer,
                  link_type: :track
                )
                puts "  [BUGFIX-LINKED] #{repo.nwo}!#{pr.number} → #{repo.nwo}##{related_issue.number}"
              rescue StandardError => e
                puts "  Warning: Failed to link: #{e.message}"
              end

            when 1
              # BUGFIX without explicit link - implicit semantic connection
              related_issue = all_issues[repo.id].sample(random: rng)
              title = semantic_rephrase_pr_title(related_issue.title, rng)
              body = implicit_fix_pr_body(related_issue.title, rng)

              pr = create_pr(repo, committer, users, title, body, rng)
              all_prs[repo.id] << pr
              puts "  [BUGFIX-IMPLICIT] #{repo.nwo}!#{pr.number} (no explicit link)"

            when 2
              # FEATURE PR - introduces new capability semantically related to an issue area
              # Issue about "pagination has bugs" → Feature PR about "add cursor pagination"
              related_issue = all_issues[repo.id].sample(random: rng)

              title = feature_pr_title(related_issue.title, rng)
              body = feature_pr_body(repo, related_issue, rng)

              pr = create_pr(repo, committer, users, title, body, rng)
              all_prs[repo.id] << pr
              puts "  [FEATURE] #{repo.nwo}!#{pr.number} (domain-related to issues)"

            when 3
              # REFACTORING PR - improves code quality in area where issues exist
              # Issue about "memory leaks" → Refactor PR about "optimize connection pooling"
              related_issue = all_issues[repo.id].sample(random: rng)

              title = refactor_pr_title(related_issue.title, rng)
              body = refactor_pr_body(related_issue, rng)

              pr = create_pr(repo, committer, users, title, body, rng)
              all_prs[repo.id] << pr
              puts "  [REFACTOR] #{repo.nwo}!#{pr.number} (addresses underlying architecture)"

            when 4
              # API BEHAVIOR UPDATE - changes API contract/behavior related to issues
              # Issue about "hardcoded limits" → API change to "make limits configurable"
              related_issue = all_issues[repo.id].sample(random: rng)

              title = api_update_pr_title(related_issue.title, rng)
              body = api_update_pr_body(related_issue, rng, repo)

              pr = create_pr(repo, committer, users, title, body, rng)
              all_prs[repo.id] << pr
              puts "  [API-CHANGE] #{repo.nwo}!#{pr.number} (changes API contract)"

            else
              # Multi-issue BUGFIX PR: links to one but fixes multiple
              issue_a = all_issues[repo.id].sample(random: rng)
              issue_b = (all_issues[repo.id] - [issue_a]).sample(random: rng)

              title = multi_issue_pr_title(issue_a, issue_b, rng)
              body = "Fixes ##{issue_a.number}\n\nAlso addresses ##{issue_b.number} implicitly\n\n" + multi_fix_pr_body(rng)

              pr = create_pr(repo, committer, users, title, body, rng)
              all_prs[repo.id] << pr

              begin
                IssueLink.create!(
                  source_issue_id: issue_a.id,
                  target_issue_id: pr.issue.id,
                  actor: committer,
                  link_type: :track
                )
              rescue StandardError => e
                puts "  Warning: Failed to link: #{e.message}"
              end
              puts "  [MULTI-ISSUE] #{repo.nwo}!#{pr.number} → #{repo.nwo}##{issue_a.number} + #{repo.nwo}##{issue_b.number}"
            end
          end
        end

        puts "\n✅ Successfully seeded semantic retrieval dataset!"
        puts "\nDataset characteristics:"
        puts "  • Concept clusters: Multiple issues per theme with synonym variations"
        puts "  • Hard cases: Semantic matches without keyword overlap"
        puts "  • False positives (issues): Lexically similar but unrelated issues (#{DECOY_TOPICS.length} decoys)"
        puts "  • Implicit links: PRs fixing issues without explicit IssueLink relationships"
        puts "  • Multi-issue PRs: PRs that fix multiple issues but link to only one"
        puts "  • Feature PRs: New capabilities semantically related to issue domains"
        puts "  • Refactoring PRs: Architectural improvements addressing underlying causes"
        puts "  • API changes: Contract updates related to issue constraints"
        puts "  • Messy realism: Technical details, logs, code snippets, narratives"
        puts "\nPR Type Distribution (per repo):"
        puts "  • 1 Bugfix with explicit link (control)"
        puts "  • 1 Bugfix without explicit link (implicit semantic connection)"
        puts "  • 1 Feature PR (domain-related, not a fix)"
        puts "  • 1 Refactoring PR (architectural, addresses root cause)"
        puts "  • 1 API Change PR (contract update, changes behavior)"
        puts "  • 1 Multi-issue bugfix (fixes 2 issues, links 1 explicitly)"
        puts "\n🧠 What semantic retrieval tools should learn:"
        puts "  • 'Related context' ≠ 'bugfix context' only"
        puts "  • Features, refactors, and API changes are related artifacts too"
        puts "  • Semantic understanding required (not just bugfix-shaped patterns)"
        puts "\nRecommended queries to test:"
        puts "  • 'token expires' (test synonym: should match 'session timeout')"
        puts "  • 'memory leak' (test semantic: should match 'RSS grows over time')"
        puts "  • 'webhook duplicate' (test implicit links: PRs without explicit links)"
        puts "  • 'pagination' (test cross-type: features, refactors, API changes related to issues)"
        puts "  • 'cache invalidation bug' (test false positive: different from 'session invalidation')"
      end

      def self.create_pr(repo, committer, users, title, body, rng)
        # Use monalisa as committer to avoid collaborator permission issues
        mona = Seeds::Objects::User.monalisa
        Seeds::Objects::PullRequest.create(
          repo: repo,
          committer: mona,
          title: title,
          body: body
        )
      end

      def self.fix_pr_body(rng)
        <<~BODY
          ## Changes
          - Fixed the core issue in the handler
          - Added validation for edge cases
          - Updated tests to cover regression

          ## Testing
          Tested locally with reproduction steps from issue.

          ## Checklist
          - [x] Tests passing
          - [x] No breaking changes
        BODY
      end

      def self.implicit_fix_pr_body(issue_title, rng)
        <<~BODY
          ## Summary
          Addressed the underlying cause of the problem mentioned in ##{rng.rand(1..200)}.

          While that issue described the symptom, the root cause was in the authentication
          flow. This PR refactors how we handle credential refresh to prevent the timeout
          scenarios that were being reported.

          ## Technical Details
          The issue occurred because we weren't proactively refreshing credentials when they
          approached expiration. This PR implements early refresh logic that:
          - Monitors token expiry timestamps
          - Triggers refresh when TTL < 5 minutes
          - Queues refresh in background

          ## Impact
          This should resolve not just the reported issue but similar timeout problems users
          might be experiencing in other workflows.
        BODY
      end

      def self.semantic_rephrase_pr_title(original_title, rng)
        # Create related but differently-phrased title
        rephrasing_templates = [
          "Refactor %s handling",
          "Improve %s robustness",
          "Address %s edge cases",
          "Prevent %s race conditions",
          "Optimize %s performance"
        ]

        template = T.cast(rephrasing_templates.sample(random: rng), String)
        format(template, original_title.downcase[0..15])
      end

      def self.multi_issue_pr_title(issue_a, issue_b, rng)
        components = [issue_a.title[0..10], issue_b.title[0..10]].join(" / ")
        "Refactor auth and session management: #{components}"
      end

      def self.multi_fix_pr_body(rng)
        <<~BODY
          ## What This Fixes
          This refactor addresses two related problems:
          1. Timeout issues in session management
          2. Refresh logic race conditions

          Both stem from the same underlying architectural issue in the auth layer.

          ## Root Cause
          The session and token refresh logic were competing for the same resource lock,
          causing cascading delays and timeouts.

          ## Solution
          Separated concerns into independent auth flows:
          - Token refresh: Proactive, non-blocking
          - Session validation: Cached, TTL-based
          - Credential checks: Parallel validation

          ## Code Changes
          - `internal/auth/session.go`: Extracted session TTL logic
          - `internal/auth/refresh.go`: Implemented eager refresh
          - `internal/auth/validate.go`: Parallelized validation

          Performance impact: p99 latency reduced from 450ms to 85ms under load.
        BODY
      end

      def self.feature_pr_title(related_issue_title, rng)
        # Extract domain from issue title and create feature suggestion
        feature_templates = [
          "Add %s support",
          "Implement %s mechanism",
          "Introduce %s capability",
          "Support %s workflow",
          "Enable configurable %s"
        ]

        template = T.cast(feature_templates.sample(random: rng), String)
        domain_keywords = [
          "cursor-based pagination",
          "exponential backoff",
          "request idempotency",
          "connection pooling",
          "rate limiting",
          "circuit breaker pattern"
        ]
        keyword = T.cast(domain_keywords.sample(random: rng), String)
        format(template, keyword)
      end

      def self.feature_pr_body(repo, related_issue, rng)
        <<~BODY
          ## Feature Description
          This PR introduces a new capability that addresses the underlying architectural
          constraints evident in #{repo.nwo}##{related_issue.number}.

          While that issue reported specific behavior, the root limitation is systemic:
          we need better primitives for handling distributed state.

          ## What's New
          - New capability for better handling of concurrent scenarios
          - Extensible design for future enhancements
          - Backward compatible with existing implementations

          ## Why Now
          Multiple issues across repos hint at this same underlying need:
          - Timeout behavior under load
          - Session management edge cases
          - Pagination consistency

          Rather than patch each symptom, we're adding the tool to solve the class of problem.

          ## Migration Path
          Existing code continues to work unchanged. Gradual adoption via feature flags.

          ## Example Usage
          ```ruby
          # Old way (still works)
          result = api.fetch(offset: 0, limit: 100)

          # New way (recommended)
          cursor = Cursor.start(api, limit: 100)
          results = cursor.fetch_page  # handles consistency
          ```

          ## Testing
          - Unit tests for new components: 95% coverage
          - Integration tests with existing code paths
          - Load tests to verify improvement under concurrent load
        BODY
      end

      def self.refactor_pr_title(related_issue_title, rng)
        refactor_templates = [
          "Refactor %s for maintainability",
          "Improve %s architecture",
          "Optimize %s design",
          "Restructure %s module",
          "Clean up %s implementation"
        ]

        template = T.cast(refactor_templates.sample(random: rng), String)
        areas = [
          "connection pool management",
          "token refresh flow",
          "request handling pipeline",
          "session state machine",
          "webhook retry logic",
          "credential validation"
        ]
        area = T.cast(areas.sample(random: rng), String)
        format(template, area)
      end

      def self.refactor_pr_body(related_issue, rng)
        <<~BODY
          ## Rationale
          Code review of the authentication layer revealed that #{related_issue.title.downcase}
          stems partly from architectural choices that are now constraining us.

          This refactor doesn't change external behavior but makes the system more resilient
          to the exact failure modes observed in related issues.

          ## Changes
          - Separated concerns: token lifecycle, session management, validation
          - Removed shared locks that caused contention under load
          - Improved testability with dependency injection
          - Added observability hooks for debugging timeout scenarios

          ## Before/After Metrics
          ```
          Max response time (p99):       450ms → 85ms
          Lock contention events:        2000/min → 40/min
          Memory growth over 24h:        1.2GB → 200MB
          Goroutine count (stable):      150 → 120
          ```

          ## Refactored Modules
          - `internal/auth/session.go` (65 lines removed, 40 added)
          - `internal/auth/token.go` (100 lines removed, 60 added)
          - `internal/auth/validate.go` (NEW - 80 lines, separated from token.go)

          ## Safety
          - All existing tests pass unchanged
          - Added 15 new tests for edge cases that refactor now handles better
          - No public API changes
          - Gradual rollout possible via feature flag if needed
        BODY
      end

      def self.api_update_pr_title(related_issue_title, rng)
        api_templates = [
          "Make %s configurable in API",
          "Add %s parameter to endpoints",
          "Expose %s limit as API option",
          "Update API contract for %s",
          "Enable dynamic %s configuration"
        ]

        template = T.cast(api_templates.sample(random: rng), String)
        options = [
          "pagination limit",
          "request timeout",
          "retry behavior",
          "rate limit",
          "batch size",
          "cache expiry"
        ]
        option = T.cast(options.sample(random: rng), String)
        format(template, option)
      end

      def self.api_update_pr_body(related_issue, rng, repo)
        <<~BODY
          ## Breaking Change (Minor Version Bump)
          This PR updates the API contract to give clients more control over behavior that
          is currently hardcoded or globally configured.

          Motivation from #{repo.nwo}##{related_issue.number}:
          Users hitting issues because we have one-size-fits-all defaults. Now clients can
          specify behavior at request time.

          ## API Changes
          ### Before
          ```bash
          GET /api/repos?owner=github
          # Always returns max 100 items, ignores limit parameter
          ```

          ### After
          ```bash
          GET /api/repos?owner=github&limit=500
          # Honors limit parameter (max 1000)
          # Returns X-Pagination-Limit header
          # Adds timeout parameter support
          ```

          ## Migration
          - Old requests continue to work (defaults to 100)
          - Client can opt-in to new parameters
          - Deprecation period: 6 months before old defaults change

          ## New Parameters
          - `limit`: Result page size (1-1000, default 100)
          - `timeout`: Request timeout in seconds (5-300, default 30)
          - `retry_strategy`: 'exponential' | 'linear' | 'none' (default: exponential)

          ## Documentation
          - Updated API docs with examples
          - Migration guide for clients hitting current limits
          - Playground examples in docs/api/examples/

          ## Testing
          - Backward compatibility verified with old client versions
          - New parameters tested with extreme values
          - Performance tests with large limit values
        BODY
      end

      private_class_method :create_pr, :fix_pr_body, :implicit_fix_pr_body, :semantic_rephrase_pr_title,
                           :multi_issue_pr_title, :multi_fix_pr_body, :feature_pr_title, :feature_pr_body,
                           :refactor_pr_title, :refactor_pr_body, :api_update_pr_title, :api_update_pr_body
    end
  end
end
