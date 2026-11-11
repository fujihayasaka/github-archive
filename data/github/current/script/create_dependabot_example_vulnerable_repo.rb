#!/usr/bin/env safe-ruby
# typed: true
# frozen_string_literal: true

require_relative "../config/environment"
require_relative "create-dependabot-github-app"
require_relative "create_dependabot_example_vulnerabilities"
require_relative "seeds/objects/user"
require "faker"
require "optparse"

unless Rails.env.development?
  abort "This can only be run in development"
end

class CreateExampleVulnerableRepository
  FEATURES_ON_REPO = []

  # Extra alerts beyond the base vulnerable repo's ~5 alerts.
  # Each entry: [state, manifest_path, dependency_scope]
  EXTRA_ALERT_SEEDS = [
    [:open,      "Gemfile.lock",      "runtime"],
    [:open,      "Gemfile.lock",      "runtime"],
    [:open,      "Gemfile.lock",      "development"],
    [:open,      "Gemfile.lock",      "runtime"],
    [:open,      "Gemfile.lock",      "runtime"],
    [:open,      "package-lock.json", "development"],
    [:open,      "package-lock.json", "runtime"],
    [:dismissed, "Gemfile.lock",      "runtime"],
    [:dismissed, "Gemfile.lock",      "development"],
    [:fixed,     "Gemfile.lock",      "runtime"],
  ].freeze

  USER_LOGINS = %w[
    alice-dev
    bob-sec
    carol-ops
    dave-eng
    eve-qa
    frank-sre
    grace-pm
    heidi-data
    ivan-infra
    judy-mobile
    karl-ml
    liam-fe
  ].freeze

  # Each entry: [description, user_indices into available_users]
  ASSIGNMENT_PLAN = [
    ["unassigned",                   []],
    ["single assignee",              [0]],
    ["single assignee (different)",  [1]],
    ["two assignees",                [0, 1]],
    ["three assignees",              [2, 3, 4]],
    ["three assignees (overlap)",    [0, 2, 5]],
    ["four assignees",               [1, 3, 6, 7]],
    ["five assignees",               [0, 1, 2, 3, 4]],
    ["max 10 assignees",             (0..9).to_a],
    ["unassigned",                   []],
    ["single assignee on dismissed", [5]],
    ["two assignees on dismissed",   [6, 7]],
    ["single assignee on fixed",     [8]],
    ["six assignees",                [0, 2, 4, 6, 8, 10]],
    ["max 10 assignees (alt)",       (0..9).to_a],
  ].freeze

  GEMFILE = <<~'GEMFILE'
    # frozen_string_literal: true

    source "https://rubygems.org"

    git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

    gem "octokit"
  GEMFILE

  GEMFILE_LOCK = <<~'GEMFILE_LOCK'
    GEM
      remote: https://rubygems.org/
      specs:
        addressable (2.5.2)
          public_suffix (>= 2.0.2, < 4.0)
        faraday (0.15.3)
          multipart-post (>= 1.2, < 3)
        multipart-post (2.0.0)
        octokit (4.13.0)
          sawyer (~> 0.8.0, >= 0.5.3)
        public_suffix (3.0.3)
        sawyer (0.8.1)
          addressable (>= 2.3.5, < 2.6)
          faraday (~> 0.8, < 1.0)

    PLATFORMS
      ruby

    DEPENDENCIES
      octokit

    BUNDLED WITH
       2.6.3
  GEMFILE_LOCK

  PACKAGE_LOCK = <<~'PACKAGE_LOCK'
  {
    "name": "test",
    "version": "1.0.0",
    "devDependencies": {
      "sawyer": "0.8.1"
    }
  }
  PACKAGE_LOCK

  README = <<~'README'
    # %{repo_name}

    This example is managed by @github/dependabot-updates to provide a test rig for our features.

    Note that pushing changes to Manifest that fix vulnerabilities will not close the vulnerabilities
    in development without the [dependency-graph-api](https://github.com/github/dependency-graph-api) service.

    # Features

    Enabled for repository:
      %{features_on_repo}

    # Config

    ```
      GitHub Bot Install ID: %{dependabot_install_id}
    ```

    ---

    Need another test repo? Check out `bin/create-example-vulnerable-repo.rb --help`

  README

  GEM_VULNERABLE_DEPENDENCIES = [
    { package_name: "octokit", ranges: [">= 4.10.0, < 4.14.0", "> 4.10.0"], dependency_scope: "runtime" },
    { package_name: "faraday", ranges: ["> 0.1.0, < 0.15.4"], dependency_scope: "development" },
    { package_name: "multipart-post", ranges: [">= 2.0.0"], dependency_scope: "development" },
  ]

  NPM_VULNERABLE_DEPENDENCIES = [
    { package_name: "sawyer", ranges: [">= 0.8.1"], dependency_scope: "development" },
  ]

  def create_repository(name: default_name, owner: monalisa, private: false, repository: nil, create_storage_records: false, create_deployment_records: false, mark_records_deleted: false)
    if mark_records_deleted && !create_storage_records && !create_deployment_records
      raise ArgumentError, "mark_records_deleted is only applicable when create_storage_records or create_deployment_records is true"
    end
    unless repository
      repository = ::Repository.handle_creation(
        owner.organization? ? owner.admins.first : owner,
        owner.login,
        {
          name: name,
          public: !private,
          template: false
        },
        synchronous: true
      ).repository
      repository.reset_memoized_attributes
    end

    repository.setup_git_repository
    repository.enable_vulnerability_alerts(actor: owner)

    enable_features(repository)
    install_dependabot_app(owner)
    add_manifests(repository, actor: owner)
    add_example_vulnerabilities(repository)
    create_artifact_storage_record(repository, mark_records_deleted) if create_storage_records
    create_artifact_deployment_record(repository, mark_records_deleted) if create_deployment_records

    repository
  rescue GitRPC::ConnectionError
    abort "\nIn order to seed repositories `script/server` must be running"
  end

  def create_artifact_storage_record(repository, mark_records_deleted)
    created_at = Time.now - 1.day
    deleted_at = mark_records_deleted ? Time.now : nil
    status = mark_records_deleted ? "deleted" : "active"
    metadata = ArtifactMetadata.create!(
      tenant_id: repository.tenant_id || 1,
      owner_id: repository.owner_id,
      repository_id: repository.id,
      attestation_id: 1,
      digest: "sha256:#{SecureRandom.hex(32)}",
      name: "#{repository.name}-1.2.3",
      version: "1.2.3",
      status: status,
      created_at: created_at,
      updated_at: created_at
    )
    ArtifactStorageRecord.find_or_create_by!(
      artifact_metadata: metadata,
      registry_url: "https://registry.example.com",
      artifact_url: "https://registry.example.com/bar/#{metadata.name}",
      registry_repository_name: "bar",
      source_registry: ArtifactStorageRecord::SOURCE_REGISTRY_ARTIFACTORY,
      deleted_at: deleted_at
    )
  end

  def create_artifact_deployment_record(repository, mark_records_deleted)
    created_at = Time.now - 1.day
    deleted_at = mark_records_deleted ? Time.now : nil
    status = mark_records_deleted ? "deleted" : "active"
    metadata = ArtifactMetadata.find_or_create_by!(
      tenant_id: repository.tenant_id || 1,
      owner_id: repository.owner_id,
      repository_id: repository.id,
      attestation_id: 1,
      digest: "sha256:#{SecureRandom.hex(32)}",
      name: "#{repository.name}-1.2.3",
      version: "1.2.3",
      status: status,
      created_at: created_at,
      updated_at: created_at
    )
    deployment_record = ArtifactDeploymentRecord.create!(
      artifact_metadata: metadata,
      owner_id: repository.owner_id,
      cluster: "moda-1",
      deployment_name: "prod-deploy-1",
      logical_environment: "production",
      physical_environment: "us-west-2",
      deleted_at: deleted_at
    )
    ArtifactDeploymentRecordTag.create!(
      deployment_record_id: deployment_record.id,
      tag_name: "runtime-risk",
      tag_value: ArtifactDeploymentRecord::SENSITIVE_DATA
    )
  end

  def enable_features(repository)
    FEATURES_ON_REPO.each do |feature|
      repository.enable_feature_flag(feature)
    end
  end

  def install_dependabot_app(owner)
    return @dependabot_install if defined?(@dependabot_install)

    user = owner.organization? ? owner.admin : owner
    dependabot_github_app = if GitHub.dependabot_github_app.nil?
      Integration.find_by(
        owner_id: GitHub.trusted_oauth_apps_owner,
        slug: "dependabot",
      )
    else
      GitHub.dependabot_github_app
    end

    @dependabot_install = dependabot_github_app.install_on(
      user,
      repositories: [],
      installer: user,
      entry_point: :script_create_dependabot_example_vulnerable_repo
    ).installation
  end

  def add_manifests(repository, actor: monalisa)
    commit = repository.commits.create({ message: "Initial commit", committer: actor }) do |files|
      files.add "Gemfile", GEMFILE
      files.add "Gemfile.lock", GEMFILE_LOCK
      files.add "package-lock.json", PACKAGE_LOCK
      files.add "README.md", readme_for(repository)
    end

    repository.refs.create("refs/heads/master", commit, actor)
  end

  def add_example_vulnerabilities(repository)
    monalisa_user = User.find_by!(login: "monalisa")

    GEM_VULNERABLE_DEPENDENCIES.each do |dependency|
      dependency[:ranges].each do |range|
        vvr = VulnerableVersionRange.find_by(affects: dependency[:package_name], requirements: range)
        next if vvr.nil? # Skip if no vulnerable version range is found

        alert = repository.repository_vulnerability_alerts.create!(
          vulnerable_version_range: vvr,
          vulnerability: T.must(vvr).vulnerability,
          vulnerable_manifest_path: "Gemfile.lock",
          dependency_scope: dependency[:dependency_scope]
        )

        # Create EPSS scores for all the alerts
        create_epss_score(alert.vulnerability)

        # Mark some alerts as Closed for various reasons.
        case dependency[:package_name]
        when "octokit"
          alert.update!(state: :dismissed, last_state_change_reason: :not_used) # dismissed state requires a non-nil last_state_change_reason
        when "faraday"
          alert.update!(state: :fixed, last_state_change_reason: :dependency_changed) # fixed state requires a non-nil last_state_change_reason
        when "multipart-post"
          alert.update!(state: :auto_dismissed, last_state_change_reason: :rule_enabled) # last_state_change_reason can be nil, setting it for consistency
        end
      end
    end

    NPM_VULNERABLE_DEPENDENCIES.each do |dependency|
      dependency[:ranges].each do |range|
        vvr = VulnerableVersionRange.find_by(affects: dependency[:package_name], requirements: range)
        repository.repository_vulnerability_alerts.create!(
          vulnerable_version_range: vvr,
          vulnerability: T.must(vvr).vulnerability,
          vulnerable_manifest_path: "package-lock.json",
          dependency_scope: dependency[:dependency_scope]
        )
      end
    end
  end

  def create_epss_score(vulnerability)
    cve_id = "CVE-#{Date.current.year}-#{SecureRandom.hex(3).upcase}"
    # Save the cve_id to the database
    vulnerability.update!(cve_id: cve_id)

    CVEEPSS.create!(
      cve_id: cve_id,
      percentage: Faker::Number.between(from: 0.0, to: 1.0).round(9).to_s.ljust(11, "0"),
      percentile: Faker::Number.between(from: 0.0, to: 1.0).round(9).to_s.ljust(11, "0"),
      calculation_date: Faker::Date.between(from: "2023-01-01", to: Date.today)
    )
  end

  def call(options)
    owner = options[:organization] ? github : monalisa
    repository = create_repository(name: options[:name] || default_name,
                      owner: owner,
                      private: options[:private],
                      create_storage_records: options[:create_storage_records],
                      create_deployment_records: options[:create_deployment_records],
                      mark_records_deleted: options[:mark_records_deleted])

    create_extra_alerts(repository)
    users = create_assignable_users(repository, user_count: options[:user_count] || USER_LOGINS.size)

    if options[:with_assignees]
      all_alerts = repository.repository_vulnerability_alerts.order(:id).to_a
      assign_users_to_alerts(all_alerts, users)
    end

    repository
  end

  private

  def create_extra_alerts(repository)
    puts "\n📦 Creating additional vulnerability alerts..."
    EXTRA_ALERT_SEEDS.each do |state, manifest_path, scope|
      vulnerability = Vulnerability.create!(
        ghsa_id: AdvisoryDB::GhsaIdGenerator.generate_unique_ghsa_id,
        severity: %w[critical high moderate low].sample,
        description: Faker::Lorem.paragraphs(number: 2).join("\n\n"),
        classification: "general",
        status: "published",
        published_at: Time.now.utc,
        summary: Faker::Lorem.sentence(word_count: 5),
      )

      ecosystem = manifest_path == "package-lock.json" ? "npm" : "RubyGems"
      package_name = ecosystem == "npm" ? "lodash-#{SecureRandom.hex(3)}" : "vuln-gem-#{SecureRandom.hex(3)}"

      vvr = vulnerability.vulnerable_version_ranges.create!(
        affects: package_name,
        ecosystem: ecosystem,
        requirements: ">= 1.0.0, < 2.0.0",
        fixed_in: state == :fixed ? "2.0.0" : nil,
      )

      alert = repository.repository_vulnerability_alerts.create!(
        vulnerable_version_range: vvr,
        vulnerability: vulnerability,
        vulnerable_manifest_path: manifest_path,
        dependency_scope: scope,
      )

      case state
      when :dismissed
        alert.update!(state: :dismissed, last_state_change_reason: :no_bandwidth)
      when :fixed
        alert.update!(state: :fixed, last_state_change_reason: :dependency_changed)
      end

      puts "  ✅ Alert ##{alert.number} (#{package_name}) — #{state}"
    end
  end

  def create_assignable_users(repository, user_count:)
    logins = USER_LOGINS.first(user_count)
    extra_count = user_count - logins.size
    logins += (1..extra_count).map { |i| "test-user-#{logins.size + i}" } if extra_count > 0

    puts "\n👥 Setting up #{logins.size} assignable users..."
    users = logins.map do |login|
      user = Seeds::Objects::User.create(login: login)
      puts "  ✅ User '#{login}' ready (id=#{user.id})"
      user
    end

    grant_write_access(repository, users)
    users
  end

  def grant_write_access(repository, users)
    owner = repository.owner
    users.each do |user|
      owner.add_member(user) if owner.organization? && !owner.member?(user)
      repository.add_member(user, action: :write)
    end
  end

  def assign_users_to_alerts(alerts, users)
    puts "\n🏷️  Assigning users to alerts..."
    alerts.each_with_index do |alert, index|
      description, user_indices = ASSIGNMENT_PLAN[index % ASSIGNMENT_PLAN.size]
      assignees = user_indices.filter_map { |i| users[i] if i < users.size }

      if assignees.empty?
        puts "  ⏭️  Alert ##{alert.number} (#{alert.package_name}, #{alert.state}) -> #{description}"
        next
      end

      alert.update_assignees(assignees, monalisa)
      puts "  ✅ Alert ##{alert.number} (#{alert.package_name}, #{alert.state}) -> #{description}: #{assignees.map(&:login).join(", ")}"
    rescue ActiveRecord::RecordInvalid => e
      puts "  ❌ Alert ##{alert.number} (#{alert.package_name}) -> #{description} FAILED: #{e.message}"
    end
  end

  def monalisa
    return @monalisa if defined?(@monalisa)
    @monalisa = User.find_by!(login: "monalisa")
  end

  def github
    return @github if defined?(@github)
    @github = Organization.find_by!(login: "github")
  end

  def default_name
    "vulnerable-repo-#{Time.now.to_i}"
  end

  def readme_for(repository)
    README % { repo_name: repository.name,
               features_on_repo: repo_feature_list,
               dependabot_install_id: @dependabot_install&.id }
  end

  def repo_feature_list
    FEATURES_ON_REPO.to_yaml
  end
end

if __FILE__ == $0
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: create_dependabot_example_vulnerable_repo.rb [options]"

    opts.on("-n", "--name NAME", "Name the repository") do |name|
      options[:name] = name
    end

    opts.on("-p", "--private", "Create a private repository (default: false)") do
      options[:private] = true
    end

    opts.on("-o", "--organization", "Create an Organization owned repository (default: false)") do
      options[:organization] = true
    end

    opts.on("--create-deployment-records", "Create with artifact deployment records (default: false)") do
      options[:create_deployment_records] = true
    end

    opts.on("--create-storage-records", "Create with artifact storage records (default: false)") do
      options[:create_storage_records] = true
    end

    opts.on("--mark-records-deleted", "Marks all created artifact and deployment records as deleted (default: false)") do
      options[:mark_records_deleted] = true
    end

    opts.on("--with-assignees", "Assign users to alerts with varied combinations (default: false)") do
      options[:with_assignees] = true
    end

    opts.on("-u", "--users COUNT", Integer, "Number of assignable users to create (default: 12)") do |count|
      options[:user_count] = [count, 1].max
    end
  end.parse!

  # Create Dependabot app and install triggers
  CreateIntegrationTrigger.new.call

  # Create example vulnerability data
  CreateExampleVulnerabilities.new.call

  repository = CreateExampleVulnerableRepository.new.call(options.to_hash)

  all_alerts = repository.repository_vulnerability_alerts.order(:id).to_a
  puts "\n\n"
  puts "Your new repository is ready:\n"
  puts "    http://#{GitHub.host_name}/#{repository.nwo}"
  puts "    Alerts page: http://#{GitHub.host_name}/#{repository.nwo}/security/dependabot"
  puts "    Total alerts: #{all_alerts.size}"
  puts "\n"
end
