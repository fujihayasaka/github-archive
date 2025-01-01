# typed: strict
# frozen_string_literal: true

require "chatops-controller"
require "github_chatops_extensions"

module Chatops
  class AdvancedSecurityController < ApplicationController
    include ::Chatops::Controller
    include ::GitHubChatopsExtensions::Checks::Includable::Room
    include SecretScanning::Features::FeatureFlagHelper

    ALLOWED_ROOMS = T.let(["#cs-architects-ops", "#ghas-billing-ops", "#sales-chatops", "#security-products-enablement-ops"].freeze, T::Array[String])

    # CAP not required on chatops controllers
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    before_action -> { T.bind(self, Chatops::AdvancedSecurityController); require_in_room(ALLOWED_ROOMS) }, except: :list

    chatops_namespace :ghas
    chatops_help "Commands for working with GitHub Advanced Security licensing"
    chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/). Try re-running the command or ask for help in [#ghas-billing](https://github.slack.com/archives/C01UGP0385T)."

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    sig { returns(T::Boolean) }
    private def verify_authenticity_token?
      false # robots do this
    end

    sig { params(type: T.nilable(String), slug: String).returns(T.nilable(T.any(Organization, Business))) }
    private def find_entity(type:, slug:)
      case type
      when "org", "organization"
        Organization.find_by(login: slug)
      when "business", "enterprise"
        Business.find_by(slug: slug)
      when nil
        organization = Organization.find_by(login: slug)
        business = Business.find_by(slug: slug)
        if !organization.nil? && !business.nil?
          raise ArgumentError.new(%Q(Ambiguous entity "#{slug}". Please refine your query as "org:#{slug}" or "business:#{slug}".))
        end
        business || organization
      else
        raise ArgumentError.new("Invalid entity type: #{slug}")
      end
    end

    sig { params(entity: T.any(Organization, Business)).returns(String) }
    def self.printable_entity(entity)
      case entity
      when Organization
        "organization:#{entity.login}"
      when Business
        "business:#{entity.slug}"
      else
        T.absurd(entity)
      end
    end

    sig { params(type: T.nilable(String), slug: String).returns(String) }
    private def printable_requested_entity(type:, slug:)
      if type.present?
        "#{type}:#{slug}"
      else
        "#{slug}"
      end
    end

    sig { params(staff_user: String, room_id: String, entity: T.any(Organization, Business)).void }
    def self.send_backfill_complete_notification(staff_user:, room_id:, entity:)
      GitHub::Chatterbox.client.say!(room_id, "@#{staff_user}, the backfill for #{self.printable_entity(entity)} is now complete! You can now run `.ghas summary #{self.printable_entity(entity)}` to get a summary of the committer data. :tadaco:")
    end

    sig { returns(User) }
    memoize private def current_actor
      User.find_by!(login: params[:user])
    end

    chatop :find_enterprise,
           /find_enterprise\s+(?:(?<entity_type>(org|organization)):\s*)?(?<entity_slug>\S+)/,
           "find_enterprise org|organization:slug - Find an enterprise by org|organization" do

      entity_type = jsonrpc_params[:entity_type]
      entity_slug = jsonrpc_params.require(:entity_slug)

      entity = begin
        find_entity(type: entity_type, slug: entity_slug)
      rescue ArgumentError => e
        chatop_send(e.to_s)
        return
      end

      if entity.nil?
        chatop_send("#{printable_requested_entity(type: entity_type, slug: entity_slug)} could not be found.")
        return
      end

      if entity.is_a?(Business)
        enterprise = entity.slug
      else
        if entity.business.nil?
          chatop_send("#{printable_requested_entity(type: entity_type, slug: entity_slug)} is not part of any enterprise.")
          return
        end

        enterprise = entity.business&.slug
      end

      chatop_send("The #{entity_type} #{entity_slug} has a business of #{enterprise}. To summary this, run `.ghas summary business:#{enterprise}`.")
      return
    end

    chatop :summary,
           /(summary|track)\s+(?:(?<entity_type>(org|organization|business|enterprise)):\s*)?(?<entity_slug>\S+)(?:\s+repos:(?<repos>\s*.+))?/,
           "summary org|business:slug - Get the summary of the Advanced Security status for a particular entity" do

      entity_type = jsonrpc_params[:entity_type]
      entity_slug = jsonrpc_params.require(:entity_slug)
      entity_nwos = jsonrpc_params[:repos]

      entity = begin
        find_entity(type: entity_type, slug: entity_slug)
      rescue ArgumentError => e
        chatop_send(e.to_s)
        return
      end

      if entity.nil?
        chatop_send("#{printable_requested_entity(type: entity_type, slug: entity_slug)} could not be found.")
        return
      end

      billable_entity = AdvancedSecurityLicense.billable_entity(entity)
      unless billable_entity.present?
        chatop_send("Could not find a billable entity for #{self.class.printable_entity(entity)}.")
        return
      end

      name = if entity.advanced_security_billable_entity?
        self.class.printable_entity(billable_entity)
      else
        "#{ self.class.printable_entity(billable_entity) } (the parent business of #{ self.class.printable_entity(entity) })"
      end

      purchased = if billable_entity.advanced_security_purchased?
        if billable_entity.advanced_security_license.unlimited_seats?
          "Unlimited"
        else
          billable_entity.advanced_security_license.seats
        end
      else
        "Not Purchased"
      end

      summary = billable_entity.advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::Bundled).entity_summary

      consumed = []
      if billable_entity.advanced_security_products_bundled?
        consumed << "* Consumed Licenses: #{summary.active_committers}"
      end

      [GitHub::Turboghas::SKU::CodeSecurity, GitHub::Turboghas::SKU::SecretSecurity].each do |sku|
        consumed << "* #{sku.title} Licenses: #{billable_entity.advanced_security_license_for_sku(sku:).entity_summary.active_committers}"
      end

      result = [
        "Advanced Security License for #{name}",
        "* Purchased Licenses: #{purchased}",
        *consumed,
        "* Maximum Licenses: #{summary.maximum_committers}",
      ]



      skus = if billable_entity.advanced_security_products_bundled?
        [GitHub::Turboghas::SKU::Bundled]
      else
        [GitHub::Turboghas::SKU::CodeSecurity, GitHub::Turboghas::SKU::SecretSecurity]
      end

      skus.each do |sku|
        if (ghes_committers = billable_entity.advanced_security_license_for_sku(sku:).ghes_committers).present?
          result << "* GHES #{sku.title} Licenses: #{ghes_committers.user_ids.size + ghes_committers.unmatched.size}"
        end
      end

      unless entity.advanced_security_billable_entity?
        entity_summary = entity.advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::Bundled).entity_summary

        consumed_seats_for_entity = entity_summary.active_committers
        maximum_seats_for_entity = entity_summary.maximum_committers

        entity_consumed = []

        if billable_entity.advanced_security_products_bundled?
          entity_consumed << "* Consumed Licenses: #{consumed_seats_for_entity}"
        end

        [GitHub::Turboghas::SKU::CodeSecurity, GitHub::Turboghas::SKU::SecretSecurity].each do |sku|
          entity_consumed << "* #{sku.title} Licenses: #{billable_entity.advanced_security_license_for_sku(sku:).entity_summary.active_committers}"
        end

        result.concat([
          "Usage for #{self.class.printable_entity(entity)}",
          *entity_consumed,
          "* Maximum Licenses: #{maximum_seats_for_entity}",
        ])
      end

      unless entity_nwos.blank?
        nwos = entity_nwos.split(",").map(&:strip).map(&:downcase)
        invalid_nwos = nwos.reject { |nwo| nwo.count("/") == 1 }
        if invalid_nwos.any?
          chatop_send("We found #{invalid_nwos.count} invalid org/repo values in your `repos:` key, not in the right format. The following org/repo values were invalid: #{invalid_nwos.join(",")}. Please make sure to use the org/repo format in the repos key. E.G repos: org1/repo1,org2/repo2")
          return
        end
        owner_ids = if entity.is_a?(Organization)
          [entity.id]
        else
          entity.organization_ids
        end
        repos = Repository.with_names_with_owners(nwos).where(Repository::arel_table[:owner_id].in(owner_ids))
        unless repos.count == nwos.count
          missing = Set.new(nwos) - repos.map(&:name_with_owner).map(&:downcase).to_set
          chatop_send("We found #{missing.count} org/repo values that did not exist in the org or enterprise. The following org/repo values were not found: #{missing.join(", ")}")
          return
        end

        repo_ids = repos.map(&:id).to_a

        repo_summary = AdvancedSecurityLicense.summary(entity: billable_entity, repository_ids: repo_ids, sku: GitHub::Turboghas::SKU::Bundled)
        consumed_committers = repo_summary.active_committers
        maximum_committers = repo_summary.maximum_committers
        additional_committers = repo_summary.additional_committers

        repo_consumed = []

        if billable_entity.advanced_security_products_bundled?
          repo_consumed << "* Consumed Licenses: #{consumed_committers}"
        end

        [GitHub::Turboghas::SKU::CodeSecurity, GitHub::Turboghas::SKU::SecretSecurity].each do |sku|
          repo_consumed << "* #{sku.title} Licenses: #{AdvancedSecurityLicense.summary(entity: billable_entity, repository_ids: repo_ids, sku:).active_committers}"
        end

        repository_phrasing = repos.count == 1 ? "repository" : "repositories"

        result.concat([
          "Usage for #{repository_phrasing}",
          *repo_consumed,
          "* Maximum Licenses: #{maximum_committers}",
          "* Additional Licenses: #{additional_committers}",
        ])
      end

      chatop_send(result.join("\n"))
    end

  end
end
