# typed: true
# frozen_string_literal: true

module Memexes
  module ProjectLinkDependency
    include MemexesHelper
    include ProjectsHelper
    extend ActiveSupport::Concern
    extend T::Helpers
    requires_ancestor { ApplicationController }

    NOT_FOUND_ERROR = "Sorry, that project cannot be found."
    UNLINK_ERROR = "An error occurred removing this project. Please try again."
    ACCESS_ERROR_PREFIX = "You must have at least read access to these projects to add or remove them: "
    UPDATE_LINK_ERROR_PREFIX = "An error occurred while adding or removing the following projects: "

    def unlink_project(context:, redirect_path:, publish_remove_event:)
      memex = context.memex_projects.find_by(id: params[:memex_project_id])
      if memex.nil? || !memex.viewer_can_read?(current_user)
        return redirect_with_error(:not_found, NOT_FOUND_ERROR, redirect_path)
      end

      publish_remove_event.call(memex: memex)

      unless context.memex_project_links.destroy_by(memex_project_id: memex.id).any?
        return redirect_with_error(:unprocessable_entity, UNLINK_ERROR, redirect_path)
      end

      # XHR clients (Rails kebab via fetch) and JSON clients (React `verifiedFetchJSON`)
      # both expect an empty 204 instead of a redirect to the html projects page.
      return head :no_content if request.xhr? || request.format.json?

      flash[:skip_memexes_controller_index_hydro] = "true"
      redirect_back_or_to redirect_path
    end

    def update_project_links(update_links_params:, context:, redirect_path:, publish_add_event:, publish_remove_event:)
      if update_links_params.nil? || update_links_params.empty?
        # JSON clients (React "Link a project" dialog) get a bare 204 instead of a
        # redirect to the html projects page when there's nothing to do.
        return head :no_content if request.xhr? || request.format.json?
        return redirect_back_or_to redirect_path
      end

      operations = { link: [], unlink: [] }
      errors = { access: [], update: [] }
      owner = T.let(context.is_a?(Organization) ? context : context.owner, T.any(Organization, User))

      owner.memex_projects.where(number: update_links_params.keys.map(&:to_i)).each do |memex|
        next errors[:access] << "#{GitHub.url}#{memex.url}" unless memex.viewer_can_read?(current_user)

        operations[update_links_params[memex.number.to_s] == "on" ? :link : :unlink] << memex
      end

      operations[:link].each do |memex|
        next if context.memex_project_links.where(memex_project: memex).exists?
        next publish_add_event.call(memex: memex) if context.memex_project_links.create(memex_project: memex)

        errors[:update] << "#{GitHub.url}#{memex.url}"
      end

      unless operations[:unlink].empty?
        items_destroyed = context.memex_project_links.destroy_by(memex_project_id: operations[:unlink].map(&:id))
        unlinked_memex_ids = items_destroyed.map(&:memex_project_id)
        operations[:unlink].each do |memex|
          next publish_remove_event.call(memex: memex) if unlinked_memex_ids.include?(memex.id)

          errors[:update] << memex.url
        end
      end

      error_message = +""

      unless errors[:access].empty?
        error_message << ACCESS_ERROR_PREFIX << errors[:access].join(", ") << "."
      end

      unless errors[:update].empty?
        error_message << " " if error_message.present?
        error_message << UPDATE_LINK_ERROR_PREFIX << \
          errors[:update].map { |url| "#{url}" }.join(", ") << ". Please try again."
      end

      # JSON clients (React "Link a project" dialog) get a bare 204 on success or a
      # 422 with the same `flash[:error]` message string we'd render for HTML clients.
      # The dialog surfaces the message inline and keeps itself open for retry.
      if request.xhr? || request.format.json?
        return head :no_content if error_message.blank?
        return render(json: { error: error_message }, status: :unprocessable_entity)
      end

      flash[:error] = error_message
      flash[:skip_memexes_controller_index_hydro] = "true"
      redirect_back_or_to redirect_path
    end

    def project_suggestions(scope, context, only_memex_templates: nil, min_permission_level: "read", q: nil, limit: nil)
      projects = if scope == "recent"
        suggester = ProjectSuggester.new(
          viewer: current_user,
          context: context,
          load_memex_projects: true,

          # Only return MemexProjects that are templates
          only_memex_templates: only_memex_templates,

          # Don't include Classic projects when suggesting Memex projects
          load_classic_projects: false,
        )

        suggester.recent_memex_projects(min_permission_level: min_permission_level)
      else
        q ||= ""
        q << " is:template" if only_memex_templates

        search_result = context.owner.search_memex_projects(
          query: Search::Queries::MemexProjectQuery.new(q),
          min_permission_level: min_permission_level,
          viewer: current_user,
          limit: limit,
        )

        search_result.memex_projects
      end

      selected_ids = Set.new(context.memex_projects.ids)

      {
        projects: projects.map do |memex|
          memex.to_repo_projects_suggestion_hash(
            is_selected: selected_ids.include?(memex.id)
          )
        end
      }
    end

    private

    def redirect_with_error(status, message, redirect_path)
      # Match the success path: XHR + JSON clients get the bare status; other clients
      # see a flash + redirect rendered server-side.
      return head status if request.xhr? || request.format.json?

      flash[:error] = message
      redirect_back_or_to redirect_path
    end
  end
end
