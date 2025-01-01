# typed: true
# frozen_string_literal: true

require "chatops-controller"

module Chatops
  class BackupController < ApplicationController
    include ::Chatops::Controller

    # Staff only command
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    chatops_namespace :backup
    chatops_help "Commands for working with Git backups"
    chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/)"

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    private def verify_authenticity_token?
      false # robots do this
    end

    chatop :repo,
           /repo(?:\s+(?<nwo>\S+))?/,
           "repo <nwo> - Back up a repository right now" do

      nwo = jsonrpc_params.require(:nwo)
      repo = Repository.nwo(nwo)
      if repo.nil?
        chatop_send("Repository #{nwo} not found")
        return
      end

      begin
        repo.backup_ng!
        chatop_send("Repository #{nwo} (#{repo.id}) backed up")
      rescue GitRPC::Error => ex
        chatop_send("error: #{ex.message}")
      end
    end

    chatop :delete,
           /delete(?:\s+(?<nwo>\S+))?/,
           "delete <nwo> - Mark a repository backup for deletion" do

      nwo = jsonrpc_params.require(:nwo)
      repo = Repository.nwo(nwo)
      if repo.nil?
        chatop_send "Repository #{nwo} not found"
        return
      end

      begin
        repo.delete_backup
        chatop_send "Repository #{nwo} (#{repo.id}) backup marked for deletion"
      rescue GitBackups::DeleteError => ex
        chatop_send("error: #{ex.message}")
      end
    end
  end
end
