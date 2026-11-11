# typed: true
# frozen_string_literal: true

module Search
  class RegistryPackageResultView
    attr_reader :source, :id, :name, :summary, :public, :downloads, :updated_at, :topics
    attr_accessor :package_url, :package
    alias :public? :public

    delegate :owner, :repository, :repository_name_with_owner, to: :package

    # Create a new RegistryPackageResultView from a `registry_package` document
    # hash returned from the ElasticSearch index.
    #
    # hash - Document Hash returned by ElasticSearch
    def initialize(hash, current_user: nil)
      @source = hash["_source"]
      @id = hash["_id"]
      @package = hash["_model"]
      # setting Actions Package type in search results in new Codesearch experience
      if FeatureFlag.vexi.enabled?(:search_action_packages, current_user, default: false) && action_package?(current_user)
        @source["package_type"] = "actions"
      end
      @name = source["name"]
      @summary = source["summary"]
      @public = source["public"]
      @downloads = source["downloads"].to_i
      @updated_at = Time.parse(source["updated_at"])

      @topics = source.fetch("ranked_topics", []).map do |ranked|
        ranked["applied"]
      end.compact
    end

    def owned_by_organization?
      owner.organization?
    end

    # Avoids calling repository.name_with_owner which may result in an additional query.
    # Package owner and repository are preloaded.
    def repo_name_with_owner
      "#{owner}/#{repository}"
    end

    def latest_version
      return @latest_version if @latest_version

      latest = source["versions"].find { |v| v["latest"] }
      latest ||= source["versions"].first

      @latest_version = latest.nil? ? "" : latest["version"]
    end

    def populate_results_data
      @repo = { name: repository&.name, owner_login: repository&.owner_display_login }
      v2 = package.instance_of?(PackageRegistry::PackageMetadata)
      if v2
        @color = "#046fb3"
        if repository.nil? && package.try(:repository_name_with_owner)
          nwo = package.repository_name_with_owner.split("/")
          @repo = { name: nwo.drop(1).join("/"), owner_login: nwo.first }
        end
      elsif package.try(:color)
        @color = package.color
      end
    end

    def for_frontend_rendering
      {
        id: @id,
        color: @color,
        downloads: @downloads,
        name: @name,
        repo: @repo,
        package_url: @package_url,
        package_type: @package_type,
        public: @public,
        source: @source,
        summary: @summary,
        topics: @topics,
        updated_at: @updated_at,
      }
    end

    def action_package?(actor)
      return false unless source.key?("package_subtype")
      return source["package_subtype"] == "actions" if source["package_subtype"] != "sig"
      version = latest_non_signature_version(actor)
      if version
        @latest_version = {
          version: version.containerMetadata.tag.name,
          latest: true,
          digest: version.containerMetadata.tag.digest,
          created_at: version.created_at,
          updated_at: version.updated_at,
        }
        @source["versions"].reject! { |v| v["latest"] }
        @source["versions"].unshift(@latest_version)
        version.aop?
      end
    end

    def latest_non_signature_version(actor)
      if package.instance_of?(PackageRegistry::PackageMetadata)
        @latest_non_signature_version = PackageRegistry::Twirp.metadata_client.get_container_latest_version(
          name: package.package["name"],
          namespace: package.package["namespace"],
          ecosystem: package.package["ecosystem"],
          actor: actor,
        )
      end
    end
  end
end
