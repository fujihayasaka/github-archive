namespace :transitions do
  task populate_abstract_repository_dependencies: :environment do
    now = Time.now.to_s(:db)

    ActiveRecord::Base.connection.remove_index :abstract_repository_dependencies,
      [:package_name, :repository_id, :package_manager]

    SlicedRange.new(min: Repository.minimum(:id), max: Repository.maximum(:id), size: 10_000).each do |range|
      sql = <<-SQL.strip_heredoc
        INSERT INTO #{AbstractRepositoryDependency.table_name} (
          repository_id,
          package_manager,
          package_name,
          created_at,
          updated_at
        )
          SELECT repository_id, package_manager, package_name, '#{now}', '#{now}'
          FROM #{Manifest.table_name}
          INNER JOIN #{ManifestDependency.table_name} specs on #{Manifest.table_name}.id = specs.manifest_id
          WHERE repository_id BETWEEN #{range.first} AND #{range.last}
          GROUP BY 1, 2, 3
      SQL
      ActiveRecord::Base.connection.execute(sql)
    end

    ActiveRecord::Base.connection.add_index :abstract_repository_dependencies,
      [:package_name, :repository_id, :package_manager],
      {
        unique: true,
        name:  :index_abstract_repo_dep_uniq_package
      }
  end

  task populate_abstract_package_dependencies: :environment do
    now = Time.now.to_s(:db)

    ActiveRecord::Base.connection.remove_index :abstract_package_dependencies,
      [:package_name, :dependent_id, :package_manager]

    SlicedRange.new(min: Package.minimum(:id), max: Package.maximum(:id), size: 10_000).each do |range|
      sql = <<-SQL.strip_heredoc
        INSERT INTO #{AbstractPackageDependency.table_name} (
          dependent_id,
          package_manager,
          package_name,
          created_at,
          updated_at
        )
          SELECT package_id, package_manager, package_name, '#{now}', '#{now}'
          FROM #{PackageRelease.table_name}
          INNER JOIN dep_graph_dependency_specifications specs on #{PackageRelease.table_name}.id = specs.dependent_id
          WHERE package_id BETWEEN #{range.first} AND #{range.last}
          GROUP BY 1, 2, 3
      SQL
      ActiveRecord::Base.connection.execute(sql)
    end

    ActiveRecord::Base.connection.add_index :abstract_package_dependencies,
      [:package_name, :dependent_id, :package_manager],
      {
        unique: true,
        name:  :index_abstract_package_dep_uniq_package
      }
  end

  task normalize_manifest_paths: :environment do
    ActiveRecord::Base.connection.execute <<~SQL
      DELETE dups, dependencies FROM #{Manifest.table_name} dups
      INNER JOIN #{Manifest.table_name} newer ON dups.repository_id = newer.repository_id
      INNER JOIN #{ManifestDependency.table_name} dependencies ON dependencies.manifest_id = dups.id
      WHERE newer.last_pushed_at > dups.last_pushed_at
        AND (newer.path = "/" OR newer.path = "" OR newer.path IS NULL)
        AND (dups.path = "/" OR dups.path = "" OR dups.path IS NULL)
    SQL

    ActiveRecord::Base.connection.execute <<~SQL
      UPDATE #{Manifest.table_name}
      SET path = ""
      WHERE path = "/" OR path IS NULL
    SQL
  end

  # These are no longer needed since we got rid of RepoIndex
  # task backfill_name_with_owner: :environment do
  #   puts "Backfilling Repositories"
  #   Repository.where("github_repository_id IS NOT NULL").find_each do |r|
  #     repo = Ingest::RepoIndex::Repository.find_by(repository_id: r.github_repository_id)
  #     r.update_attribute(:nwo, "#{repo.owner_name}/#{repo.name}") if repo.present?
  #   end

  #   puts "Backfilling Package Releases"
  #   PackageRelease.where("repository_id IS NOT NULL").find_each do |pr|
  #     repo = Ingest::RepoIndex::Repository.find_by(repository_id: pr.repository_id)
  #     pr.update_attribute(:repository_nwo, "#{repo.owner_name}/#{repo.name}") if repo.present?
  #   end

  #   puts "Backfilling Packages"
  #   Package.where("repository_id IS NOT NULL").find_each do |pr|
  #     repo = Ingest::RepoIndex::Repository.find_by(repository_id: pr.repository_id)
  #     pr.update_attribute(:repository_nwo, "#{repo.owner_name}/#{repo.name}") if repo.present?
  #   end
  # end

  def each_with_lock(query)
    con = ActiveRecord::Base.connection
    begin
      last_id = query.maximum(:id)
    rescue ActiveRecord::StatementInvalid
      puts "cant find last id"
      last_id = 0
    end
    counter = 0

    query.in_batches(of: 20, load: false) do |rel|
      con.transaction do
        rel.lock(true).each do |dep|
          counter += 1
          if counter > 1_000
            counter = 0
            puts "Processed #{dep.id} of #{last_id}"
          end
          yield(dep)
        end
      end
    end
  end

  def update_package_name(dep)
    name = ManifestAdapters::Pip::DependencyString.normalize_package_name(dep.package_name)
    if dep.package_name != name
      dep.update_columns(package_name: name)
    end
  rescue ActiveRecord::RecordNotUnique => e
    puts "Cannot update package_name[#{dep.package_name}] for id[#{dep.id}]. (dup key err)"
    puts "\t#{e.message}"
  end

  def update_package_name_and_label(dep)
    label = dep.package_name
    name = ManifestAdapters::Pip::DependencyString.normalize_package_name(dep.package_name)

    dep.update_columns(package_name: name, package_label: label)
  rescue ActiveRecord::RecordNotUnique => e
    puts "Cannot update package_name[#{dep.package_name}] for manifest[#{dep.id}] . (dup key err)"
    puts "\t#{e.message}"
  end

  task normalize_pip_packages: :environment do
    pip = Types::PackageManager[:pip]
    counter = 0
    ## Update the manifest tables
    puts "normalizing ManifestDependency..."
    Manifest.for_package_manager(pip).find_in_batches(batch_size: 2000) do |manifests|
      manifests.each do |manifest|
        counter += 1
        if counter > 1_000
          counter = 0
          puts "At #{manifest.id}"
        end

        Manifest.transaction do
          manifest = manifest.lock!
          manifest.dependencies.where(package_label: nil).order(last_seen_at_revision: :desc).each do |dep|
            abstract_dep = AbstractRepositoryDependency.for_package_manager(pip).where(package_name: dep.package_name)
                             .from("#{AbstractRepositoryDependency.quoted_table_name} USE INDEX (tmp_index_abstract_repo_deps_lookups)")
                             .first
            update_package_name(abstract_dep) if abstract_dep
            update_package_name_and_label(dep)
          end
        end
      end
    end
  end
end
