require "terminal-table"
require "clearly_defined"
require_relative "../../lib/hmac_authentication"
require_relative "../../etl/ingest/package_metadata_processor"

class ChatopsController < ApplicationController
  include ::Chatops::Controller

  # Create a comma-separated list of supported Package Managers
  PACKAGE_MANAGER_LIST = Types::PackageManager.map(&:to_s).join(", ")

  chatops_namespace :dg

  chatop :echo,
  /echo (?<text>.*)?/,
  "echo <text> - Echo some text back" do
    jsonrpc_success "Echoing back to you: #{jsonrpc_params[:text]}"
  end

  chatop :ping,
  /ping/,
  "ping - replies back with 'pong!'" do
    jsonrpc_success "pong!"
  end

  chatop :blocklist,
  /blocklist (?<type>\S*)/,
  "blocklist <type> - returns the <type> ('packages' or 'repos') blocklist" do
    type = jsonrpc_params[:type]
    case type
    when "repos"
      manifest_repos_blocklist = Ingest::Blocklist.view(type: :manifest_repos)
      manifests_repos = manifest_repos_blocklist.empty? ? "None" : manifest_repos_blocklist.join(", ")
      jsonrpc_success ":no_entry_sign: Blocklisted manifest repos: %s" % manifests_repos
    when "packages"
      package_blocklist = Ingest::Blocklist.view(type: :packages)
      packages = if package_blocklist.present?
                   packages_string = package_blocklist.map { |package| package.split(":").then { |name, manager| "#{name} (#{manager})" } }
                   packages_string.join(", ")
      else
        "None"
      end
      jsonrpc_success ":no_entry_sign: Blocklisted packages: %s" % packages
    else
      jsonrpc_failure "You didn't input a valid type :sad_parrot:"
    end
  end

  chatop :blocklist_repos_add,
  /blocklist repos add (?<items>.*)/,
  "blocklist repos add <items> - adds the <items> to the the manifest repos blocklist. Accepts Repository IDs or NWOs" do
    type = jsonrpc_params[:type]
    items = jsonrpc_params[:items]

    items_array = items.split(/[\s,]+/)

    items_array.each { |item| Ingest::Blocklist.add(type: :manifest_repos, item: item) }
    jsonrpc_success ":plus: Sucessfully added '#{items}' to the manifest repos blocklist!"
  end

  chatop :blocklist_packages_add,
  /blocklist packages add (?<name>\S*) (?<manager>\S*)/,
  "blocklist packages add <name> <manager> - adds the package <name> <manager> to the the packages blocklist" do
    type = jsonrpc_params[:type]
    name = jsonrpc_params[:name]
    manager = jsonrpc_params[:manager]

    unless PACKAGE_MANAGER_LIST.include?(manager)
      jsonrpc_failure "You didn't input a valid package name & manager :sad_parrot:. Try dg blocklist packages add package_name package_manager."
      return
    end

    package_string = "#{name}:#{manager}"
    Ingest::Blocklist.add(type: :packages, item: package_string)

    jsonrpc_success ":plus: Sucessfully added '#{package_string}' to the packages blocklist!"
  end


  chatop :blocklist_repos_remove,
  /blocklist repos remove (?<items>.*)/,
  "blocklist repos remove <items> - removes <items> from the the repos blocklist. Accepts Repository IDs or NWOs" do
    type = jsonrpc_params[:type]
    items = jsonrpc_params[:items]

    items_array = items.split(/[\s,]+/)

    items_array.each { |item| Ingest::Blocklist.remove(type: :manifest_repos, item: item) }
    jsonrpc_success ":heavy_minus_sign: Sucessfully removed '#{items}' from the manifest repos blocklist!"
  end

  chatop :blocklist_packages_remove,
  /blocklist packages remove (?<name>\S*) (?<manager>\S*)/,
  "blocklist packages remove <name> <manager> - removes the package <name>,<manager> from the the packages blocklist" do
    type = jsonrpc_params[:type]
    name = jsonrpc_params[:name]
    manager = jsonrpc_params[:manager]

    unless PACKAGE_MANAGER_LIST.include?(manager)
      jsonrpc_failure "You didn't input a valid package name & manager :sad_parrot:. Try dg blocklist packages remove package_name package_manager."
      return
    end

    package_string = "#{name}:#{manager}"
    Ingest::Blocklist.remove(type: :packages, item: package_string)
    jsonrpc_success ":heavy_minus_sign: Sucessfully removed '#{package_string}' from the packages blocklist!"
  end

  chatop :hmac,
  /hmac/,
  "hmac - gives you an hmac token" do
    key = ENV["DEPENDENCY_GRAPH_API_HMAC_KEYS"].to_s.split(" ").first.to_s
    hmac = HMACAuthentication.request_hmac(Time.now, key)
    jsonrpc_success hmac
  end
  chatop :checkpoints,
  /checkpoints/,
  "checkpoints - List the known checkpoints" do
    checkpoint_names = Checkpoint.names
    jsonrpc_success "I know about the following checkpoints: ```\n#{checkpoint_names.join("\n")}\n```"
  end

  chatop :checkpoint,
  /checkpoint (?<name>.*)/,
  "checkpoint <name> - Get the latest checkpoint for a given name" do
    name = jsonrpc_params[:name]
    checkpoint = Checkpoint.with_name(name).first
    if checkpoint
      jsonrpc_success "Checkpoint for #{name} is #{checkpoint.get} (last updated at #{checkpoint.updated_at})"
    else
      jsonrpc_failure "Checkpoint for #{name} not found."
    end
  end

  chatop :locks,
  /locks/,
  "locks - Get the full list of dg_lock entries" do
    output = "LOCKNAME             HOLDER                      EXPIRES AT\n"
    Lock.all.each { |row|
      holder = row.holder.empty? ? "<UNCLAIMED>" : row.holder
      output += "%-18s | %-30s | %-16s\n" % [row.lockname, holder, row.expires]
    }

    jsonrpc_success output
  end

  chatop :release_lock,
  /lock release (?<lockname>.*)/,
  "lock release <lockname> - Release the named lock so a new holder can obtain it" do
    name = jsonrpc_params[:lockname]
    begin
      Lock.release(name)
    rescue ActiveRecord::ActiveRecordError => e
      jsonrpc_failure "Failed to release lock #{name} with error: #{e}"
    end

    jsonrpc_success "Released lock #{name}"
  end

  chatop :packages,
  /packages (?<package_manager>.*)/,
  "packages <package_manager> - Get info about packages for a given package manager" do
    package_manager = jsonrpc_params[:package_manager]
    begin
      packages = Package.for_package_manager(package_manager)
      count = packages.count
      last_created = packages.most_recently_created
      last_published = packages.most_recently_published
      last_updated = packages.most_recently_updated
      output = <<~EOS
        Packages for #{package_manager} (count: #{count}):
        ---
        Most recently published: #{last_published.name}
          last_published_at #{last_published.last_published_at}
        ---
        Most recently created: #{last_created.name}
          created_at #{last_created.created_at}
        ---
        Most recently updated: #{last_updated.name}
          updated_at #{last_updated.updated_at}
      EOS
      jsonrpc_success output
    rescue ArgumentError => e
      jsonrpc_failure e
    end
  end

  chatop :package,
  /package (?<package_manager>\S*) (?<package_name>\S*)/,
  "package <package_manager (#{PACKAGE_MANAGER_LIST})> <package_name> - Get info about a package by a given package manager and name" do
    package_manager, package_name = jsonrpc_params[:package_manager], jsonrpc_params[:package_name]
    packages = Package.for_package_manager(package_manager).with_name(package_name)
    output = <<~EOS
    ```
    #{packages.inspect}
    ```
    EOS

    jsonrpc_success output
  end

  chatop :package_override,
  /package (?<package_manager>\S*) (?<package_name>\S*) override (?<repository_nwo>\S*)/,
  "package <package_manager (#{PACKAGE_MANAGER_LIST})> <package_name> override <repository_nwo> - " do
    package_manager, package_name, repository_nwo  = jsonrpc_params[:package_manager], jsonrpc_params[:package_name], jsonrpc_params[:repository_nwo]
    package = Package.for_package_manager(package_manager).with_name(package_name).first
    if package.nil?
      return jsonrpc_failure "Package #{package_manager}:#{package_name} not found. Use map if you want to map a completely unmapped package."
    end

    repo = Repository.find_by(nwo: repository_nwo)
    if repo.nil?
      return jsonrpc_failure "Repo #{repository_nwo} not found"
    end

    PackageToRepoMapping::OverrideMatcher.record_match!(package, repo)

    jsonrpc_success "Remapped #{package_manager}:#{package_name} to #{repository_nwo}"
  end

  chatop :package_map,
  /package (?<package_manager>\S*) (?<package_name>\S*) map (?<repository_nwo>\S*)/,
  "package <package_manager (#{PACKAGE_MANAGER_LIST})> <package_name> map <repository_nwo> - " do
    package_manager, package_name, repository_nwo  = jsonrpc_params[:package_manager], jsonrpc_params[:package_name], jsonrpc_params[:repository_nwo]
    package = Package.for_package_manager(package_manager).with_name(package_name).first
    unless package.nil?
      return jsonrpc_failure "Package #{package_manager}:#{package_name} already mapped. Use override if you want to override the mapping"
    end

    package_manager_obj = Types::PackageManager.find { |pm| pm.name == package_manager.to_sym }
    if package_manager_obj.nil?
      return jsonrpc_failure "Package manager #{package_manager} not found.  Valid values are: #{PACKAGE_MANAGER_LIST}"
    end
    package_manager_id = package_manager_obj.id

    repo = Repository.find_by(nwo: repository_nwo)
    if repo.nil?
      return jsonrpc_failure "Repo #{repository_nwo} not found"
    end

    package = Package.create! name: package_name, package_manager: package_manager_id
    PackageToRepoMapping::OverrideMatcher.record_match!(package, repo)

    jsonrpc_success "Mapped #{package_manager}:#{package_name} to #{repository_nwo}"
  end

  chatop :clear_package_mapping,
  /package (?<package_manager>\S*) clear_mapping (?<package_name>\S*)/,
  "package <package_manager (#{PACKAGE_MANAGER_LIST})> clear_mapping <package_name> - " do
    package_manager, package_name = jsonrpc_params[:package_manager], jsonrpc_params[:package_name]

    package_manager_obj = Types::PackageManager.find { |pm| pm.name == package_manager.to_sym }
    package = Package.for_package_manager(package_manager).with_name(package_name).first

    if package_manager_obj.nil?
      return jsonrpc_failure "Package manager #{package_manager} not found.  Valid values are: #{PACKAGE_MANAGER_LIST}"
    end

    if package.nil?
      return jsonrpc_failure "Package #{package_name} not found"
    else
      package.update!(repository_id: nil, repository_id_certainty: 0)
      jsonrpc_success "Cleared Mapping for #{package_manager}:#{package_name}"
    end
  end

  chatop :explain,
  /explain (?<query>.*)/,
  "explain <query> - EXPLAIN a SQL query" do
    query = jsonrpc_params[:query]
    sql = "EXPLAIN #{query}"
    begin
      results = ActiveRecord::Base.connected_to(role: :reading) do
        ActiveRecord::Base.connection.execute(sql)
      end

      output = "```\n"
      row_count = 0
      results.rows.each do |row|
        row_count += 1

        output += <<~EOS
        *************************** #{row_count}. row ***************************
          Select Type: #{row[1]}
                Table: #{row[2]}
           Partitions: #{row[3]}
                 Type: #{row[4]}
        Possible Keys: #{row[5]}
                  Key: #{row[6]}
              Key Len: #{row[7]}
                  Ref: #{row[8]}
                 Rows: #{row[9]}
             filtered: #{row[10]}
                Extra: #{row[11]}

        EOS
      end
      output += "```"
      jsonrpc_success output
    rescue => e
      jsonrpc_failure e
    end
  end

  chatop :insights,
  /insights rebuild (?<org_id>.*)/,
  "insights rebuild <org_id> - rebuild the dep insights table for the org" do
    org_id = jsonrpc_params[:org_id]

    if org_id.nil?
      return jsonrpc_failure "Organization id is a required argument, make sure you pass in a valid id"
    end

    # Adds org to backfill table, backfills it, and builds materialized view for org
    DependencyInsightsBackfill.org_to_backfill(github_owner_id: org_id, source: "chatop").backfill

    jsonrpc_success "Rebuilt dependent counts for org: #{org_id}"
  end

  chatop :help, /help/, "Lists available ChatOps" do
    # Clone a list of our ChatOps so that we don't accidentally mess anything up!
    chatops = self.class.chatops.clone.sort

    list_of_commands = chatops.map do |name, chatop|
      "*#{name}* - #{chatop[:help]}"
    end

    jsonrpc_success <<~EOS
    :dependencies: Dependency Graph ChatOps:
      #{list_of_commands.join("\n  ")}
    EOS
  end

  chatop :audit_github_owner, /audit github owner (?<owner_id>\d+)/, "Determines if " do
    owner_id = jsonrpc_params[:owner_id].to_i
    # Set local variables so we can set them in the connected_to block below
    repos_count, manifest_count, package_release_dependents_count, backfill_record = 0, 0, 0, nil

    ActiveRecord::Base.connected_to(role: :reading) do
      repos_count = Repository.where(github_owner_id: owner_id).count
      manifest_count = Manifest.joins(:repository).where(dg_repositories: { github_owner_id: owner_id }).count
      package_release_dependents_count = Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count
      backfill_record = DependencyInsightsBackfill.find_by(github_owner_id: owner_id)
    end

    output = <<~EOS
      Counts for GitHub Owner ID #{owner_id}:
      • Repositories: #{repos_count}
      • Manifests: #{manifest_count}
      • PackageReleaseDependentCounts: #{package_release_dependents_count}
      • Backfill: #{backfill_record.inspect}
    EOS
    jsonrpc_success output
  end

  chatop :audit_abstract_repo_dependencies,
  /audit abstract repo dependencies (?<package_manager>\S*) (?<package_name>\S*)/,
  "audit abstract repo dependencies <package_manager (#{PACKAGE_MANAGER_LIST})> <package_name> - Given a package manager and name, delete ARDs if they no longer exist in their original repo." do
    package_manager, package_name = jsonrpc_params[:package_manager], jsonrpc_params[:package_name]

    begin
      deleted_count = AbstractRepositoryDependency.delete_orphans(package_name, package_manager)
      output = <<~EOS
        :dependencies2: Audited abstract repository dependencies for #{package_name}. #{deleted_count} orphan #{"dependency".pluralize(deleted_count)} deleted.
      EOS
      jsonrpc_success output
    rescue => e
      jsonrpc_failure e
    end
  end

  chatop :package_import,
  /package import (?<registry>\S*) (?<package_name>\S*)(\s(?<package_version>\S*))?/,
  "package import <registry> <package_name> [<package_version> if Actions] - Downloads an individual package from its respective registry." do
    registry, package_name, package_version = jsonrpc_params[:registry].to_sym, jsonrpc_params[:package_name], jsonrpc_params[:package_version]
    begin
      releases_count = OneOffImporters.run!(registry, package_name: package_name, package_version: package_version)
      jsonrpc_success ":matrix-animated: Imported #{releases_count} #{"release".pluralize(releases_count)} of *#{package_name}* from #{registry}"
    rescue => e
      jsonrpc_failure e
    end
  end

  chatop :clearly_defined_import,
  /clearly_defined import (?<registry>\S*) (?<package_name>\S*)(\s(?<package_version>\S*))?/,
  "clearly_defined import <registry> <package_name> [package_version] - Imports license data from Clearly Defined for a single package." do
    registry, package_name, package_version = jsonrpc_params[:registry].to_sym, jsonrpc_params[:package_name], jsonrpc_params[:package_version]

    begin
      ospo_package_managers = Ingest::PackageMetadataProcessor::OSPO_DG_SUPPORTED_ECOSYSTEMS
        .map { |pm| Ingest::PackageMetadataProcessor.ospo_type_to_package_manager(pm.to_s) }

      valid_types = Types::PackageManager.to_a
        .filter { |pm| ospo_package_managers.include?(pm) }

      begin
        pm = Types::PackageManager.coerce(registry)
        # message unimportant; just want this to be caught in the rescue block
        raise "invalid type" if !valid_types.include?(pm)
        package_manager = pm.to_i
      rescue
        return jsonrpc_failure "Invalid package manager. Must be one of: #{valid_types.join(', ')}"
      end

      if package_version.blank?
        package_releases = PackageRelease.where(package_manager: package_manager, package_name: package_name).includes(:attributions)
      else
        package_releases = PackageRelease.where(package_manager: package_manager, package_name: package_name, name: package_version).includes(:attributions)
      end

      if package_releases.count < 1
        return jsonrpc_failure "Could not find local package: `#{registry}:#{package_name}@#{package_version}`"
      end

      client = ClearlyDefined.new
      definitions = client.get_definitions(package_releases)

      responses = []

      package_releases.each do |package_release|
        old_license = package_release.license || "<empty>"
        old_attr_count = package_release.attributions.count
        package_release_definition = definitions[package_release]
        package_name = package_release.package_name
        package_manager = package_release.package_manager
        version = package_release.version

        client.process_package_version_licenses(package_release_definition, package_release, package_name, package_manager, version, nil)

        package_release.reload
        new_license = package_release.license || "<empty>"
        new_attr_count = package_release.attributions.count

        responses << "#{package_name}@#{version}: #{old_license} (#{old_attr_count} attributions) -> #{new_license} (#{new_attr_count} attributions)"
      end

      jsonrpc_success "Imported license and attribution data for `#{registry}:#{package_name}` from ClearlyDefined:\n```\n#{responses.join("\n")}\n```"
    rescue => e
      jsonrpc_failure e
    end
  end
end
