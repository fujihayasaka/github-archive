# typed: true
# frozen_string_literal: true

require "chatops-controller"

module Chatops
  class DependencyGraphController < ApplicationController
    # These are staff only commands
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    BATCH_SIZE = 100
    include ::Chatops::Controller

    chatops_help "Commands for working with the dependency graph"
    chatops_namespace :dependency_graph

    private def verify_authenticity_token?
      false # robots do this
    end

    def validate_repo(nwo_or_id) # rubocop:todo GitHub/UseRestfulActions
      if /\A[0-9]+\Z/.match(nwo_or_id)
        Repository.exists?(nwo_or_id) && nwo_or_id.to_i
      else
        repo = Repository.nwo(nwo_or_id)
        repo.present? && repo.id
      end
    end

    chatop :redetect_owner,
      /redetect_(owner|org) (?<owner>.*)?/,
      "redetect_owner [user/org] - redetect all manifests for all repos owned by the given owner" do
        rpc_params = jsonrpc_params.permit(:owner, :message_id)
        owner_name = rpc_params.fetch(:owner)
        owner = User.find_by_login(owner_name)
        if owner
          repos_count = ActiveRecord::Base.connected_to(role: :reading) { Repository.where(owner_id: owner.id).count }

          DependencyGraphManageOwnerDependenciesJob.perform_later(owner.id, task: :redetect)

          chatop_send "Queued redetect job for #{repos_count} repos belonging to #{owner_name}"
        else # No such org
          chatop_send "No owner found with the name '#{owner_name}'"
        end
      end

    chatop :redetect,
      /redetect (?<repo>.*)?/,
      "redetect [repo] - redetect all manifests for the given repo" do
        rpc_params = jsonrpc_params.permit(:repo, :message_id)
        repo = rpc_params.fetch(:repo)
        validated_id = validate_repo(repo)
        if validated_id
          begin
            RepositoryDependencyManifestInitializationJob.perform_now(validated_id)
            chatop_send "Redetection complete for #{repo}"
          rescue => e # rubocop:todo Lint/GenericRescue
            chatop_send "Error performing RepositoryDependencyManifestInitializationJob: #{e.inspect}"
          end
        else # Repository does not exist
          chatop_send "Repository #{repo} does not exist"
        end
      end

    chatop :clear_owner,
      /clear_(owner|org) (?<owner>.*)?/,
      "clear_owner [user/org] - clear all manifests for all repos owned by the given owner" do
        rpc_params = jsonrpc_params.permit(:owner, :message_id)
        owner_name = rpc_params.fetch(:owner)
        owner = User.find_by_login(owner_name)
        if owner
          repos_count = ActiveRecord::Base.connected_to(role: :reading) { Repository.where(owner_id: owner.id).count }

          DependencyGraphManageOwnerDependenciesJob.perform_later(owner.id, task: :clear)
          chatop_send "Queued clear job for #{repos_count} repos belonging to #{owner_name}"
        else # No such org
          chatop_send "No owner found with the name '#{owner_name}'"
        end
      end

    chatop :clear,
      /clear (?<repo>.*)?/,
      "clear [repo | repo1,repo2,...,repoN] - runs the 'clear manifests' action on the given repository, or CSV list of repositories" do
        rpc_params = jsonrpc_params.permit(:repo, :message_id)
        arg = rpc_params.fetch(:repo)
        repos = arg.split(",")
        if repos.length < 1
          chatop_send "at least one Repository NWO or ID is required"
        else
          submitted = 0
          repos.each do |repo|
            validated_id = validate_repo(repo)
            if validated_id
              RepositoryDependencyClearDependencies.perform_later(validated_id)
              submitted += 1
            end
          end
          chatop_send "Clear dependencies jobs submitted for #{submitted} of #{repos.length} requested repositories"
        end
      end

    chatop :disable_for_org_archived_repos,
      /disable_for_org_archived_repos (?<org>.*)?/,
      "disable_for_org_archived_repos [org] - disables dependency graph for all archived repositories in an org" do
        rpc_params = jsonrpc_params.permit(:org, :message_id)
        org_name = rpc_params.fetch(:org)
        org = Organization.find_by_login(org_name)
        if org
          RepositoryDependencyDisableOrgArchivedReposJob.perform_later(org, User.staff_user)
          chatop_send "Enqueued job to disable dependency graph on all archived repos under #{org_name}."
        else # No such org
          chatop_send "No org found with the name '#{org_name}'"
        end
      end
  end
end
