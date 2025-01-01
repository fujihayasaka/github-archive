# typed: true
# frozen_string_literal: true

require "logger"

module GitHub::Pages::Management
  class ListReplicas



    attr_reader :page_id, :page_deployment_id, :delegate

    def initialize(page_id:, page_deployment_id:, delegate:)
      @page_id = page_id
      @page_deployment_id = page_deployment_id
      @delegate = delegate
      nil
    end

    # Perform gets the results and logs them to stdout through `delegate`
    # This is used mainly for chatops in dotcom and `ghe-dpages` commands in GHES
    def perform
      results = get_results

      if results.empty?
        delegate.puts "No replicas for page_id=#{page_id}!"
        return true
      end

      deployment_ids_and_refs = ApplicationRecord::Pages.connection.select_rows(Arel.sql(<<-SQL, page_deployment_ids: results.map(&:last).compact))
        SELECT id, ref_name FROM page_deployments WHERE id IN (:page_deployment_ids)
      SQL
      deployment_refs = deployment_ids_and_refs.each_with_object({}) do |(id, ref_name), memo|
        memo[id] = ref_name
      end

      results.each do |host, revision, page_deployment_id|
        path = GitHub::Routing.dpages_storage_path(page_id, revision: revision)
        if page_deployment_id
          delegate.puts "#{host}:#{path} (page_deployment_id=#{page_deployment_id.inspect} ref=#{deployment_refs[page_deployment_id]})"
        else
          delegate.puts "#{host}:#{path} (page_deployment_id=#{page_deployment_id.inspect} ref=#{page_ref})"
        end
      end

      true
    end

    # Get the list of replicas for a given deployment.
    # We can't depend on ActiveRecord here since one goal of this method
    # is to find replicas in the database after a repo or page is deleted.
    # Returns a list of replicas as [:dfs-host, :revision, :deployment_id]
    def get_results
      if page_deployment_id
        # get specific: just one deployment, please!
        ApplicationRecord::Pages.connection.select_rows(Arel.sql(<<-SQL, page_id: page_id, page_deployment_id: page_deployment_id))
          SELECT pages_replicas.host, page_deployments.revision, pages_replicas.pages_deployment_id FROM pages
          INNER JOIN page_deployments ON page_deployments.page_id = pages.id
          INNER JOIN pages_replicas ON pages_replicas.pages_deployment_id = page_deployments.id
          WHERE pages.id = :page_id AND pages_replicas.pages_deployment_id = :page_deployment_id
        SQL
      else
        # be generic: grab all replicas for all deployments!
        # fetch legacy (nil) deployments' replicas
        nil_pages_deployment_id = ApplicationRecord::Pages.connection.select_rows(Arel.sql(<<-SQL, page_id: page_id))
          SELECT pages_replicas.host, pages.built_revision, pages_replicas.pages_deployment_id FROM pages
          INNER JOIN pages_replicas ON pages_replicas.page_id = pages.id
          WHERE pages.id = :page_id AND pages_replicas.pages_deployment_id IS NULL
        SQL
        # add those to replicas with proper deployments.
        nil_pages_deployment_id + ApplicationRecord::Pages.connection.select_rows(Arel.sql(<<-SQL, page_id: page_id))
          SELECT pages_replicas.host, page_deployments.revision, page_deployments.id FROM pages
          INNER JOIN page_deployments ON page_deployments.page_id = pages.id
          INNER JOIN pages_replicas ON pages_replicas.pages_deployment_id = page_deployments.id
          WHERE pages.id = :page_id AND pages_replicas.pages_deployment_id IS NOT NULL
        SQL
      end
    end

    private

    def page_info
      return @page_info if @page_info

      page_info = ApplicationRecord::Pages.connection.select_all(Arel.sql(<<-SQL, page_id: page_id)).to_a.fetch(0)
        SELECT source, repository_id
        FROM pages
        WHERE pages.id = :page_id
      SQL

      repo_info = ApplicationRecord::Domain::Repositories.connection.select_all(Arel.sql(<<-SQL, repo_id: page_info.delete("repository_id"))).to_a.fetch(0)
        SELECT name, owner_id
        FROM repositories
        WHERE repositories.id = :repo_id
        AND repositories.active = 1
      SQL

      @page_info = page_info.merge(repo_info)

      user_id = @page_info.delete("owner_id")

      @page_info["login"] = ApplicationRecord::Domain::Users.connection.select_values(Arel.sql(<<-SQL, id: user_id)).fetch(0)
        SELECT users.login FROM users WHERE users.id = :id
      SQL

      @page_info
    end

    def page_ref
      @page_ref ||= if page_info["source"].to_s.start_with?("master")
        "master"
      elsif source = page_info["source"]
        source
      elsif page_info["name"].to_s.eql?("#{page_info["login"]}.#{GitHub.pages_host_name_v2}")
        "master" # this is username.github.io, which defaults to the master branch
      elsif page_info["name"].to_s.eql?("#{page_info["login"]}.#{GitHub.pages_host_name_v1}")
        "master" # this is username.github.com, which defaulted to the master branch in the olden days
      else
        "gh-pages"
      end
    end
  end
end
