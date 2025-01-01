# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module Helpers
      module Repository
        include Imports::Helpers::ContentCreation
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::Attribution

        # Gets the visibility of a repository.
        #
        # Returns an enum corresponding to
        # MonolithTwirp::Octoshift::Imports::V1::RepositoryVisibility
        def get_repository_visibility(repository)
          if repository.public?
            :REPOSITORY_VISIBILITY_PUBLIC
          elsif repository.private? && repository.visibility == ::Repository::PRIVATE_VISIBILITY
            :REPOSITORY_VISIBILITY_PRIVATE
          elsif repository.internal?
            :REPOSITORY_VISIBILITY_INTERNAL
          else
            :REPOSITORY_VISIBILITY_INVALID
          end
        end

        # Maps MonolithTwirp::Octoshift::Imports::V1::RepositoryVisibility
        # to a Repository model visibility
        #
        # Returns one of the following Repository visibilities
        # PUBLIC_VISIBILITY
        # PRIVATE_VISIBILITY
        # INTERNAL_VISIBILITY
        def map_visibility(twirp_repository_visibility)
          map =
            {
              REPOSITORY_VISIBILITY_PUBLIC: ::Repository::PUBLIC_VISIBILITY,
              REPOSITORY_VISIBILITY_PRIVATE: ::Repository::PRIVATE_VISIBILITY,
              REPOSITORY_VISIBILITY_INTERNAL: ::Repository::INTERNAL_VISIBILITY
            }
          map[twirp_repository_visibility.to_sym]
        end

        def map_visibility_string(twirp_repository_visibility)
          map =
            {
              REPOSITORY_VISIBILITY_PUBLIC: "public",
              REPOSITORY_VISIBILITY_PRIVATE: "private",
              REPOSITORY_VISIBILITY_INTERNAL: "internal"
            }
          map[twirp_repository_visibility.to_sym]
        end

        def update_visibility(repository, actor, visibility, is_archived)
          owner = repository.owner
          if visibility == :REPOSITORY_VISIBILITY_INTERNAL && !owner.business
            return Twirp::Error.canceled("Repository owner must be associated with an enterprise to set visibility to internal")
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            repository.toggle_visibility(
              actor: actor,
              visibility: map_visibility_string(visibility)
            ) unless get_repository_visibility(repository) == visibility

            if is_archived && !repository.archived?
              repository.set_archived
            elsif !is_archived && repository.archived?
              repository.unset_archived
            end
          end
        end

        def map_repository_topic_state(topic_state)
          map = {
            REPOSITORY_TOPIC_STATE_INVALID: nil,
            REPOSITORY_TOPIC_STATE_CREATED: :created,
            REPOSITORY_TOPIC_STATE_SUGGESTED: :suggested,
            REPOSITORY_TOPIC_STATE_DECLINED_NOT_RELEVANT: :declined_not_relevant,
            REPOSITORY_TOPIC_STATE_DECLINED_TOO_SPECIFIC: :declined_too_specific,
            REPOSITORY_TOPIC_STATE_DECLINED_PERSONAL_PREFERENCE: :declined_personal_preference,
            REPOSITORY_TOPIC_STATE_DECLINED_TOO_GENERAL: :declined_too_general
          }
          map[topic_state]
        end

        def page_visibility_valid?(repository, visibility)
          valid_visibilities = []
          if repository.org_members_can_create_public_pages? && repository.can_have_public_pages?
            valid_visibilities << "public"
          end

          if repository.org_members_can_create_private_pages? && repository.can_have_private_pages?
            valid_visibilities << "private"
          end

          valid_visibilities.include?(visibility)
        end

        def generate_page_visibility_error(repository, is_public)
          visibility = is_public ? "public" : "private"
          unless page_visibility_valid?(repository, visibility)
            return "Page visibility is set to #{visibility} but the organization's settings do not allow #{visibility} pages."
          end
          ""
        end

        def update_page_settings(repository, page_req)
          page_error = generate_page_visibility_error(repository, page_req.is_public)
          if page_error.present?
            return page_error
          end

          page = repository.build_page(public: page_req.is_public)
          page.set_source(source: page_req.source.presence, build_type: page_req.build_type.presence, ref_name: page_req.source_ref_name.presence, subdir: page_req.source_subdir.presence)

          # rebuild_pages will also save the page.
          repository.rebuild_pages(repository.import.creator)

          page.cname_error
        end

        def valid_repo_event_types
          @valid_repo_event_types ||= Hook::EventRegistry.for_target(::Repository).map(&:event_type) + [Hook::WildcardEvent]
        end

        def create_autolinks(repository, autolinks_req)
          autolinks_req.each do |autolink|
            attributes = Repositories::CreateKeyLinkAttributes.new(
              key_prefix: autolink.key_prefix,
              url_template: autolink.url_template
            )
            attributes.is_alphanumeric = autolink.is_alphanumeric unless autolink.is_alphanumeric.nil?
            Repositories.domain.key_links.create(attributes, repo_id: repository.id)
          end
        end

        def get_topic_model(name, url)
          topic = replica(Topic).find_by(name: name)
          return topic if topic

          Topic.create!(
            name: name,
            url: url
          )
        end

        def update_default_branch(repository, branch)
          return true if repository.empty?
          return true if branch.empty?
          return true if repository.default_branch == branch

          repository.update_default_branch(branch)
        end
      end
    end
  end
end
