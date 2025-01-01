# typed: true
# frozen_string_literal: true

require "chatops-controller"
require "github_chatops_extensions"

module Chatops
  class GlobalIdController < ApplicationController
    include ::Chatops::Controller

    chatops_namespace :global_id
    chatops_help "Commands for getting the global_id info for an entity"
    chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/). Try re-running the command or ask for help in [#octoshift](https://github.slack.com/archives/CV0E7204X)."

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    # Opt-out of all conditional access and secondary authn checks, since these chatops are run by Hubbers
    # from Slack and the routes for triggering them are only accessible through our internal network
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    private def verify_authenticity_token?
      false # robots do this
    end

    chatop :find,
           /find (?<entity_name>\S+)/,
           "find <entity_name> - get the global_id info for an Repo/Org/Enterprise" do

      entity_name = jsonrpc_params.require(:entity_name)

      if entity_name.include?("/")
        repo, org, user, enterprise = find_entity_from_nwo(entity_name)
        chatop_send(build_response(repo, org, user, enterprise))
        return
      end

      repo, org, user, enterprise, is_ambiguous = find_entity(String(entity_name))

      if is_ambiguous
        chatop_send(build_ambiguous_response(repo, org, user, enterprise))
        return
      end

      chatop_send(build_response(repo, org, user, enterprise))
    end


    chatop :decode,
            /decode (?<global_id>\S+)/,
            "decode <global_id> - decode the global_id into an entity (User, Repository, Organization, or Enterprise )" do

      global_id = jsonrpc_params.require(:global_id)

      if global_id.nil?
        chatop_send("Please provide a global_id to decode.")
        return
      end

      begin
        repo, org, user, enterprise = find_entity_from_next_global_id(global_id)
        chatop_send(build_response(repo, org, user, enterprise))
      rescue Platform::Errors::NotFound
        chatop_send("Invalid global_id #{global_id.inspect}, please enter a valid global_id.")
      end
    end

    private

    sig { params(repo: T.nilable(Repository), org: T.nilable(Organization), user: T.nilable(User), enterprise: T.nilable(Business)).returns(String) }
    def build_response(repo, org, user, enterprise)
      response = String.new(":bufo-detective: Here's what I found:\n\n")
      if enterprise
        response << "*Enterprise:*\n"
        response << "Id: `#{enterprise.next_global_id}`\n"
        response << "Name: `#{enterprise.name}`\n"
        response << "Slug: `#{enterprise.slug}`\n\n"
      end
      if org
        response << "*Organization:*\n"
        response << "Id: `#{org.next_global_id}`\n"
        response << "Name: `#{org.login}`\n\n"
      end
      if user
        response << "*User:*\n"
        response << "Id: `#{user.next_global_id}`\n"
        response << "Name: `#{user.login}`\n\n"
      end
      if repo
        response << "*Repository:*\n"
        response << "Id: `#{repo.next_global_id}`\n"
        response << "Name: `#{repo.name_with_owner}`\n\n"
      end
      response
    end

    sig { params(repo: T.nilable(Repository), org: T.nilable(Organization), user: T.nilable(User), enterprise: T.nilable(Business)).returns(String) }
    private def build_ambiguous_response(repo, org, user, enterprise)
      response = String.new(":bufo-detective: Multiple entities found:\n\n")
      if enterprise
        response << "*Enterprise:*\n"
        response << "Id: `#{enterprise.next_global_id}`\n"
        response << "Name: `#{enterprise.name}`\n"
        response << "Slug: `#{enterprise.slug}`\n\n"
      end
      if org
        response << "*Organization:*\n"
        response << "Id: `#{org.next_global_id}`\n"
        response << "Name: `#{org.login}`\n"
        business = org.business
        if business
          response << "*Owned by Enterprise:*\n"
          response << "Id: `#{business.next_global_id}`\n" if business.next_global_id
          response << "Name: `#{business.name}`\n" if business.name
          response << "Slug: `#{business.slug}`\n" if business.slug
          response << "\n"
        end
        response << "\n"
      end
      if user
        response << "*User:*\n"
        response << "Id: `#{user.next_global_id}`\n"
        response << "Name: `#{user.login}`\n\n"
      end
      if repo
        response << "*Repository:*\n"
        response << "Id: `#{repo.next_global_id}`\n"
        response << "Name: `#{repo.name_with_owner}`\n\n"
      end
      response
    end

    sig { params(entity_name: String).returns([T.nilable(Repository), T.nilable(Organization), T.nilable(User), T.nilable(Business), T::Boolean]) }
    def find_entity(entity_name)
      org, user, enterprise = ActiveRecord::Base.connected_to(role: :reading) do
        [
          Organization.find_by(login: entity_name),
          User.find_by(login: entity_name),
          Business.find_by(slug: entity_name),
        ]
      end

      is_ambiguous = org.present? & enterprise.present? ||
                     user.present? & enterprise.present?

      # users an orgs are really the same thing, so we need to check if we have both
      user = nil if user.present? && org.present?
      enterprise = org&.business if enterprise.nil? && org.present?

      # No repository for this lookup, so return nil as first parameter
      [nil, org, user, enterprise, is_ambiguous]
    end

    sig { params(nwo: String).returns([T.nilable(Repository), T.nilable(Organization), T.nilable(User), T.nilable(Business)]) }
    def find_entity_from_nwo(nwo)
      repo = Repository.nwo(nwo)
      if repo.nil?
        chatop_send("Repository #{nwo.inspect} does not exist.")
        return [nil, nil, nil, nil]
      end

      org = nil
      user = nil
      enterprise = nil

      if repo.owner.is_a?(Organization)
        org = repo.owner
        enterprise = org.business
      else
        user = repo.owner
      end

      [repo, org, user, enterprise]
    end

    sig { params(global_id: String).returns([T.nilable(Repository), T.nilable(Organization), T.nilable(User), T.nilable(Business)]) }
    def find_entity_from_next_global_id(global_id)
      decoded_id = Platform::Helpers::NodeIdentification.from_global_id(global_id)

      user = nil
      org = nil
      enterprise = nil
      repo = nil

      case decoded_id.first
      when "Enterprise"
        enterprise = ActiveRecord::Base.connected_to(role: :reading) { Business.find_by(id: decoded_id.last) }
      when "Organization"
        org = ActiveRecord::Base.connected_to(role: :reading) { Organization.find_by(id: decoded_id.last) }
        enterprise = org.business if org
      when "Repository"
        repo = ActiveRecord::Base.connected_to(role: :reading) do
          if FeatureFlag.vexi.enabled?(:repos_domain_controllers, default: false)
            Repositories.domain.by_id(decoded_id.last)
          else
            Repository.find_by(id: decoded_id.last)
          end
        end
        owner = repo.owner if repo
        if owner.is_a?(Organization)
          org = owner
          enterprise = org.business
        else
          user = owner
        end
      when "User"
        user = ActiveRecord::Base.connected_to(role: :reading) { User.find_by(id: decoded_id.last) }
      else
        raise "Unable to find anything for global_id #{global_id.inspect}"
      end

      [repo, org, user, enterprise]
    end
  end
end
