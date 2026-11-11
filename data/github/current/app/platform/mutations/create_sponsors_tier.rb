# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateSponsorsTier < Platform::Mutations::Base
      description "Create a new payment tier for your GitHub Sponsors profile."

      def self.async_user_or_org(user_or_org_or_login)
        if user_or_org_or_login.is_a?(String)
          Loaders::ActiveRecord.load(::User, user_or_org_or_login, column: :login)
        else
          Promise.resolve(user_or_org_or_login)
        end
      end

      def self.async_api_can_modify?(permission, **inputs)
        specified_sponsorable = inputs[:sponsorable] || inputs[:sponsorable_login]
        sponsorable_promise = async_user_or_org(specified_sponsorable || permission.viewer)

        sponsorable_promise.then do |sponsorable|
          unless sponsorable
            raise Platform::Errors::Execution.new("`sponsorableId` or `sponsorableLogin` is required")
          end

          permission.access_allowed?(:admin_sponsors_listing,
            resource: sponsorable,
            current_org: sponsorable.organization? ? sponsorable : nil,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["user", "admin:org"]

      argument :sponsorable_id, ID, "The ID of the user or organization who owns the GitHub Sponsors profile. " \
        "Defaults to the current user if omitted and sponsorableLogin is not given.", required: false,
        loads: Interfaces::Sponsorable
      argument :sponsorable_login, String, "The username of the user or organization who owns the GitHub Sponsors " \
        "profile. Defaults to the current user if omitted and sponsorableId is not given.", required: false
      argument :amount, Integer, "The value of the new tier in US dollars. Valid values: " \
        "1-#{::SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS}.", required: true
      argument :is_recurring, Boolean, "Whether sponsorships using this tier should happen monthly/yearly or just " \
        "once.", required: false, default_value: true
      argument :repository_id, ID, "Optional ID of the private repository that sponsors at this tier should gain " \
        "read-only access to. Must be owned by an organization.", required: false, loads: Objects::Repository
      argument :repository_owner_login, String, "Optional login of the organization owner of the private " \
        "repository that sponsors at this tier should gain read-only access to. Necessary if repositoryName is " \
        "given. Will be ignored if repositoryId is given.", required: false
      argument :repository_name, String, "Optional name of the private repository that sponsors at this tier " \
        "should gain read-only access to. Must be owned by an organization. Necessary if repositoryOwnerLogin is " \
        "given. Will be ignored if repositoryId is given.", required: false
      argument :welcome_message, String, "Optional message new sponsors at this tier will receive.", required: false
      argument :description, String, "A description of what this tier is, what perks sponsors might receive, what " \
        "a sponsorship at this tier means for you, etc.", required: true
      argument :publish, Boolean, "Whether to make the tier available immediately for sponsors to choose. Defaults " \
        "to creating a draft tier that will not be publicly visible.", required: false, default_value: false

      field :sponsors_tier, Objects::SponsorsTier, "The new tier.", null: true

      def resolve(amount:, description:, is_recurring: true, sponsorable: nil, sponsorable_login: nil, repository: nil, welcome_message: nil, publish: false, repository_owner_login: nil, repository_name: nil)
        raise Errors::Unprocessable.new("GitHub Sponsors is not available") unless GitHub.sponsors_enabled?

        if amount <= 0
          raise Errors::Unprocessable.new("Please specify an amount between $1 and " \
            "#{::SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN} USD")
        end

        unless repository
          if repository_name.present? && repository_owner_login.blank?
            raise Errors::Unprocessable.new("Please specify the login of the owner of the repository")
          end

          if repository_name.blank? && repository_owner_login.present?
            raise Errors::Unprocessable.new("Please specify the name of the repository")
          end
        end

        viewer = context[:viewer]
        repo_promise = if repository
          Promise.resolve(repository)
        elsif repository_name && repository_owner_login
          Platform::Helpers::RepositoryByNwo.async_repository_with_owner(
            permission: context[:permission],
            viewer: viewer,
            login: repository_owner_login,
            name: repository_name,
          )
        else
          Promise.resolve(nil)
        end

        specified_sponsorable = sponsorable || sponsorable_login
        sponsorable_promise = self.class.async_user_or_org(specified_sponsorable || viewer)
        sponsorable_promise.then do |sponsorable|
          sponsors_listing = sponsorable.sponsors_listing

          unless sponsors_listing
            raise Errors::Unprocessable.new("#{sponsorable} does not have a GitHub Sponsors profile")
          end

          repo_promise.then do |repo|
            tier = begin
              Sponsors::CreateSponsorsTier.call(
                custom: false,
                sponsors_listing: sponsors_listing,
                description: description,
                amount: amount,
                viewer: viewer,
                is_recurring: is_recurring,
                welcome_message: welcome_message,
                repository_id: repo&.id,
              )
            rescue ::Sponsors::CreateSponsorsTier::UnprocessableError => err
              raise Errors::Unprocessable.new(err.message)
            rescue ::Sponsors::CreateSponsorsTier::ForbiddenError => err
              raise Errors::Forbidden.new(err.message)
            end

            if publish
              begin
                Sponsors::PublishSponsorsTier.call(tier: tier, viewer: viewer)
              rescue ::Sponsors::PublishSponsorsTier::UnprocessableError => err
                raise Errors::Unprocessable.new(err.message)
              end
            end

            { sponsors_tier: tier }
          end
        end
      end
    end
  end
end
