namespace :package_to_repo_mapping do
  task run: :environment do
    # deprecated
  end

  task update: :environment do
    # deprecated
  end

  desc "Provide a CSV file to override package to repo mappings"
  task :override, [:csv_path] => :environment do |_task, args|
    CSV.foreach(args[:csv_path], headers: :first_row) do |row|
      ["Package Manager", "Package Name", "Repository"].each do |k|
        raise "Missing #{k} field in CSV row" if row[k].nil? || row[k] == ""
      end
      package_manager_name = row["Package Manager"].strip
      package_name = row["Package Name"].strip
      repo_nwo = row["Repository"].strip

      puts "Overriding #{package_manager_name} package #{package_name} to #{repo_nwo}"

      package_manager = Types::PackageManager[package_manager_name.to_sym]
      package = Package.where(name: package_name, package_manager: package_manager).first!

      if repo_nwo == "none"
        github_repo_id = nil
      else
        owner, repo_name = repo_nwo.split("/", 2)
        github_repo_id = Ingest::RepoIndex::GitHubRepository.joins("INNER JOIN users owners ON repositories.owner_id = owners.id").where("owners.login = ? AND repositories.name = ?", owner, repo_name).first!.id
      end

      if package.repository_id == github_repo_id
        puts "#{package_manager_name} package #{package_name} already mapped to #{repo_nwo}!"
      else
        PackageToRepoMapping::OverrideMatcher.record_match!(package, github_repo_id)
      end
    end
  end
end
