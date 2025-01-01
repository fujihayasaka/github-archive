require_relative "../../lib/repository_finder"
require "dependency_graph/connection"

class LoadPackageMetadataJob < RetryJob
  include RepositoryFinder

  queue_as :ospo_package_metadata

  def perform(release, persist_data: true)
    begin
      # Skip processing this release blocklisted packages
      if Ingest::Blocklist.blocklisted_package?(release)
        Instrument.increment("etl.ospo.ingest.blocklisted",
                             package_manager: package_manager,
                             persist_data: persist_data.to_s)
        return
      end
      @release = release
      @persist_data = persist_data
      @package_name = release.package_name
      @package_manager = release.package_manager

      if persist_data
        persist_ospo_data
      else
        dry_run_ospo_data
      end

      Instrument.increment("etl.ospo.ingest.processed",
                           package_manager: package_manager,
                           persist_data: persist_data.to_s)
    rescue ActiveRecord::ActiveRecordError => e
      # TODO: revisit this. we do want to let the job retry on transient SQL errors
      #       but more detail in the "rescue" clause may be needed to do that
      Instrument.increment("etl.ospo.ingest.failure",
                           package_manager: package_manager,
                           error_class: e.class.to_s,
                           persist_data: persist_data.to_s)
      Failbot.report(e,
        "gh.aqueduct.queue.name" => queue_name,
        "gh.aqueduct.job.name" => "LoadPackageMetadataJob", "gh.dryrun" => (!persist_data).to_s
      )
      raise e
    rescue StandardError => e
      Instrument.increment("etl.ospo.ingest.failure",
                           package_manager: package_manager,
                           error_class: e.class.to_s,
                           persist_data: persist_data.to_s)
      Failbot.report(e,
        "gh.aqueduct.queue.name" => queue_name,
        "gh.aqueduct.job.name" => "LoadPackageMetadataJob",
        "gh.dryrun" => (!persist_data).to_s
      )
      raise e
    end
  end


  private
  attr_reader :release, :package_manager, :package_name, :persist_data

  PACKAGES_TABLE = Package.table_name.freeze
  RELEASES_TABLE = PackageRelease.table_name.freeze
  # Array of columns to update for repo mappings
  REPO_FIELDS = %w(repository_id repository_id_certainty source_url)

  def package_label
    if package_manager == Types::PackageManager[:pip]
      ManifestAdapters::Pip::DependencyString.normalize_package_name(package_name)
    end
  end

  def license
    release.license
  end

  def clearly_defined_score
    release.clearly_defined_score.to_i
  end

  def repository_id
    # Assumption release.source_url is set to a valid github url upstream by parser
    release_source_url = release.source_url

    return if release_source_url.blank?
    return @repository_id if defined?(@repository_id)

    repo_url =  Ingest::GitHubUrl.new(release_source_url)
    return nil unless repo_url&.valid?

    repo = find_repo(nwo: "#{repo_url.owner}/#{repo_url.name}")

    return @repository_id = nil if repo.nil? || !repo.public?
    @repository_id = repo.github_repository_id
  end

  def repository_id_certainty
    return PackageToRepoMapping::Certainty::NULL if repository_id.blank?

    # TODO: ship initially with this more conservative value, to avoid
    # corner cases where OSPO data destructively overwrites authoritative
    # PMAs etc. - later, post-validation of OSPO data, we could update
    # to POSITIVE_MATCH and backfill from the source topic
    PackageToRepoMapping::Certainty::CLEARLY_DEFINED_MATCH
  end

  def source_url
    return if repository_id.blank?

    release.source_url
  end

  def update_repo_mapping(table:, field:)
    raise(ArgumentError, "Invalid field #{field} for repo mapping") unless REPO_FIELDS.include?(field)
    "(CASE
      WHEN (COALESCE(#{table}.repository_id_certainty, 0) < VALUES(repository_id_certainty))
        THEN VALUES(#{field})
      ELSE #{table}.#{field}
      END)"
  end

  def published_at
    encode_date(release.published_at)
  end

  def unpublished_at
    encode_date(release.unpublished_at)
  end

  # Current Granularity is set to date
  # https://github.com/github/hydro-schemas/blob/33bb210108821d3d5150cea666e5ac6735fa7046/proto/hydro/schemas/package_license_gateway/clearlydefined/v0/package_metadata.proto#L23
  def encode_date(date)
    return if date.blank?

    return date if date.is_a? String
    return date.strftime("%F %T") if date.respond_to?(:strftime)
    raise ArgumentError, "Invalid date #{date.inspect}"
  end

  def encoded
    Versioning::VersionParser.parse(release.version, allow_named_versions: Types::PackageManager.allows_named_versions?(package_manager)).encoded.to_i
  rescue Versioning::NoEncodedVersionError
    nil
  end

  def persist_ospo_data
    Instrument.time_dist("etl.ospo.ingest.package_metadata.dist.time",
                         package_manager: package_manager,
                         persist_data: persist_data.to_s) do
      DependencyGraph::Connection.with_read_committed(role: :writing) do
        DependencyGraph.throttler.throttle(:"dependency-graph") do
          Package.upsert({
            name: package_name,
            package_manager: package_manager,
            label: package_label,
            repository_id: repository_id,
            repository_id_certainty: repository_id_certainty,
            last_published_at: published_at,
          },
          on_duplicate: Arel.sql(ActiveRecord::Base.sanitize_sql ["
            last_published_at = COALESCE(#{PACKAGES_TABLE}.last_published_at, :published_at),
            repository_id = #{update_repo_mapping(table: PACKAGES_TABLE, field: 'repository_id')},
            repository_id_certainty = #{update_repo_mapping(table: PACKAGES_TABLE, field: 'repository_id_certainty')},
            updated_at = :updated_at",
            {
              published_at: published_at,
              updated_at: Time.now
            },
          ]))
        end

        inserted_package = Package.find_by(name: package_name, package_manager: package_manager)

        DependencyGraph.throttler.throttle(:"dependency-graph") do
          PackageRelease.
            upsert({
              package_id: inserted_package.id,
              name: release.version,
              package_name: package_name,
              package_manager: package_manager,
              source_url: source_url,
              repository_id: repository_id,
              repository_id_certainty: repository_id_certainty,
              clearly_defined_score: clearly_defined_score,
              license: release.license,
              encoded: encoded,
              published_at: published_at,
              unpublished_at: unpublished_at,
            },
            on_duplicate: Arel.sql(ActiveRecord::Base.sanitize_sql ["
              license = COALESCE(:release_license, license),
              clearly_defined_score = GREATEST(COALESCE(#{RELEASES_TABLE}.clearly_defined_score, 0), :clearly_defined_score),
              repository_id = #{update_repo_mapping(table: RELEASES_TABLE, field: 'repository_id')},
              source_url = #{update_repo_mapping(table: RELEASES_TABLE, field: 'source_url')},
              repository_id_certainty = #{update_repo_mapping(table: RELEASES_TABLE, field: 'repository_id_certainty')},
              published_at = COALESCE(#{RELEASES_TABLE}.published_at, :published_at),
              unpublished_at = COALESCE(#{RELEASES_TABLE}.unpublished_at, :unpublished_at),
              updated_at = :updated_at",
              {
                clearly_defined_score: clearly_defined_score,
                release_license: license,
                published_at: published_at,
                unpublished_at: unpublished_at,
                updated_at: Time.now
              },
              ])
            )
        end

        package_version_id = PackageRelease.find_by(package_name: package_name, package_manager: package_manager, name: release.version).id

        # In most cases, a release will have between 0 and 1 attributions, but we have outliers where this is they
        # run into the thousands of individual contributors for some ecosystems we currently ingest.
        release.attributions.each_slice(100) do |attributions|
          DependencyGraph.throttler.throttle(:"dependency-graph") do
            Attribution.upsert_all(
              attributions.map do |data|
                {
                  dg_package_versions_id: package_version_id,
                  attribution: data
                }
              end
            )
          end
        end
      end
    end
  end

  def dry_run_ospo_data
    found_package = Package.find_by(name: package_name, package_manager: package_manager)
    found_release = found_package&.releases&.find_by(name: release.version)

    if found_package.present?
      fields_to_update = {}
      fields_to_update[:last_published_at] = published_at unless found_package.last_published_at
      if found_package.repository_id_certainty < repository_id_certainty
        fields_to_update[:repository_id] = repository_id
        fields_to_update[:repository_id_certainty] = repository_id_certainty
      end
      DependencyGraph.logger.info("Updating package",
        "gh.dryrun" => true,
        "gh.dependency_graph.package.name" => package_name,
        "gh.dependency_graph.package_manager" => package_manager.name,
        "gh.dependency_graph.package.fields_to_update" => fields_to_update.to_json
      )
    else
      DependencyGraph.logger.info("Creating package",
        "gh.dryrun" => true,
        "gh.dependency_graph.package.name" => package_name,
        "gh.dependency_graph.package_manager" => package_manager.name,
        "gh.dependency_graph.package.fields_to_update" => {
          name: package_name,
          package_manager: package_manager,
          label: package_label,
          repository_id: repository_id,
          repository_id_certainty: repository_id_certainty,
          last_published_at: published_at,
        }.to_json
      )
    end

    if found_release.present?
      fields_to_update = {}
      fields_to_update[:license] = license if license
      fields_to_update[:published_at] = published_at unless found_release.published_at
      fields_to_update[:unpublished_at] = unpublished_at unless found_release.unpublished_at
      fields_to_update[:clearly_defined_score] = clearly_defined_score if clearly_defined_score > found_release.clearly_defined_score.to_i
      if found_release.repository_id_certainty < repository_id_certainty
        fields_to_update[:repository_id] = repository_id
        fields_to_update[:source_url] = source_url
        fields_to_update[:repository_id_certainty] = repository_id_certainty
      end
      DependencyGraph.logger.info("Updating package release",
        "gh.dryrun" => true,
        "gh.dependency_graph.package.name" => package_name,
        "gh.dependency_graph.package_manager" => package_manager.name,
        "gh.dependency_graph.package.fields_to_update" => fields_to_update.to_json,
        "gh.dependency_graph.package.version" => release.version,
      )
    else
      DependencyGraph.logger.info("Creating package release",
        "gh.dryrun" => true,
        "gh.dependency_graph.package.name" => package_name,
        "gh.dependency_graph.package_manager" => package_manager.name,
        "gh.dependency_graph.package.version" => release.version,
        "gh.dependency_graph.package.fields_to_update" => {
          name: release.version,
          package_name: package_name,
          package_manager: package_manager,
          source_url: source_url,
          repository_id: repository_id,
          repository_id_certainty: repository_id_certainty,
          clearly_defined_score: release.clearly_defined_score,
          license: release.license,
          encoded: encoded,
          published_at: published_at,
          unpublished_at: unpublished_at
        }.to_json,
      )
    end
  end

end
