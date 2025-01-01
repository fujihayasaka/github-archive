# typed: true
# frozen_string_literal: true

module Memexes
  module SharedMemexesControllerActions
    extend ActiveSupport::Concern
    include MemexesHelper
    include ColorHelper
    include ApplicationController::JsonDependency
    include ::Memexes::ThisRepositoryDependency
    include MemexProject::DefaultTemplates
    include GitHub::Tracing

    extend T::Helpers
    requires_ancestor { Memexes::GrantRoleOnCreateDependency }
    requires_ancestor { ApplicationController::AuthenticatedSystem }

    abstract!

    sig { abstract.returns(T.nilable(::User)) }
    def current_user; end

    SEARCH_RESULT_LIMIT = 8
    MAX_LIMIT_FOR_MEMEX_ITEMS = 25

    included do
      T.bind(self, T.class_of(ApplicationController))

      # shared actions dependencies
      #show
      depends_on_clusters ApplicationRecord::Collab,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests, only: [:show]
      depends_on_clusters ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Ballast,
        ApplicationRecord::Spokes,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Billing,
        ApplicationRecord::Notify, only: [:show], optional: true

      #create
      depends_on_clusters ApplicationRecord::Collab,
        ApplicationRecord::Repositories, only: [:create]
      depends_on_clusters ApplicationRecord::Iam,
        ApplicationRecord::Ballast,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries, only: [:create], optional: true

      #refresh
      depends_on_clusters ApplicationRecord::Collab,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests, only: [:refresh]
      depends_on_clusters ApplicationRecord::Iam,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Ballast,
        ApplicationRecord::Spokes,
        ApplicationRecord::Billing,
        ApplicationRecord::Notify, only: [:refresh], optional: true

      #update
      depends_on_clusters ApplicationRecord::Collab,
        ApplicationRecord::Repositories, only: [:update]
      depends_on_clusters ApplicationRecord::Ballast,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries, only: [:update], optional: true

      #delete
      depends_on_clusters ApplicationRecord::Collab, only: [:delete]

      #copy
      depends_on_clusters ApplicationRecord::Collab,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        ApplicationRecord::IssuesPullRequests, only: [:copy]
      depends_on_clusters ApplicationRecord::Iam,
        ApplicationRecord::Ballast,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries, only: [:copy], optional: true

      #search_repositories
      depends_on_clusters ApplicationRecord::Collab,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests, only: [:search_repositories]
      depends_on_clusters ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Spokes,
        ApplicationRecord::Notify, only: [:search_repositories], optional: true

      #search_issues_and_pulls
      depends_on_clusters ApplicationRecord::Collab,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests, only: [:search_issues_and_pulls]
      depends_on_clusters ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Spokes,
        ApplicationRecord::Ballast, only: [:search_issues_and_pulls], optional: true

      #count_issues_and_pulls
      depends_on_clusters ApplicationRecord::Collab,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests, only: [:count_issues_and_pulls]
      depends_on_clusters ApplicationRecord::Mysql2,
        ApplicationRecord::Ballast,
        ApplicationRecord::Spokes, only: [:count_issues_and_pulls], optional: true

      #suggested_repositories
      depends_on_clusters ApplicationRecord::Collab,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests, only: [:suggested_repositories]
      depends_on_clusters ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Configurations,
        ApplicationRecord::Ballast,
        ApplicationRecord::Spokes,
        ApplicationRecord::Notify, only: [:suggested_repositories], optional: true

      #filter_suggestions
      depends_on_clusters ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests, only: [:filter_suggestions]

      #stats
      depends_on_clusters ApplicationRecord::Collab,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests, only: [:stats]

      depends_on_clusters ApplicationRecord::Mysql1, only: [:memex_without_limits_beta_signup]

      preload_features [
        :active_job_skip_enqueue,
      ]

      preload_features MemexesHelper::MEMEX_CLIENT_FEATURE_FLAGS, only: [:show]
      preload_features MemexesHelper::MEMEX_PROJECT_ACTOR_FEATURE_FLAGS, only: [:show]
      preload_features MemexesHelper::MEMEX_BACKEND_FEATURE_FLAGS, only: [:show, :refresh]
      preload_features MemexesHelper::MEMEX_GROUP_TOGGLE_FEATURE_FLAGS.keys, only: [:show]

      before_action :parse_json_params
      before_action :require_title, only: [:create]
      before_action :require_this_memex, only: [:show, :refresh, :update, :stats, :delete, :copy, :memex_without_limits_beta_signup, :memex_without_limits_beta_optout, :dismiss_notice, :filter_suggestions]
      before_action :user_has_admin_access, only: [:memex_without_limits_beta_optout]
      before_action :user_is_admin_or_staff_with_write, only: [:memex_without_limits_beta_signup]
      before_action :require_pwl_enabled, only: [:filter_suggestions]
      before_action :require_user_visible_memex_project, only: [:show, :refresh]
      before_action :require_valid_suggestions_column, only: [:filter_suggestions]
      before_action :redirect_live_update_requests_to_refresh_endpoint, only: [:show]
      before_action :require_xhr_json_request, only: [:refresh]
      before_action :require_authorization_for_visibility_update, only: [:update]
      before_action :set_memex_nav_breadcrumb, only: [:show]
      before_action :user_has_read_access, only: [:copy]
      before_action :add_csp_exceptions, only: [:show]

      helper_method :orgs_for_conditional_access_component

    end

    CSP_EXCEPTIONS = {
      media_src: [GitHub.asset_host_url]
    }

    trace_method :memex_project_data
    trace_method :logged_in_user, span_annotator: ->(_klass, span, _context, result) do
      span.add_attributes({ "gh.memex.logged_in_user.logged_in" => result.present? })
    end
    trace_method :serialize_memex_items_with_options

    def refresh
      render(json: memex_project_data.transform_keys { |key| key.to_s.camelize(:lower) })
    end

    private def dark_ship_request?
      request&.xhr? && request&.params[:dark_ship] == "true" && GitHub.flipper[:memex_without_limits_dark_ship].enabled?(current_user)
    end

    def show
      return show_dark if dark_ship_request?

      begin
        if referring_params[:controller] == "repos/memexes" && referring_params[:action] == "index"
          instrument_memex_event("view_open", { repository: memex_owner&.repositories&.find_by(name: referring_params[:repository]) })
        end

        if request&.params[:statusUpdateId].present? && request&.params[:pane] == "info"
          source_controller = (request&.referrer.present? && referring_params) ? referring_params[:controller] : "unknown"
          instrument_memex_event("status_update_open", { context: source_controller })
        end

      rescue ActionController::RoutingError
        # as the project rendering is not dependent on a valid referrer, we can ignore this error
      end

      render("memexes/show", locals: {
        **memex_show_data,
        # these are specifically used by the header/layout, and not memex-specific data
        page_title: this_memex.display_title,
        page_breadcrumb_object: this_memex,
      })
    end

    def show_dark
      render_to_string("memexes/show", locals: {
        **memex_show_data,
        # these are specifically used by the header/layout, and not memex-specific data
        page_title: this_memex.display_title,
        page_breadcrumb_object: this_memex,
      })

      head :ok
    end

    def create
      owner = memex_owner
      return render status: 422, json: { errors: ["Project owner not found"] } unless owner

      is_template = create_memex_params[:is_template]&.to_s&.downcase == "true"

      if is_template && !owner.is_a?(Organization)
        error = "Project templates can only be created for organizations"
        if request&.xhr?
          return render(json: { errors: [error] }, status: :unprocessable_entity)
        else
          flash[:error] = error
          return redirect_to :back
        end
      end

      create_memex_params[:title].strip! unless create_memex_params[:title].nil?

      memex = if owner.organization? && create_memex_params[:template_id].present?
        memex_template = owner.memex_templates.find_by(id: create_memex_params[:template_id])
        unless memex_template&.memex_project&.viewer_can_read?(current_user)
          return render status: 422, json: { errors: ["Template not found"] }
        end
        memex_template = T.must(memex_template)
        template_project = T.must(memex_template.memex_project)
        max_draft_item_copy_error = MemexProject::Copier.get_max_draft_error(
          base_project: template_project,
          include_draft_issues: !!copy_memex_params[:include_draft_issues],
          is_template: true,
          actor: T.must(current_user),
        )
        if max_draft_item_copy_error
          GitHub.dogstats.increment("memex.memex_project_copier.max_copy_error")
          if request&.xhr?
            return render(json: { errors: [max_draft_item_copy_error] }, status: :unprocessable_entity)
          else
            flash[:error] = max_draft_item_copy_error
            return redirect_to :back
          end
        end

        memex = MemexProject.create_with_associations(
          owner: owner,
          creator: T.must(current_user),
          memex_template: memex_template,
          title: create_memex_params[:title],
          with_default_workflows: false,
          with_mwl_enabled: false,
        )
        copier = MemexProject::Copier.new(
          base_project: template_project,
          target_project: memex,
          include_draft_issues: !!copy_memex_params[:include_draft_issues],
          actor: current_user,
        )

        copier_result = copier.execute
        async_copy_message = copier_result.get_async_copying_message
        copier_result.target_project
      else
        MemexProject.create_with_associations(
          owner: owner,
          creator: T.must(current_user),
          title: create_memex_params[:title],
          with_mwl_enabled: true,
        )
      end

      @this_memex = memex

      if memex.valid? && memex.persisted?
        return unless grant_role_on_create(memex)

        if is_template
          memex.create_template!
          memex.apply_default_template(creator: current_user, template: MemexProject::DefaultTemplates::BlankTemplate)
          instrument_memex_event("make_template", { context: "create_project", ui: parse_template_ui(create_memex_params[:ui]) })
        end

        yield memex if block_given?

        if !request&.xhr?
          if async_copy_message
            flash[:notice] = async_copy_message
          end
          return redirect_to show_org_memex_path(this_memex.owner, this_memex.number), flash: { memex_templates: !is_template }  if this_memex.owner.is_a?(Organization)
          return redirect_to show_user_memex_path(this_memex.owner, this_memex.number), flash: { memex_templates: !is_template } if this_memex.owner.is_a?(User)
        end

        render(
          json: {
            **memex_project_api_metadata.transform_keys { |key| key.to_s.camelize(:lower) },
            **memex_project_data.transform_keys { |key| key.to_s.camelize(:lower) },
            memexProjectColumns: [],
          },
          status: :created,
        )
      else
        render(json: { errors: memex.errors.full_messages }, status: :unprocessable_entity)
      end
    rescue ActiveRecord::RecordInvalid => e
      render(json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity)
    end

    def copy
      return render_404 unless this_memex.viewer_can_read?(current_user)
      source_memex_project = this_memex

      target_memex_project_title = copy_memex_params[:title]
      target_memex_project_title.strip! unless target_memex_project_title.nil?
      target_memex_project_owner = User.find_by!(login: params[:owner])
      target_memex_project_is_template = copy_memex_params[:is_template]&.to_s&.downcase == "true"

      if target_memex_project_owner.organization?
        # Type must be casted here since Sorbet doesn't know that .organization? should only return true
        # if the object is an Organization
        target_memex_project_owner = T.cast(target_memex_project_owner, Organization)
        return head(:forbidden) unless target_memex_project_owner.organization_projects_enabled?
        return head(:forbidden) unless cap_filter.authorized_resources(target_memex_project_owner)
      end

      return head(:forbidden) unless target_memex_project_owner.projects_writable_by?(current_user)

      if target_memex_project_is_template
        return head(:forbidden) unless target_memex_project_owner.organization?
      end

      # Create a new target project with the default system fields
      new_project_params = {
        owner: target_memex_project_owner,
        creator: T.must(current_user),
        title: target_memex_project_title,
        with_default_workflows: false,
        with_mwl_enabled: false
      }

      template_id = copy_memex_params[:template_id]
      if template_id.present?
        memex_template = this_memex.owner.memex_templates.find_by(id: template_id)
        unless memex_template&.memex_project&.viewer_can_read?(current_user)
          return render status: 422, json: { errors: ["Template not found"] }
        end

        new_project_params[:memex_template] = T.must(memex_template)
      end

      max_draft_item_copy_error = MemexProject::Copier.get_max_draft_error(
        base_project: source_memex_project,
        include_draft_issues: !!copy_memex_params[:include_draft_issues],
        is_template: template_id.present?,
        actor: T.must(current_user),
      )
      if max_draft_item_copy_error
        GitHub.dogstats.increment("memex.memex_project_copier.max_copy_error")
        if request&.xhr?
          return render(json: { errors: [max_draft_item_copy_error] }, status: :unprocessable_entity)
        else
          flash[:error] = max_draft_item_copy_error
          return redirect_to :back
        end
      end

      new_project = MemexProject.create_with_associations(**new_project_params)

      raise ActiveRecord::RecordInvalid, new_project unless new_project.valid?

      copier = MemexProject::Copier.new(
        base_project: source_memex_project,
        target_project: new_project,
        include_draft_issues: !!copy_memex_params[:include_draft_issues],
        actor: T.must(current_user),
      )

      copier_result = copier.execute
      async_copy_message = copier_result.get_async_copying_message
      @this_memex = copier_result.target_project

      this_memex.create_template! if target_memex_project_is_template

      if !this_memex.persisted?
        error_sentence = this_memex.errors.full_messages.to_sentence
        flash[:error] = "There was a problem copying the project. #{error_sentence}"
        redirect_to :back
      else
        event_name = target_memex_project_is_template ? "copy_as_template" : "copy"
        instrument_memex_event(
          event_name,
          memex_project: source_memex_project,
          context: {
            target_project_id: this_memex.id,
            target_owner_id: target_memex_project_owner.id
          }.to_json
        )

        if request&.xhr?
          render(
            json: {
              **memex_project_api_metadata.transform_keys { |key| key.to_s.camelize(:lower) },
              **memex_project_data.transform_keys { |key| key.to_s.camelize(:lower) },
              memexProjectColumns: [],
            },
            status: :created,
          )
        else
          if async_copy_message
            flash[:notice] = async_copy_message
          end
          return redirect_to show_org_memex_path(this_memex.owner, this_memex.number), flash: { memex_templates: false }  if this_memex.owner.is_a?(Organization)
          redirect_to show_user_memex_path(this_memex.owner, this_memex.number), flash: { memex_templates: false } if this_memex.owner.is_a?(User)
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      error_sentence = e.record.errors.full_messages.to_sentence
      flash[:error] = "There was a problem copying the project. #{error_sentence}"
      redirect_to :back
    rescue ActiveRecord::RecordNotFound => e
      flash[:error] = "Could not find the specified project."
      redirect_to :back
    end

    def update
      final_update_params = update_memex_params.slice(:title, :description, :short_description)

      verb = "updated"
      event = "update"
      if !update_memex_params[:public].nil?
        verb = "visibility changed"
        event = "visibility_change"
      end

      closed = update_memex_params[:closed]&.to_s&.downcase
      if %w[1 true].include?(closed)
        final_update_params[:closed_at] = Time.zone.now
        verb = "closed"
        event = "close"
      elsif %w[0 false].include?(closed)
        final_update_params[:closed_at] = nil
        verb = "reopened"
        event = "reopen"
      end

      if !update_memex_params[:public].nil?
        final_update_params[:public] = update_memex_params[:public]
      end

      is_template = update_memex_params[:is_template]&.to_s&.downcase
      if is_template.present?
        return head(:forbidden) unless this_memex.owner.is_a?(Organization) && this_memex.viewer_is_admin?(current_user)
        if %w[1 true].include?(is_template)
          this_memex.create_template!
          instrument_memex_event("make_template", { context: "update_project" })
        elsif %w[0 false].include?(is_template)
          this_memex.remove_template!
          instrument_memex_event("remove_template")
        end
      end

      final_update_params[:title].strip! unless final_update_params[:title].nil?

      success = final_update_params.empty? || this_memex.update(final_update_params)

      if !this_memex.project_migration.nil?
        GitHub.dogstats.increment("memex_project_migration.update_migrated_project", tags: ["event:#{event}"])
      end

      if request&.xhr? && success
        render(json: { memexProject: this_memex.to_hash })
      elsif request&.xhr?
        render(json: { errors: this_memex.errors.full_messages }, status: :unprocessable_entity)
      elsif success
        instrument_memex_event(event, { ui: "index" })
        flash[:notice] = "Project #{verb}."
        redirect_to :back
      else
        flash[:error] = "You cannot perform that action at this time."
        redirect_to :back
      end
    end

    def delete
      has_read_access = this_memex.viewer_can_read?(current_user)
      has_admin_access = this_memex.viewer_is_admin?(current_user)

      unless has_read_access
        return render_404
      end

      unless has_admin_access
        return head(:forbidden)
      end

      this_memex.soft_delete!(current_user)
      instrument_memex_event("soft_delete")

      if !this_memex.project_migration.nil?
        this_memex.project_migration.destroy!
      end

      # Note that the client will perform the redirect, and flash will be shown on the subsequent page
      flash[:notice] = "Your project \"#{this_memex.name}\" was successfully deleted."
      render(json: { redirectUrl: projects_path(owner: memex_owner) })
    end

    def remove_visited # rubocop:todo GitHub/UseRestfulActions
      if this_memex.present? && memex_owner.present?
        T.must(memex_owner).remove_from_recently_visited_projects(viewer: current_user, memex_project: this_memex)
      end

      redirect_to :back
    end

    def suggested_repositories
      suggester = MemexRepositorySuggester.new(
        viewer: current_user,
        owner: memex_owner,
        memex_project: this_memex,
        milestone: underscored_params[:milestone],
        with_issue_types: ActiveRecord::Type::Boolean.new.deserialize(underscored_params[:with_issue_types]),
      )

      repo = this_repository

      repositories = if repo.present? && can_read_this_repository?
        suggester.repositories.push(repo.memex_suggestion_hash).uniq
      else
        suggester.repositories
      end

      render(json: { repositories: repositories })
    end

    def search_repositories
      stripped_query = params.fetch(:q, "").strip
      limit_to_repo_ids = nil
      with_issue_types = params.fetch(:with_issue_types, false)
      milestone = params.fetch(:milestone, nil)
      if milestone.present?
        limit_to_repo_ids = repo_ids_with_milestone(milestone)
      end

      query = stripped_query
      scope = search_repositories_scope

      # rescope the query if it is in name with owner format (e.g. owner/repo)
      split_query = stripped_query.split("/", 2)
      if split_query.length == 2
        query = split_query[1]
        owner = split_query[0] == "@me" ? current_user&.display_login : split_query[0]
        # owner is set to display_login already
        scope = "org:#{owner}" # rubocop:disable GitHub/DoNotAllowLogin
      end

      # execute the query
      search_query = ::Search::Queries::RepoQuery.new(
        current_user: current_user,
        user_session: user_session,
        remote_ip:    request&.remote_ip,
        phrase: "#{scope} in:name #{query}",
        per_page: SEARCH_RESULT_LIMIT,
        include_forks: true,
        limit_to_repo_ids: limit_to_repo_ids,
      )
      results = search_query.execute.results

      # if the query is a single word, and we didn't get enough results, try again using the query as the target owner
      if split_query.length == 1 && results.length < SEARCH_RESULT_LIMIT
        scope = "org:#{split_query[0]}"
        search_query = ::Search::Queries::RepoQuery.new(
          current_user: current_user,
          user_session: user_session,
          remote_ip: request&.remote_ip,
          phrase: "#{scope}",
          per_page: SEARCH_RESULT_LIMIT,
          include_forks: true,
          limit_to_repo_ids: limit_to_repo_ids,
        )
        results += search_query.execute.results
      end

      repos = results.map { |r| r["_model"] }.uniq.first(SEARCH_RESULT_LIMIT)

      render(json: { repositories: repos.map(&:memex_suggestion_hash) })
    end

    # this regex splits the phrase at only spaces outside of quotation marks to avoid splitting up multi-word phrases
    # e.g. `label:"tech debt" is:open` matches only the space between the closing quotation and the word "is"
    # e.g. `label:"tech debt"` does not have any matches
    PHRASE_PARTS_REGEX = /\s+(?=(?:[^"]*"[^"]*")*[^"]*$)/

    def search_issues_and_pulls
      # pre-escape and prepare user input
      prepared_phrase = prepare_search_phrase(params.fetch(:q, "").strip)

      limit = params.fetch(:limit, 0).to_i
      limit = limit.clamp(0, MAX_LIMIT_FOR_MEMEX_ITEMS)
      limit = SEARCH_RESULT_LIMIT unless limit > 0

      parameters = {
        current_user: current_user,
        remote_ip: request&.remote_ip,
        memex_project_id: this_memex&.id,
        phrase: prepared_phrase,
        source_fields: false,
        per_page: limit,
        force_issue_number_terms: true,
        escape_wildcards: prepared_phrase.empty?,
        sort: prepared_phrase.present? ? nil : %w[updated desc],
        normalizer: ->(results) { results.map { |r| Elastomer.get_index_name_from_result(r) == "issues" ? r["_model"] : r["_model"].pull_request }.compact },
        context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
      }

      repo = cap_filter.authorized_resources(this_repository)&.first
      if repo.present?
        parameters[:repo_id] = repo.id
      end

      query = ::Search::Queries::IssueQuery.new(parameters.compact)

      start_time = GitHub::Dogstats.monotonic_time
      results = query.execute.results

      result = results.map(&:memex_suggestion_hash)

      GitHub.dogstats.distribution(
        "memex_issue_search.duration",
        GitHub::Dogstats.duration(start_time),
        tags: ["wildcard_search:#{!prepared_phrase.empty?}"])

      render(json: { issuesAndPulls: result })
    end

    def count_issues_and_pulls
      prepared_phrase = prepare_search_phrase(params.fetch(:q, "").strip)

      parameters = {
        current_user: current_user,
        remote_ip: request&.remote_ip,
        # This excludes items that are already in the project
        memex_project_id: this_memex&.id,
        phrase: prepared_phrase,
        source_fields: false,
        escape_wildcards: prepared_phrase.empty?,
        context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
      }

      repo = this_repository
      if repo.present?
        parameters[:repo_id] = repo.id
      end

      query = ::Search::Queries::IssueQuery.new(parameters.compact)
      total_count = query.count
      render json: { count: total_count }
    end

    def stats
      context_value = stats_params[:context].present? ? stats_params[:context].to_s : nil

      stat_payload = {
        actor: current_user,
        memex_project: this_memex,
        memex_project_column: column_from_params,
        memex_project_item: item_from_params,
        name: haxor_filtered(stats_params[:name]),
        ui: haxor_filtered(stats_params[:ui]),
        context: context_value,
        memex_project_view: memex_project_view_from_params,
      }

      if stat_payload[:name] == "path_change" && logged_in?
        this_memex.update_last_visited_at_for_viewer(viewer: current_user)
      end

      # Note this is currently temporary, eventually the caller will pass along
      # the correct name for the event.
      if group_by_toggle_stat?
        stat_payload[:name] =
          boolean_stat(:group_by_enabled) ? "group_by.enabled" : "group_by.disabled"
      elsif group_by_collapse_toggle_stat?
        stat_payload[:name] = boolean_stat(:collapsed) ? "field_group_collapse" : "field_group_expand"
        stat_payload[:context] = "number_of_rows: #{stats_params[:number_of_rows].to_i},group_title: #{stats_params[:group_title]}"
      elsif !stats_params[:number_of_rows].nil?
        stat_payload[:context] = "number_of_rows: #{stats_params[:number_of_rows].to_i}"
      end

      GlobalInstrumenter.instrument("memex_event", stat_payload) if valid_stats_params?

      # whether the stats call succeeds or not, return :ok
      render(json: { success: true }, status: :ok)
    rescue ActionController::UnpermittedParameters
      render(json: { success: false }, status: :unprocessable_entity)
    end

    def memex_without_limits_beta_signup
      return render(json: { success: false }, status: :unprocessable_entity) unless
        show_memex_without_limits_waitlist_banner?(skip_eligibility_check: true) ||
        show_memex_without_limits_waitlist_staffship_banner?(skip_eligibility_check: true)

      return render(json: { success: false }, status: :not_found) unless add_to_mwl_waitlist?

      if this_memex.add_to_beta_waitlist(current_user)
        render(json: { success: true }, status: :created)
      else
        render(json: { success: false }, status: :unprocessable_entity)
      end
    end

    def memex_without_limits_beta_optout
      return render(json: { success: false }, status: :unprocessable_entity) unless GitHub.flipper[:mwl_beta_optout].enabled?(current_user)
      this_memex.remove_from_beta
      render(json: { success: true }, status: :ok)
    end

    def filter_suggestions

      response = Search::Queries::MemexProjectItemQuery.distinct_values_query(
        project: this_memex,
        viewer: current_user,
        cap_filter:,
        field_id: suggestions_column&.id,
        include_metadata: true,
      ).execute
      values = T.must(response.slices).filter_map { _1["slice_metadata"] unless _1["slice_value"] == MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY }
      render(json: { suggestions: values })
    end

    # only allow leading lowercase letters, dashes, spaces, and underscores,
    # filters out some pentesting-related junk data.
    private def haxor_filtered(str)
      return unless str.present?

      str.slice(/[a-z_ -]+/)
    end

    def memex_feature_flags
      return @memex_feature_flags if defined?(@memex_feature_flags)
      memex_feature_flags = MemexesHelper::MEMEX_CLIENT_FEATURE_FLAGS.filter do |flag|
        if flag == :issue_types
          memex_owner&.issue_types_enabled?
        elsif flag == :sub_issues
          SubIssuesFeature.enabled?(this_memex, actor: current_user)
        elsif flag == :memex_table_without_limits
          # While the client uses the presence of a singular `memex_table_without_limits` feature flag to determine if a MemexProject
          # is enrolled into the Increased Limits experience, we cannot determine enrollment to the Increased Limits experience on the
          # server in a single feature flag check as a project can be enrolled from any one of our multiple feature flags which are
          # checked in the `memex_table_without_limits_enabled?` helper method.
          memex_table_without_limits_enabled?
        else
          feature_enabled_globally_or_for_current_user_or_entity?(flag, memex_owner)
        end
      end

      memex_project_feature_flags = MemexesHelper::MEMEX_PROJECT_ACTOR_FEATURE_FLAGS.filter do |flag|
        this_memex.feature_enabled?(flag)
      end
      memex_feature_flags += memex_project_feature_flags

      # https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-preview/#working-with-flipper
      if logged_in?
        memex_feature_previews = MemexesHelper::MEMEX_FEATURE_PREVIEWS.filter do |flag|
          current_user&.feature_preview_enabled?(flag)
        end
        memex_feature_flags += memex_feature_previews
      end

      # Add feature gates, dependent upon the user/org's billing plan (see plans.yml) and project visibility.
      MemexesHelper::MEMEX_FEATURE_GATES.each do |feature_gate, memex_feature|
        memex_feature_flags.push((memex_feature.to_s + "_public").to_sym) if memex_owner&.plan_supports?(feature_gate, visibility: :public)
        memex_feature_flags.push((memex_feature.to_s + "_private").to_sym) if memex_owner&.plan_supports?(feature_gate, visibility: :private)
      end

      # Business configured features
      memex_feature_flags.push(:memex_automation_enabled) if this_memex.automation_enabled_for_user?(current_user)

      MemexesHelper::MEMEX_GROUP_TOGGLE_FEATURE_FLAGS.each do |parent_flag, child_flags|
        memex_feature_flags -= child_flags if GitHub.flipper[parent_flag].enabled?
      end

      # Tracks and Tracked By features are disabled if memex_table_without_limits is enabled.
      memex_feature_flags.delete(:tasklist_block) unless this_memex.tracks_and_tracked_by_enabled?

      # Features flags, previews, and gates *should* be mutually exclusive lists in MemexesHelper, but ensuring uniqueness
      # just in case
      @memex_feature_flags = memex_feature_flags.uniq
    end

    def memex_limits
      {
        projectItemLimit: this_memex.items_limit,
        projectItemArchiveLimit: this_memex.archived_items_limit,
        limitedChartsLimit: MemexProjectChart::LIMITED_CHARTS_LIMIT,
        singleSelectColumnOptionsLimit: MemexProjectColumn::Settings::Options::OPTION_LIMIT,
        singleSelectDescriptionMaxLength: MemexProjectColumn::Settings::OptionEntry::DESCRIPTION_CHAR_LIMIT,
        autoAddCreationLimit: this_memex.auto_add_creation_limit,
        viewsLimit: MemexProjectView::MAX_VIEW_COUNT,
      }
    end

    def memex_relay_ids
      {
        memexProject: this_memex.global_relay_id
      }
    end

    def emoji_skin_tone_preference
      return @emoji_skin_tone_preference if defined?(@emoji_skin_tone_preference)
      @emoji_skin_tone_preference = if logged_in?
        current_user&.profile_settings.preferred_emoji_skin_tone
      else
        nil
      end
    end

    def theme_preferences
      {
        mode: color_mode_with_override(current_user).to_s,
        light: color_mode_light_theme(current_user).to_s,
        dark: color_mode_dark_theme(current_user).to_s,
        markdown_fixed_width_font: current_user&.use_fixed_width_font? || false,
        preferred_emoji_skin_tone: emoji_skin_tone_preference,
      }
    end

    def media_urls
      {
        projectTemplateDialog:
        {
          boardLight: image_url("modules/memexes/memex-templates-board-light.png"),
          boardDark: image_url("modules/memexes/memex-templates-board-dark.png"),
          tableLight: image_url("modules/memexes/memex-templates-table-light.png"),
          tableDark: image_url("modules/memexes/memex-templates-table-dark.png"),
          roadmapLight: image_url("modules/memexes/memex-templates-roadmap-light.png"),
          roadmapDark: image_url("modules/memexes/memex-templates-roadmap-dark.png"),
          featureLight: image_url("modules/memexes/memex-templates-feature-light.png"),
          featureDark: image_url("modules/memexes/memex-templates-feature-dark.png"),
          backlogLight: image_url("modules/memexes/memex-templates-team-backlog-light.png"),
          backlogDark: image_url("modules/memexes/memex-templates-team-backlog-dark.png"),
        },
        insightsChartLimitDialog:
        {
          bannerLight: image_url("modules/memexes/insights-chart-limit-dialog-banner-light.png"),
          bannerDark: image_url("modules/memexes/insights-chart-limit-dialog-banner-dark.png"),
        },
        issueTypes:
        {
          popoverLight: image_url("modules/memexes/memex-issue-types-popover-light.png"),
          popoverDark: image_url("modules/memexes/memex-issue-types-popover-dark.png"),
          demoDark: image_url("modules/memexes/memex-issue-types-demo.mp4"),
          demoLight: image_url("modules/memexes/memex-issue-types-demo.mp4"),
          announcementDark: image_url("modules/memexes/memex-issue-types-announcement-dark.png"),
          announcementLight: image_url("modules/memexes/memex-issue-types-announcement-light.png"),
        },
      }
    end

    sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
    def memex_system_templates
      serialize_memex_system_templates(SYSTEM_TEMPLATES)
    end

    sig { params(templates: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    private def serialize_memex_system_templates(templates)
      templates.map do |template|
        {
          id: template[:id],
          title: template[:title],
          shortDescription: template[:short_description],
          imageUrl: {
            light: image_url(template[:image_url][:light]),
            dark: image_url(template[:image_url][:dark]),
          },
        }
      end
    end

    def memex_feedback_url
      return "https://github.com/github/memex/discussions/categories/staff-ship-feedback" if current_user&.employee?
      "https://github.com/github-community/community/discussions/categories/issues"
    end

    def issue_viewer_url
      return "https://github.com/github/issues/discussions/6502" if current_user&.employee?
      "https://github.com/orgs/community/discussions/62400"
    end

    def pwl_beta_url
      return "https://github.com/github/collaboration-workflows/discussions/177" if current_user&.employee?
      "https://github.com/orgs/community/discussions/139936"
    end

    def archive_alpha_feedback_url
      return nil unless memex_paginated_archive_enabled?
      return "https://github.com/github/engineering/discussions/3051" if current_user&.employee?
      "https://github.com/orgs/community/discussions/52805"
    end

    def csrf_data(path, method: :post)
      {
        url: path,
        token: authenticity_token_for(path, method: method),
      }
    end

    def create_memex_params
      underscored_params
        .require(:memex_project)
        .permit(
          :title,
          :template_id,
          # Creates a corresponding MemexTemplate if true
          :is_template,

          # Optional param to indicate originating UI context
          :ui,

          memex_project_items: [:content_type, content: [:title, :id, :repository_id]],
          memex_project_columns: [
            :data_type,
            :name,
            :position,
            :visible,
            settings: [
              options: [
                :name,
                :color
              ],
              configuration: [
                :start_day,
                :duration,
                iterations: [
                  :title,
                  :start_date,
                  :duration
                ],
                completed_iterations: [
                  :title,
                  :start_date,
                  :duration
                ]
              ]
            ]
          ]
        )
    end

    def copy_memex_params
      underscored_params.require(:memex_project_copy).permit(
        :owner,
        :title,
        :include_draft_issues,
        :template_id,
        :is_template
      )
    end

    def update_memex_params
      underscored_params.permit(
        # These are params from routing.
        :org,
        :memex_number,
        :user_id,

        # These are additional params that Rails includes with an HTML update.
        :_method,
        :authenticity_token,
        :client_uid,

        # These are the params that are actually used for mass assignment.
        :title,
        :description,
        :short_description,
        :closed,
        :public,

        # These are params to update MemexTemplate table.
        :is_template
      )
    end

    def this_memex_items
      return @this_memex_items if defined?(@this_memex_items)

      @this_memex_items = if memex_table_without_limits_enabled?
        this_paginated_memex_items_response.models.to_a
      else
        this_memex
          .prioritized_scope(:memex_project_items)
          .limit(MemexProjectItem::PER_PAGE_LIMIT)
          .to_a
      end
    end

    def this_paginated_memex_items_response
      return @this_paginated_memex_items_response if defined?(@this_paginated_memex_items_response)

      grouping_options = paginated_items_grouping_options

      # A nil slice_by param indicates it wasn't passed, so fallback to the view configuration.
      # An empty "" slice_by param overrides for no slicing.
      slice_by = memex_slice_params.first.nil? ? this_memex_view&.slice_by&.dig("field") : memex_slice_params.first.presence
      slice_value = slice_by.nil? ? nil : memex_slice_params.second

      @this_paginated_memex_items_response = if this_memex_view
        query = Search::Queries::MemexProjectItemQuery.new(
          project: this_memex,
          viewer: current_user,
          cap_filter: cap_filter,
          include_project_item_owner_ids: true,
          query: underscored_params[:filter_query] || this_memex_view.filter || "",
          first: Search::Queries::MemexProjectItemQuery::MAX_PAGE_SIZE,
          grouping_options:,
          sort: (memex_sort_params.any? ? memex_sort_params : this_memex_view.sort_params).map { |s| s.to_sort_fragment(this_memex) }.compact,
          sort_params: memex_sort_params.any? ? memex_sort_params : this_memex_view.sort_params,
          slice_by: slice_by,
          slice_value: slice_value,
          include_empty_slices: true,
          include_slice_metadata: true,
        )
        query.execute
      else
        # current_view being nil here means that we had a view_number
        # in the URL, but failed to find a view with that number.
        # Instead of falling back on the default view, we just return
        # no item data to the client and let it handle the UX for the view
        # not existing.
        Search::Responses::MemexProjectItemResponse.new({})
      end
    end

    sig { returns(T.nilable(MemexProjectColumn::Interface::Groupable::Options)) }
    private def paginated_items_grouping_options
      # When we support swimlanes, this won't be a binary choice, but instead board view will read the horizontal
      # grouping as well
      is_board_view = this_memex_view_current_layout == "board"
      group_by_params, configured_view_grouping, missing_value_group_order = if is_board_view
        [
          memex_group_params[:vertical],
          # fall back to status_column if there is no configured vertical grouping column
          this_memex_view&.vertical_group_by&.first || this_memex.status_column.id,
          MemexProjectColumn::Interface::Groupable::MissingValueGroupOrder::First
        ]
      else
        [
          memex_group_params[:horizontal],
          this_memex_view&.group_by&.first,
          MemexProjectColumn::Interface::Groupable::MissingValueGroupOrder::Last
        ]
      end

      # group by params if they are passed, otherwise fall back to the appropriate column for the current view
      field_id = group_by_params.first.nil? ? configured_view_grouping : group_by_params.first
      return unless field_id.present?

      # If memex_mwl_swimlanes is enabled and this is a board view, add optional secondary swimlanes grouping
      if current_user&.feature_enabled?(:memex_mwl_swimlanes) && this_memex_view_current_layout == "board"
        secondary_group_by_params, secondary_configured_view_grouping, secondary_missing_value_group_order =
          [
            memex_group_params[:horizontal],
            this_memex_view&.group_by&.first,
            MemexProjectColumn::Interface::Groupable::MissingValueGroupOrder::Last
          ]
        # group by params if they are passed, otherwise fall back to the appropriate column for the current view
        secondary_field_id = secondary_group_by_params.first.nil? ? secondary_configured_view_grouping : secondary_group_by_params.first

        if secondary_field_id.present?
          secondary_grouping_options = MemexProjectColumn::Interface::Groupable::Options.new(
            field_object_or_id: secondary_field_id.to_i,
            missing_value_group_order: secondary_missing_value_group_order,
            include_empty_groups: false,
            ignore_group_sort: is_board_view,
            include_group_metadata: true,
          )
        end
      end

      MemexProjectColumn::Interface::Groupable::Options.new(
        field_object_or_id: field_id.to_i,
        missing_value_group_order:,
        include_empty_groups: is_board_view,
        ignore_group_sort: is_board_view,
        include_group_metadata: true,
        secondary_grouping_options:,
      )
    end

    def project_views(memex: this_memex)
      memex.prioritized_memex_project_views.reverse
    end

    def require_pwl_enabled
      render_404 unless memex_table_without_limits_enabled?
    end

    def require_user_visible_memex_project
      render_404 if this_memex.hide_from_user?(current_user)
    end

    def require_valid_suggestions_column
      return render status: 422, json: { errors: ["Field is invalid"] } unless suggestions_column
      render status: 422, json: { errors: ["Suggestions not available for field type"] } unless suggestions_column&.to_field&.slice_by_metadata_id_path
    end

    def require_title
      if !create_memex_params[:title]
        render_json_error(
          error: "You must provide a title",
          status: :unprocessable_entity,
        )
      end
    end

    private def require_authorization_for_visibility_update
      return if update_memex_params[:public].nil?
      head(:forbidden) unless this_memex.viewer_can_change_visibility?(current_user)
    end

    def serialized_memex_items_with_prefilled_associations
      return @serialized_memex_items_with_prefilled_associations if defined?(@serialized_memex_items_with_prefilled_associations)
      @serialized_memex_items_with_prefilled_associations = serialize_memex_items_with_options
    end

    def serialize_memex_items_with_options
      prefilled_associations = if this_memex && this_memex_items.present?
        prefill_associations(this_memex_items, required_columns_for_initial_load)
      end

      items = T.let([], T::Array[MemexProjectItem])
      instrument_cap_filtering("memexes_controller.serialize_memex_items_with_options") do
        items = MemexProjectItemSerializer
          .new(
            viewer: current_user,
            memex: this_memex,
            items: this_memex_items,
            columns: required_columns_for_initial_load,
            prefilled_associations: prefilled_associations,
            cap_filter: cap_filter
          )
          .result
          .items
        items
      end

      [items, prefilled_associations]
    end

    # TODO: add a real allowlist of stats?
    def stats_params
      return @stats_params if defined?(@stats_params)
      @stats_params = underscored_params.require(:payload).permit(
        :org,
        :memex_number,
        :key,
        :memex_project_column_id,
        :memex_project_item_id,
        :group_by_enabled,
        :group_title,
        :collapsed,
        :name,
        :ui,
        :context,
        :number_of_rows,
        :memex_project_view_number,
        :mode
      )
    end

    def valid_stats_params?
      group_by_toggle_stat? ||
        group_by_collapse_toggle_stat? ||
        stats_params[:name].present?
    end

    def boolean_stat(key)
      stats_params[key] == "true" || stats_params[key] == true
    end

    def group_by_toggle_stat?
      stats_params[:key] == "memex_project_field_group_by" &&
        !stats_params[:group_by_enabled].nil? &&
        column_from_params.present?
    end

    def group_by_collapse_toggle_stat?
      stats_params[:key] == "memex_project_field_group_by_collapse_toggle" &&
        %i( group_title collapsed number_of_rows ).all? { |param| !stats_params[param].nil? } &&
        column_from_params.present?
    end

    def column_from_params
      return @column_from_params if defined?(@column_from_params)
      return @column_from_params = nil unless stats_params[:memex_project_column_id]

      @column_from_params = ActiveRecord::Base.connected_to(role: :reading) do
        this_memex
          .find_column_by_name_or_id(stats_params[:memex_project_column_id])
      end
    end

    def item_from_params
      return @item_from_params if defined?(@item_from_params)
      return @item_from_params = nil unless stats_params[:memex_project_item_id]

      @item_from_params = ActiveRecord::Base.connected_to(role: :reading) do
        this_memex
          .memex_project_items
          .find_by(id: stats_params[:memex_project_item_id])
      end
    end

    def memex_project_view_from_params
      return @memex_project_view_from_params if defined?(@memex_project_view_from_params)
      return @memex_project_view_from_params = nil unless stats_params[:memex_project_view_number]

      @memex_project_view_from_params = ActiveRecord::Base.connected_to(role: :reading) do
        this_memex.memex_project_views.find_by(number: stats_params[:memex_project_view_number])
      end
    end

    def suggestions_column
      return @suggestions_column if defined?(@suggestions_column)

      field_id = underscored_params.require(:field_id)
      @suggestions_column = this_memex.find_column_by_name_or_id(field_id)
    end

    def search_repositories_scope
      raise NotImplementedError
    end

    def repo_ids_with_milestone(milestone)
      raise NotImplementedError
    end

    def logged_in_user
      if logged_in?
        {
          id: current_user&.id,
          global_relay_id: current_user&.global_relay_id,
          login: current_user&.display_login,
          name: current_user&.name,
          avatarUrl: current_user&.primary_avatar_url(40),
          paste_url_link_as_plain_text: current_user&.paste_url_link_as_plain_text?,
          use_single_key_shortcut: current_user&.settings&.get(:keyboard_shortcuts_preference) == "all",
          isSpammy: current_user&.spammy,
        }
      end
    end

    def memex_project_data
      return @memex_project_data if defined?(@memex_project_data)

      columns_without_excluded = remove_excluded_columns(this_memex.columns)
      serialized_memex_items, prefilled_associations = if memex_table_without_limits_enabled? || dark_ship_request?
        [nil, nil]
      else
        serialized_memex_items_with_prefilled_associations
      end

      # Skip fetching paginated items for refresh requests
      refreshing = action_name.to_sym == :refresh
      serialized_paginated_memex_items = if !refreshing && (memex_table_without_limits_enabled? || dark_ship_request?)
        Search::Responses::MemexItemsApiResponse.build_from_response(
          response: this_paginated_memex_items_response,
          serializer: ->(response) do
            items = response.models
            redactor_results = response.redactor_results
            result = serialize_items(items, required_columns_for_initial_load, cap_filter, from_paginated_context: true, redactor_results:)
            prefilled_associations = result[:prefilled_associations]
            result[:serialized_items]
          end
        ).to_hash
      else
        nil
      end

      @memex_project_data = {
        github_runtime: GitHub.runtime.current,
        github_version_number: GitHub.major_minor_version_number,
        github_billing_enabled: GitHub.billing_enabled?,
        feedback: {
          url: memex_feedback_url,
          issue_viewer_url: issue_viewer_url,
          pwl_beta_url: pwl_beta_url
        },
        archive_alpha_feedback: { url: archive_alpha_feedback_url },
        logged_in_user:,
        memex_project: this_memex.to_hash,
        memex_project_items: serialized_memex_items,
        memex_project_items_paginated: serialized_paginated_memex_items,
        memex_project_all_columns: columns_without_excluded.map do |e|
          e.to_hash(prefilled_associations: prefilled_associations)
        end,
        memex_workflow_configurations: this_memex.workflow_configurations(current_user).map(&:to_hash),
        memex_workflows: this_memex.workflows.map(&:to_hash),
        memex_views: project_views(memex: this_memex).map(&:to_hash),
        memex_charts: this_memex.supported_charts.map(&:to_hash),
        created_with_template_memex: created_with_template_memex,
        latest_memex_project_status: get_latest_memex_project_status,
        memex_user_notices: get_user_notices(columns_without_excluded),
        memex_service: { betaSignupBanner: get_pwl_beta_banner_state, killSwitchEnabled: get_killswitch_state },
        memex_consistency_metrics: this_memex.consistency_metrics(viewer: current_user),
      }
    end

    def dismiss_notice
      notice = params[:notice]
      # Dismiss notices on a per-project basis if the notice is a project notice. Otherwise dismiss the notice per user.
      if User::NoticesDependency::PROJECT_NOTICES.include?(notice)
        current_user&.dismiss_project_notice(params[:notice], project_id: this_memex.id) if logged_in?
      else
        current_user&.dismiss_notice(params[:notice], kv_store: Memex::KV.store) if logged_in?
      end
      render(json: { success: true }, status: :ok)
    end

    #
    # Returns the necessary API Metadata for a given memex project
    # This object should camelized in the json response from create,
    # but contains metadata that should be exposed _as is_ in the show view
    #
    def memex_project_api_metadata
      # This method MUST have the required methods defined in order to be called. This
      # cannot be declared statically, since not all controllers will call this.
      T.bind(self, T.all(SharedMemexesControllerActions, Memexes::ClientPathsDependency))
      return @memex_project_api_metadata if defined?(@memex_project_api_metadata)

      @memex_project_api_metadata = {
        search_repositories_endpoint_data: { url: client_search_repositories_path },
        search_issues_and_pulls_endpoint_data: { url: client_search_issues_and_pulls_path },
        count_issues_and_pulls_endpoint_data: { url: client_count_issues_and_pulls_path },
        suggested_repositories_endpoint_data: { url: client_suggested_repositories_path },
        memex_refresh_api_data: client_paths.fetch(:refresh_memex),
        memex_update_api_data: client_paths.fetch(:update_memex),
        memex_delete_api_data: client_paths.fetch(:delete_memex),

        memex_suggested_collaborators_api_data: client_paths.fetch(:suggest_memex_collaborators),
        memex_collaborators_api_data: client_paths.fetch(:get_memex_collaborators),
        memex_add_collaborators_api_data: client_paths.fetch(:add_memex_collaborators),
        memex_remove_collaborators_api_data: client_paths.fetch(:remove_memex_collaborators),

        memex_item_create_api_data: client_paths.fetch(:create_memex_item),
        memex_item_create_bulk_api_data: client_paths.fetch(:create_memex_items_bulk),
        memex_item_get_api_data: client_paths.fetch(:get_memex_item),
        memex_item_update_api_data: client_paths.fetch(:update_memex_item),
        memex_item_update_bulk_api_data: client_paths.fetch(:update_memex_items_bulk),
        memex_item_delete_api_data: client_paths.fetch(:delete_memex_item),
        memex_item_archive_api_data: client_paths.fetch(:archive_memex_item),
        memex_item_unarchive_api_data: client_paths.fetch(:unarchive_memex_item),
        memex_archived_items_get_api_data: client_paths.fetch(:get_memex_archived_items),
        memex_paginated_items_get_api_data: client_paths.fetch(:get_memex_paginated_items),
        memex_get_archive_status_api_data: client_paths.fetch(:get_memex_archive_status),
        memex_item_convert_issue_api_data: client_paths.fetch(:convert_memex_item_to_issue),

        memex_item_suggested_assignees_api_data: client_paths.fetch(:suggest_memex_item_assignees),
        memex_item_suggested_labels_api_data: client_paths.fetch(:suggest_memex_item_labels),
        memex_item_suggested_milestones_api_data: client_paths.fetch(:suggest_memex_item_milestones),
        memex_item_suggested_issue_types_api_data: client_paths.fetch(:suggest_memex_item_issue_types),

        memex_preview_markdown_api_data: client_paths.fetch(:preview_markdown),

        memex_get_sidepanel_item_api_data: client_paths.fetch(:memex_get_sidepanel_item),
        memex_comment_on_sidepanel_item_api_data: client_paths.fetch(:memex_comment_on_sidepanel_item),
        memex_update_sidepanel_item_state_api_data: client_paths.fetch(:memex_update_sidepanel_item_state),
        memex_update_sidepanel_item_api_data: client_paths.fetch(:memex_update_sidepanel_item),
        memex_edit_sidepanel_comment_api_data: client_paths.fetch(:memex_edit_sidepanel_comment),
        memex_update_sidepanel_item_reaction_api_data: client_paths.fetch(:memex_update_sidepanel_item_reaction),
        memex_sidepanel_item_suggestions_api_data: client_paths.fetch(:memex_sidepanel_item_suggestions),

        memex_columns_get_api_data: client_paths.fetch(:get_memex_columns),
        memex_column_create_api_data: client_paths.fetch(:create_memex_column),
        memex_column_update_api_data: client_paths.fetch(:update_memex_column),
        memex_column_delete_api_data: client_paths.fetch(:delete_memex_column),
        memex_column_option_create_api_data: client_paths.fetch(:create_memex_column_option),
        memex_column_option_update_api_data: client_paths.fetch(:update_memex_column_option),
        memex_column_option_delete_api_data: client_paths.fetch(:delete_memex_column_option),

        memex_workflow_create_api_data: client_paths.fetch(:create_memex_workflow),
        memex_workflow_update_api_data: client_paths.fetch(:update_memex_workflow),

        stats_post_endpoint_csrf_data: client_paths.fetch(:post_memex_stats),

        memex_view_create_api_data: client_paths.fetch(:create_memex_view),
        memex_view_update_api_data: client_paths.fetch(:update_memex_view),
        memex_view_delete_api_data: client_paths.fetch(:delete_memex_view),

        memex_update_organization_access_api_data: client_paths.fetch(:update_memex_organization_access),
        memex_get_organization_access_api_data: client_paths.fetch(:get_memex_organization_access),

        memex_chart_create_api_data: client_paths.fetch(:create_memex_chart),
        memex_chart_update_api_data: client_paths.fetch(:update_memex_chart),
        memex_chart_delete_api_data: client_paths.fetch(:delete_memex_chart),

        memex_migration_get_api_data: client_paths.fetch(:memex_migration),
        memex_migration_retry_api_data: client_paths.fetch(:memex_retry_migration),
        memex_migration_cancel_api_data: client_paths.fetch(:memex_cancel_migration),
        memex_migration_acknowledge_completion_api_data: client_paths.fetch(:memex_acknowledge_completion_migration),

        memex_template_api_data: client_paths.fetch(:create_memex_template),

        memex_custom_templates_api_data: client_paths.fetch(:memex_custom_templates),

        memex_tracked_by_api_data: client_paths.fetch(:memex_items_tracked_by_parent),
        memex_reindex_items_api_data: client_paths.fetch(:memex_reindex_items),
        copy_memex_project_partial_data: client_paths.fetch(:copy_memex_project_partial),

        memex_statuses_api_data: client_paths.fetch(:memex_statuses),
        memex_status_create_api_data: client_paths.fetch(:create_memex_status),
        memex_status_destroy_api_data: client_paths.fetch(:destroy_memex_status),
        memex_status_update_api_data: client_paths.fetch(:update_memex_status),

        memex_notification_subscription_create_api_data: client_paths.fetch(:create_notification_subscription),
        memex_notification_subscription_destroy_api_data: client_paths.fetch(:destroy_notification_subscription),
        memex_viewer_subscribed: memex_status_updates_notifications_enabled? && notifyd_subscription&.viewer_is_subscribed?,
        memex_without_limits_beta_signup_api_data: client_paths.fetch(:memex_without_limits_beta_signup),
        memex_without_limits_beta_optout_api_data: client_paths.fetch(:memex_without_limits_beta_optout),
        memex_filter_suggestions_api_data: client_paths.fetch(:memex_filter_suggestions),

        memex_dismiss_notice_api_data: client_paths.fetch(:memex_dismiss_notice),

        memex_alive: {
          presenceChannel: this_memex.presence_channel,
          messageChannel: this_memex.live_updates_channel,
        },

        memex_refresh_events:,
      }
    end

    # This {policy}_enforceable method allows us to opt out of the emu_ownership CAP policy when copying public projects
    # See: https://thehub.github.com/epd/engineering/products-and-services/dotcom/cap/cookbook/#how-to-opt-out-of-enforcement
    def emu_ownership_enforceable
      action_name == "copy" && this_memex&.public? ? :no : :yes
    end

    private def memex_refresh_events
      events = [
        "github.memex.v1.MemexProjectColumnCreate",
        "github.memex.v1.MemexProjectColumnUpdate",
        "github.memex.v1.MemexProjectColumnDestroy",
        "github.memex.v0.MemexProjectEvent",
        "github.memex.v0.MemexProjectViewCreate",
        "github.memex.v0.MemexProjectViewUpdate",
        "github.memex.v0.MemexProjectViewDestroy",
      ]
      unless memex_table_without_limits_enabled?
        # `memex_item_denormalized_to_elasticsearch` covers these events
        # when memex_table_without_limits is enabled
        events.concat([
          "github.memex.v0.MemexProjectColumnValueCreate",
          "github.memex.v0.MemexProjectColumnValueDestroy",
          "github.memex.v0.MemexProjectColumnValueUpdate",
          "github.memex.v0.MemexProjectItemMove",
          "github.memex.v0.ProjectItemCreate",
          "github.memex.v0.ProjectItemUpdate",
          "github.memex.v0.ProjectItemDestroy",
          "github.v1.IssueUpdateAssignee",
          "github.v1.IssueUpdateIssueType",
          "github.v1.IssueUpdateLabel",
          "github.v1.LabelUpdate",
        ])
      end
      events
    end

    private def memex_show_data
      memex_creator = if this_memex.creator
        {
          id: this_memex.creator.id,
          login: this_memex.creator.display_login,
          name: this_memex.creator.name,
          avatarUrl: this_memex.creator.primary_avatar_url(40)
        }
      end

      memex_templates = flash[:memex_templates]

      # Asserting that memex_owner exists here since this method should only ever get called
      # after checking that memex_owner is not nil.
      # need to fix the underlying type of memex_owner to be Organization | User
      owner = T.cast(T.must(memex_owner), T.any(Organization, User))

      reserved_columns = MemexProjectColumn.reserved_column_names(actor: current_user, owner: owner)

      {
        **memex_project_api_metadata,
        **memex_project_data,
        viewer_privileges: memex_viewer_privileges,
        enabled_features: memex_feature_flags,
        reserved_column_names: reserved_columns,
        theme_preferences: theme_preferences,
        media_urls: media_urls,
        memex_creator: memex_creator,
        memex_templates: memex_templates,
        memex_system_templates: memex_system_templates,
        created_with_template_memex: created_with_template_memex,
        memex_owner: {
          id: owner.id,
          login: owner.display_login,
          name: owner.name,
          avatarUrl: owner.primary_avatar_url(40),
          type: owner.is_a?(Organization) ? "organization" : "user",
          isEnterpriseManaged: this_memex.owner_is_enterprise_managed?,
          planName: owner.plan.name
        },
        memex_limits: memex_limits,
        memex_relay_ids: memex_relay_ids,
        memex_project_migration: this_memex.viewer_can_write?(current_user) &&
          this_memex.project_migration.as_json(root: false, methods: :is_automated, only: ProjectMigration::PROJECT_MIGRATION_FIELDS)
      }
    end

    # This method returns all the referenced orgs in the memex items that the current user has access to
    def orgs_for_conditional_access_component
      return [] unless logged_in?
      return [] unless this_memex.present?

      return @orgs_for_conditional_access_component if defined?(@orgs_for_conditional_access_component)

      instrument_cap_filtering("memexes_controller.orgs_for_conditional_access_component") do
        @orgs_for_conditional_access_component = if memex_table_without_limits_enabled?
          owner_ids = this_paginated_memex_items_response.project_item_owner_ids
          owner_ids.present? ? User.where(id: owner_ids).to_a : []
        else
          MemexProjectItem.multiple_target_for_conditional_access(this_memex_items).values
        end
      end
    end

    def instrument_memex_event(name, overrides = {})
      GlobalInstrumenter.instrument("memex_event",
        {
          actor: current_user,
          memex_project: this_memex,
          name: name,
          memex_project_column: nil,
          memex_project_item: nil,
          ui: nil,
          context: "",
          memex_project_view: nil,
        }.merge(overrides)
      )
    end

    def instrument_cap_filtering(metric_name)
      timer = Timer.start
      result = yield
      timer.stop

      # round length of this_memex_items to nearest power of 2 for tags (1,2,4,8,16...)
      approx_items_count = this_memex_items.empty? ? 0 : 2**(Math.log2(this_memex_items.length).round)

      GitHub.dogstats.distribution(metric_name, timer.elapsed_ms, tags: [
        "approx_number_of_memex_items:#{approx_items_count}"
      ])
      result
    end

    private def redirect_live_update_requests_to_refresh_endpoint
      # This method MUST have the required methods defined in order to be called. This
      # cannot be declared statically, since not all controllers will call this.
      T.bind(self, T.all(SharedMemexesControllerActions, Memexes::ClientPathsDependency))

      return unless xhr_json_request?
      GitHub.dogstats.increment("memex.client.requested_legacy_live_updates_endpoint")
      redirect_to(client_paths.fetch(:refresh_memex)[:url])
    end

    private def require_xhr_json_request
      render_404 unless xhr_json_request?
    end

    private def xhr_json_request?
      request&.xhr? && request&.format&.json?
    end

    private def memex_viewer_privileges(role: nil)
      role = if role.present? && [:admin, :write, :read].include?(role)
        role
      elsif role.blank? || Rails.env.production?
        this_memex.viewer_most_capable_permission(current_user)
      else
        raise ArgumentError.new("Invalid role: '#{role}'. Must be one of :admin, :read or :write")
      end

      {
        role: role,
        canChangeProjectVisibility: this_memex&.viewer_can_change_visibility?(current_user) || false,
        canCopyAsTemplate: memex_can_copy_as_template?,
      }
    end

    private def readable_created_with_template_memex(viewer)
      template_memex = this_memex.created_with_memex_template&.memex_project
      return unless template_memex
      return if template_memex.deleted?
      return unless template_memex.viewer_can_read?(viewer)

      template_memex
    end

    private def created_with_template_memex
      template_project = readable_created_with_template_memex(current_user)
      return unless template_project

      template_project_url = if template_project.owner.is_a?(Organization)
        show_org_memex_path(template_project.owner.display_login, template_project.number)
      else
        show_user_memex_path(template_project.owner.display_login, template_project.number)
      end

      {
        titleHtml: template_project.title_html,
        url: template_project_url,
        id: template_project.id,
      }
    end

    # only organizations can make templates.
    #
    # A user may copy the project as a template if they are a member or billing manager of any organization
    private def memex_can_copy_as_template?
      return false unless this_memex.owner.is_a?(Organization) && current_user.present?

      current_user&.member_or_billing_manager_for_any_organization?
    end

    private def set_memex_nav_breadcrumb
      return unless header_redesign_enabled? && this_memex

      set_nav_breadcrumb(ContextRegion::Factory.build(this_memex))
    end

    private def prepare_search_phrase(user_specified_phrase)
      # This function is used to prepare the search phrase for bulk-add and auto-add items
      phrase_parts = user_specified_phrase.split(PHRASE_PARTS_REGEX)
      modifiers, plain_text = phrase_parts.partition { |p| p.include?(":") }
      modifier_string = modifiers.join(" ")
      plain_text_string = plain_text
        .map { |p| Search.escape_characters(p) + "*" }
        .join(" ")
      prepared_phrase = modifier_string.present? ? modifier_string : ""
      prepared_phrase = [prepared_phrase, "in:title #{plain_text_string}"].join(" ").strip if plain_text_string.present?

      prepared_phrase
    end

    # Accepts a user-controlled UI input and checks if it matches one of the recognized UI strings,
    # and returns `nil` otherwise.
    sig { params(ui: T.untyped).returns(T.nilable(String)) }
    private def parse_template_ui(ui)
      ui if MemexStats::UIValues.has_serialized?(ui)
    end

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    private def get_latest_memex_project_status
      latest_memex_project_status = this_memex.memex_project_statuses.last
      latest_memex_project_status&.to_hash(current_user, cap_filter)&.deep_transform_keys { |k| k.to_s.camelize(:lower) }
    end

    sig { returns(T.nilable(MemexProject::NotifydSubscriptions)) }
    private def notifyd_subscription
      return unless (user = current_user)
      @notifyd_subscription ||= MemexProject::NotifydSubscriptions.new(user, this_memex)
    end

    sig { returns(String) }
    private def get_pwl_beta_banner_state
      return "staffship" if show_memex_without_limits_waitlist_staffship_banner?
      return "visible" if show_memex_without_limits_waitlist_banner?
      "hidden"
    end

    sig { returns(T::Boolean) }
    private def get_killswitch_state
      # If the kill switch is enabled, then we'll return `false` for the MWL FF to the client
      # However, we only want to show an indicator that the kill switch is enabled to projects
      # that otherwise _would have_ had the MWL FF enabled.
      # So we always return false for the kill switch state if the MWL FF is disabled
      return false unless this_memex.feature_enabled?(:memex_table_without_limits)
      this_memex.feature_enabled?(:memex_without_limits_kill_switch)
    end

    sig { params(skip_eligibility_check: T::Boolean).returns(T::Boolean) }
    private def show_memex_without_limits_waitlist_banner?(skip_eligibility_check: false)
      return false unless current_user && this_memex.viewer_is_admin?(current_user)
      return false unless project_is_bannerable?

      # Optionally skip `#eligible_for_memex_without_limits_waitlist?`. The idea
      # here is that sometimes we do not need to know if the project is
      # eligible, we just need to check that all other conditions met.
      #
      # This helps us for example return the correct status based on whether the
      # users is allowed to join the waitlist versus if the project is eligible
      # which we want to check separately.
      return true if skip_eligibility_check

      this_memex.eligible_for_memex_without_limits_waitlist?
    end

    sig { params(skip_eligibility_check: T::Boolean).returns(T::Boolean) }
    private def show_memex_without_limits_waitlist_staffship_banner?(skip_eligibility_check: false)
      return false unless current_user&.employee? && this_memex.viewer_can_write?(current_user)
      return false unless project_is_bannerable?

      # Optionally skip `#eligible_for_staffship_memex_without_limits_waitlist?`. The idea
      # here is that sometimes we do not need to know if the project is
      # eligible, we just need to check that all other conditions met.
      #
      # This helps us for example return the correct status based on whether the
      # users is allowed to join the waitlist versus if the project is eligible
      # which we want to check separately.
      return true if skip_eligibility_check

      this_memex.eligible_for_staffship_memex_without_limits_waitlist?
    end

    private def project_is_bannerable?
      return false unless GitHub.dotcom_request?
      return false if GitHub.flipper[:memex_table_without_limits].enabled?(this_memex)
      return false if EarlyAccessMembership.exists?(member: this_memex, feature_slug: "memex_table_without_limits")
      return false if T.must(current_user).dismissed_project_notice?("memex_without_limits_beta", project_id: this_memex.id)
      true
    end

    private def get_user_notices(columns)
      return [] unless (user = current_user)
      return [] unless memex_owner&.issue_types_enabled?

      notices = []

      if this_memex.viewer_is_admin?(user)
        has_user_defined_type_column = columns.any? { |c| c.name.casecmp?(MemexProjectColumn::TYPE_COLUMN_NAME) && c.user_defined? }

        if has_user_defined_type_column
          dismissed_rename_prompt = user.dismissed_project_notice?("memex_issue_types_rename_prompt", project_id: this_memex.id)

          unless dismissed_rename_prompt
            notices << "memex_issue_types_rename_prompt"
          end
        end
      end

      notices
    end

    sig { returns(T::Boolean) }
    private def add_to_mwl_waitlist?
      this_memex.eligible_for_memex_without_limits_waitlist? ||
      this_memex.eligible_for_staffship_memex_without_limits_waitlist?
    end

    private def user_is_admin_or_staff_with_write
      head(:forbidden) unless this_memex.viewer_is_admin?(current_user) ||
      (current_user&.employee? && this_memex.viewer_can_write?(current_user))
    end

    # Sets a span attribute that allows us to observe when the "Projects Without Limits" architecture is enabled.
    sig { void }
    private def set_pwl_span_attribute
      GitHub.current_span&.set_attribute("gh.project.pwl_enabled", memex_table_without_limits_enabled?)
    end
  end
end
