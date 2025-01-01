# typed: true
# frozen_string_literal: true

require "github/pages/management/repair"

module GitHub::Pages::Management
  class ReplicationStatus
    MAX_BROKEN_REPOS_TO_PRINT = 20

    attr_reader :delegate

    def initialize(delegate:)
      @delegate = delegate
      nil
    end

    def perform
      if under_over_replicated_pages.empty?
        delegate.puts "Everything looks OK!"
      else
        delegate.puts "under/over-replicated pages:"
        under_over_replicated_pages.
          take(MAX_BROKEN_REPOS_TO_PRINT).
          each do |(page_id_and_deployment_id, replica_counts)|
            page_id = page_id_and_deployment_id.first
            page_deployment_id = page_id_and_deployment_id.last
            voting = replica_counts.find { |replica_count| replica_count.voting }
            non_voting = replica_counts.find { |replica_count| !replica_count.voting }
            ref = page_deployment_refs[page_deployment_id] || ref_for_page_info(page_infos[page_id])

            delegate.puts "  #{nwo_for_page(page_id)} (pages ref=#{ref} page_deployment_id=#{page_deployment_id.inspect}) " \
              "- #{[humanized_count(voting), humanized_count(non_voting)].compact.join(" and ")}"
          end

        if under_over_replicated_pages.size > MAX_BROKEN_REPOS_TO_PRINT
          delegate.puts "... and #{under_over_replicated_pages.size - MAX_BROKEN_REPOS_TO_PRINT} more"
        end

        delegate.puts "under/over-replicated pages total: #{under_over_replicated_pages.size}"
        delegate.puts ""
      end

      true
    end

    def under_over_replicated_pages
      @under_over_replicated_pages ||= \
        GitHub::Pages::Management::Repair.new(delegate: delegate).unhealthy_pages_replica_counts(limit: MAX_BROKEN_REPOS_TO_PRINT * 2).
          # Don't include pages with no copies
          reject { |replica| 0 == replica.replica_count }.
          # Make sure we count each page only once
          uniq { |replica| [replica.page_id, replica.page_deployment_id, replica.voting] }.
          # Show voting first, then non-voting, then sort by page_id, page_deployment_id, and lastly count
          sort_by do |replica|
            [replica.voting ? 1 : 0, replica.page_id, replica.page_deployment_id || -1, replica.replica_count || 0]
          end.
          # Group by page_id and page_deployment_id
          group_by { |replica| [replica.page_id, replica.page_deployment_id] }.to_a
    end

    def humanized_count(replica_count)
      return nil if replica_count.nil?

      voting_non_voting_word = replica_count.voting ? "voting replica" : "non-voting replica"
      "#{replica_count.replica_count} #{voting_non_voting_word.pluralize(replica_count.replica_count)}"
    end

    def nwo_for_page(page_id)
      info = page_infos[page_id]
      return "network/#{page_id}" if info.nil? || info["nwo"].empty?
      info["nwo"]
    end

    def ref_for_page_info(page_info)
      return nil if page_info.nil?
      if page_info["source"].to_s.start_with?("master")
        "master"
      elsif page_info["source"]
        page_info["source"]
      elsif page_info["name"].to_s.eql?("#{page_info["login"]}.#{GitHub.pages_host_name_v2}")
        "master" # this is username.github.io, which defaults to the master branch
      elsif page_info["name"].to_s.eql?("#{page_info["login"]}.#{GitHub.pages_host_name_v1}")
        "master" # this is username.github.com, which defaulted to the master branch in the olden days
      else
        "gh-pages"
      end
    end

    def page_infos
      @page_infos ||= begin
        page_ids = under_over_replicated_pages.
          map { |(page_id_and_deployment_id, _)| page_id_and_deployment_id.first }.compact
        return {} if page_ids.empty?

        page_infos = ApplicationRecord::Pages.connection.select_all(Arel.sql(<<-SQL, page_ids: page_ids)).to_a
          SELECT id, source, repository_id
          FROM pages
          WHERE pages.id IN (:page_ids)
        SQL

        repo_ids = page_infos.map { |row| row["repository_id"] }
        repo_infos = ApplicationRecord::Domain::Repositories.connection.select_all(Arel.sql(<<-SQL, repo_ids: repo_ids)).to_a
          SELECT id, name, owner_id
          FROM repositories
          WHERE repositories.id IN (:repo_ids)
          AND repositories.active = 1
        SQL

        infos = page_infos.map do |page_info|
          repo_info = repo_infos.find { |repo_info| repo_info["id"] == page_info["repository_id"] }.except("id")
          page_info.merge(repo_info).except("repository_id")
        end

        return {} if infos.empty?

        user_ids = infos.map { |row| row["owner_id"] }
        user_logins = ApplicationRecord::Domain::Users.connection.select_rows(Arel.sql(<<-SQL, ids: user_ids)).to_h
          SELECT users.id, users.login FROM users WHERE users.id IN (:ids)
        SQL

        infos.each_with_object({}) do |info, memo|
          owner_login = user_logins[info["owner_id"]]
          if owner_login
            info.delete("owner_id")
            info["login"] = owner_login
            info["nwo"] = "#{owner_login}/#{info["name"]}"
            memo[info["id"]] = info
          end
        end
      end
    end

    def page_deployment_refs
      @page_deployment_refs ||= begin
        page_deployment_ids = under_over_replicated_pages.
          take(MAX_BROKEN_REPOS_TO_PRINT).
          map { |(page_id_and_deployment_id, _)| page_id_and_deployment_id.last }.compact
        return {} if page_deployment_ids.empty?

        results = ApplicationRecord::Pages.connection.select_rows(Arel.sql(<<-SQL, page_deployment_ids: page_deployment_ids))
          SELECT id, ref_name FROM page_deployments WHERE id IN (:page_deployment_ids)
        SQL
        results.each_with_object({}) do |(id, ref_name), memo|
          memo[id] = ref_name
        end
      end
    end
  end
end
