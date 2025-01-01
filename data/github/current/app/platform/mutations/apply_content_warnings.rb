# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ApplyContentWarnings < Platform::Mutations::Base
      description "Apply content warnings to repositories."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :repository_ids, [ID], "Global relay IDs of repositories to which content warnings will be applied.", required: true, loads: Objects::Repository, as: :repositories
      argument :category, String, "Content warning category. E.g. 'mis_dis_information'", required: true
      argument :sub_category, String, "Content warning sub category. E.g. 'medical_scientific'", required: false
      argument :custom_sub_category, String, "Content warning custom sub category. E.g. 'dangerous content.'", required: false
      argument :forks, Boolean, "Apply content warnings to repository forks too.", required: false, default_value: false
      argument :notify_fork_owners, Boolean, "Send email notifications to fork owners too.", required: false, default_value: false
      argument :instructions, String, "Instructions for repository owners that are appended to the bottom of their email notification.", required: false

      argument :async, Boolean, "Whether or not to run operation in a background job. Should always be set to true. Is an arg for sake of backward compatibility.", required: false, default_value: false

      field :type, String, "The type of content warning that was applied.", null: true
      field :forks, Boolean, "Whether or not content warnings were applied to forks.", null: true
      field :successes, [Objects::Repository], "The repositories to which content warnings were applied (not including forks).", null: true
      field :failures, [Objects::Repository], "The repositories to which content warnings failed to be applied (not including forks).", null: true
      field :errors, [String], "The errors that caused `failures`.", null: true

      def self.async_api_can_modify?(permission, **_)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      def resolve(**params)
        repositories = params[:repositories]
        category = params[:category]
        sub_category = params[:sub_category]
        custom_sub_category = params[:custom_sub_category]
        forks = params[:forks]
        notify_fork_owners = params[:notify_fork_owners]
        instructions = params[:instructions]

        async = params[:async]

        category = nil if category.blank?
        sub_category = nil if sub_category.blank?
        custom_sub_category = nil if custom_sub_category.blank?
        instructions = nil if instructions.blank?

        response = { type: nil, forks: forks, successes: [], failures: [], errors: [] }

        if async
          repositories.each do |repo|
            begin
              response[:type] = repo.apply_content_warning_later(
                category,
                sub_category,
                custom_sub_category,
                actor: context[:actor],
                forks: forks,
                notify_fork_owners: notify_fork_owners,
                instructions: instructions,
              )
            rescue TrustSafety::ContentWarnings::ValidationError => error
              response[:failures].append(repo)
              response[:errors].append(error.message)
            end
          end
        else # Synchronous execution is deprecated and should not be invoked: https://github.com/github/github/pull/331559
          repositories.each do |repo|
            begin
              response[:type] = repo.set_content_warning(
                category,
                sub_category,
                custom_sub_category,
                actor: context[:actor],
                forks: forks,
                notify_fork_owners: notify_fork_owners,
                instructions: instructions,
              )
            end
            response[:successes].append(repo)
          rescue TrustSafety::ContentWarnings::ValidationError => error
            response[:failures].append(repo)
            response[:errors].append(error.message)
          end
        end

        response
      end
    end
  end
end
