# typed: true
# frozen_string_literal: true

require "logger"
require "progeny"

module GitHub::Pages::Management
  class CheckReplicas
    class Replica
      attr_reader :page_deployment_id, :ref_name, :host, :revision

      def initialize(page_deployment_id, ref_name, host, revision)
        @page_deployment_id = page_deployment_id
        @ref_name = ref_name
        @host = host
        @revision = revision
        nil
      end

      def <=>(other)
        [page_deployment_id, host, revision] <=> [other.page_deployment_id, other.host, other.revision]
      end

      def signature
        "#{host}:#{revision}"
      end

      def hash
        signature.hash
      end

      def eql?(other)
        return false unless other.is_a?(Replica)

        signature.eql?(other.signature)
      end

      def ==(other)
        return false unless other.is_a?(Replica)

        page_deployment_id == other.page_deployment_id &&
          ref_name == other.ref_name &&
          host == other.host &&
          revision == other.revision
      end
    end

    attr_reader :page_id, :page_deployment_id, :delegate

    def initialize(page_id:, page_deployment_id: nil, delegate:)
      @page_id = page_id
      @page_deployment_id = page_deployment_id
      @delegate = delegate
      nil
    end

    def perform
      results = deployment_replicas.concat(legacy_replicas).uniq.sort

      results.group_by(&:page_deployment_id).each do |page_deployment_id, replicas|
        delegate.puts [
          "page_id=#{page_id}",
          "page_deployment_id=#{page_deployment_id < 0 ? "nil" : page_deployment_id}",
          "ref_name=#{replicas.map(&:ref_name).uniq.join(",")}",
        ].join(" ")
        replicas.each do |replica|
          path = GitHub::Routing.dpages_storage_path(page_id, revision: replica.revision)
          delegate.puts "  #{replica.host}:#{path} #{exists_on_disk(replica.host, path)}"
        end
      end

      true
    end

    private

    # Default timeout is 2s. On Enterprise allow a timeout of 10s.
    def timeout
      GitHub.enterprise? ? 10 : 2
    end

    def exists_on_disk(host, path)
      if delegate.ssh(host, "test -d #{path}", timeout: timeout)
        "ok"
      else
        "MISSING"
      end
    rescue Progeny::TimeoutExceeded
      "TIMED OUT!"
    end

    def deployment_replicas
      sql = Arel.sql(<<-SQL, page_id: page_id)
        SELECT page_deployments.id, page_deployments.ref_name, pages_replicas.host, page_deployments.revision FROM page_deployments
        INNER JOIN pages_replicas ON pages_replicas.pages_deployment_id = page_deployments.id
        WHERE page_deployments.page_id = :page_id
      SQL
      sql += Arel.sql(<<-SQL, page_deployment_id: page_deployment_id) if page_deployment_id
        AND page_deployments.id = :page_deployment_id
      SQL
      ApplicationRecord::Domain::PagesFromRepositories.connection.select_rows(sql).map { |id, ref_name, host, revision| Replica.new(id, ref_name, host, revision) }
    end

    def legacy_replicas
      results = ApplicationRecord::Domain::PagesFromRepositories.connection.select_rows(Arel.sql(<<-SQL, page_id: page_id))
        SELECT pages_replicas.host, pages.built_revision, pages.source FROM pages
        INNER JOIN pages_replicas ON pages_replicas.page_id = pages.id
        WHERE pages.id = :page_id AND pages_replicas.pages_deployment_id IS NULL
      SQL
      results.map { |host, revision, source| Replica.new(-1, ref_name_from_source(source), host, revision) }
    end

    def ref_name_from_source(source)
      if source.to_s.start_with?("master")
        "master"
      else
        "gh-pages"
      end
    end
  end
end
