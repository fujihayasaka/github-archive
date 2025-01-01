# typed: true
# frozen_string_literal: true

require "chatops-controller"
require "github_chatops_extensions"

module Chatops
  class ReposController < ApplicationController
    include ActionView::Helpers::NumberHelper
    include ::Chatops::Controller
    include ::GitHubChatopsExtensions::Checks::Includable::Room

    chatops_namespace :repos
    chatops_help "Commands for getting information about GitHub repositories"
    chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/). Try re-running the command or ask for help in [#code-scanning](https://github.slack.com/archives/CP9GMKJCE)."

    # CAP not required on chatops controllers
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    private def verify_authenticity_token?
      false # robots do this
    end

    private def send_each(name)
      out = []
      jsonrpc_params.require(name).split(/\s+/).each do |param|
        out << yield(param)
      end
      chatop_send(out.join("\n"))
      nil
    end

    chatop :spec,
           /spec (?<nwo>.+)/,
           "spec nwo - get the repository's network spec ('<network-id>/<repo-id>')" do

      send_each(:nwo) do |nwo|
        unless nwo.include?("/")
          chatop_send("Invalid nwo #{nwo.inspect}, please enter a repository in the format <owner>/<name>.")
          return
        end

        repo = Repository.nwo(nwo)

        if repo.nil?
          chatop_send("Repository #{nwo.inspect} does not exist.")
          return
        end

        "#{repo.network_id}/#{repo.id}"
      end
    end

    chatop :nwo,
           /nwo (?<id>.+)/,
           "nwo id - get the name with object for a repository" do

      send_each(:id) do |id_param|
        id = Integer(id_param, exception: false)

        if id.nil?
          chatop_send("Invalid id #{id_param.inspect}, please provide an integer ID.")
          return
        end

        repo = Repository.find_by(id: id)

        if repo.nil?
          chatop_send("Repository #{id_param.inspect} does not exist.")
          return
        end

        repo.nwo
      end
    end

    chatop :id,
           /id (?<nwo>.+)/,
           "id nwo - get the id for a repository based on the nwo" do

      send_each(:nwo) do |nwo|
        unless nwo.include?("/")
          chatop_send("Invalid nwo #{nwo.inspect}, please enter a repository in the format <owner>/<name>.")
          return
        end

        repo = Repository.nwo(nwo)

        if repo.nil?
          chatop_send("Repository #{nwo.inspect} does not exist.")
          return
        end

        repo.id.to_s
      end
    end

    chatop :global_relay_id,
    /global_relay_id (?<nwo>.+)/,
    "global_relay_id nwo - get the graphql node ids for a repository based on the nwo" do

      send_each(:nwo) do |nwo|
        unless nwo.include?("/")
          chatop_send("Invalid nwo #{nwo.inspect}, please enter a repository in the format <owner>/<name>.")
          return
        end

        repo = Repository.nwo(nwo)

        if repo.nil?
          chatop_send("Repository #{nwo.inspect} does not exist.")
          return
        end

        "global_relay_id: #{repo.global_relay_id}; next_global_id: #{repo.next_global_id}"
      end
    end

    chatop :releases,
           /releases (?<nwo>.+)/,
           "releases <nwo> - gets the total number and size of releases for a repository" do

      send_each(:nwo) do |nwo|
        unless nwo.include?("/")
          chatop_send("Invalid nwo #{nwo.inspect}, please enter a repository in the format <owner>/<name>.")
          return
        end

        repo = Repository.nwo(nwo)

        if repo.nil?
          chatop_send("Repository #{nwo.inspect} does not exist.")
          return
        end

        releases = repo.releases.includes(:release_assets)
        releases_binary_assets_size = releases.sum { |r| r.release_assets.sum(:size) }

        "#{releases.count} (#{number_to_human_size(releases_binary_assets_size)})"
      end
    end
  end
end
