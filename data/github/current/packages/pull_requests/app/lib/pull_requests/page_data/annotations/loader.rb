# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Annotations
  class Loader
    include GitHub::Memoizer
    include GitHub::ResilienceMixin
    include PullRequests::PageData::Telemetry

    PageInfo = PullRequests::PageData::Pagination::PageInfo

    class CheckRun < T::Struct
      const :details_url, String
      const :name, String
    end

    class Annotation < T::Struct
      const :annotation_level, String
      const :app_avatar_alt_text, String
      const :app_avatar_url, String
      const :check_run, CheckRun
      const :check_suite_name, T.nilable(String)
      const :database_id, Integer
      const :end_line, Integer
      const :id, String
      const :message, String
      const :path, String
      const :path_digest, String
      const :start_line, Integer
      const :title, String
    end

    class PaginatedResult < T::Struct
      const :items, T::Array[Annotation]
      const :page_info, PageInfo

      sig { params(page: Integer).returns(PaginatedResult) }
      def self.empty(page: 1)
        new(
          items: [],
          page_info: PageInfo.empty(page: page)
        )
      end
    end

    sig do
      params(
        pull_request: PullRequest,
        end_commit_oid: String,
        user_session: T.nilable(UserSession),
        current_user: T.nilable(User),
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        paths: T::Array[String]
      ).returns(T::Array[Annotation])
    end
    def self.load(pull_request:, end_commit_oid:, user_session:, current_user:, limit_config:, paths:)
      new(pull_request:, end_commit_oid:, user_session:, current_user:, limit_config:, paths:).load
    end

    sig do
      params(
        pull_request: PullRequest,
        end_commit_oid: String,
        user_session: T.nilable(UserSession),
        current_user: T.nilable(User),
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        paths: T::Array[String],
      ).returns(PaginatedResult)
    end
    def self.load_initial_page(pull_request:, end_commit_oid:, user_session:, current_user:, limit_config:, paths:)
      new(
        pull_request:,
        end_commit_oid:,
        user_session:,
        current_user:,
        limit_config:,
        paths:,
      ).load_initial_page
    end

    sig do
      params(
        pull_request: PullRequest,
        end_commit_oid: String,
        user_session: T.nilable(UserSession),
        current_user: T.nilable(User),
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        after_cursor: String,
        paths: T::Array[String],
        page: Integer,
      ).returns(PaginatedResult)
    end
    def self.load_with_cursor(pull_request:, end_commit_oid:, user_session:, current_user:, limit_config:, after_cursor:, paths:, page: 2)
      new(
        pull_request:,
        end_commit_oid:,
        user_session:,
        current_user:,
        limit_config:,
        paths:,
      ).load_with_cursor(after_cursor:, page:)
    end

    sig do params(
      pull_request: PullRequest,
      end_commit_oid: String,
      user_session: T.nilable(UserSession),
      current_user: T.nilable(User),
      limit_config: PullRequests::PageData::Files::PageLimitConfig,
      paths: T::Array[String]
    ).void
    end
    def initialize(pull_request:, end_commit_oid:, user_session:, current_user:, limit_config:, paths:)
      @pull_request = pull_request
      @end_commit_oid = end_commit_oid
      @user_session = user_session
      @current_user = current_user
      @limit_config = limit_config
      @paths = paths
    end

    sig { returns(T::Array[Annotation]) }
    def load
      return [] if @paths.empty?

      annotations = @pull_request.async_compare_repository.then do |repository|
        @limit_config.apply_page_limit(PullRequests::PageData::Files::PageLimitConfig::LimitType::Annotations) do |limit|
          repository.annotations_for(
            inline_only: true,
            limit: limit,
            sha: @end_commit_oid,
            filenames: @paths
          )
        end
      end.sync

      map_annotations(annotations)
    end

    sig { returns(PaginatedResult) }
    def load_initial_page
      with_telemetry do
        with_database_error_fallback(fallback: PaginatedResult.empty(page: 1)) do
          repository = @pull_request.async_compare_repository.sync

          annotations_relation = @limit_config.apply_paginated_max_limit(
            PullRequests::PageData::Files::PageLimitConfig::LimitType::Annotations
          ) do |limit|
            build_annotations_query(repository:).limit(limit)
          end

          annotations = annotations_relation.to_a
          page_size = @limit_config.annotations_limit
          has_next_page = annotations.size > page_size
          first_page = has_next_page ? annotations.take(page_size) : annotations
          cursor = first_page.last&.id&.to_s

          PaginatedResult.new(
            items: map_annotations(first_page),
            page_info: PageInfo.new(
              has_next_page: has_next_page,
              cursor: cursor,
              page: 1
            )
          )
        end
      end
    end

    sig { params(after_cursor: String, page: Integer).returns(PaginatedResult) }
    def load_with_cursor(after_cursor:, page: 2)
      with_telemetry do
        with_database_error_fallback(fallback: PaginatedResult.empty(page: page)) do
          page_size = @limit_config.annotations_limit
          total_limit = @limit_config.annotations_paginated_limit

          previously_loaded = (page - 1) * page_size
          remaining_budget = total_limit - previously_loaded

          if remaining_budget <= 0
            return PaginatedResult.empty(page: page)
          end

          effective_limit = [page_size, remaining_budget].min

          repository = @pull_request.async_compare_repository.sync
          annotations_with_extra = build_annotations_query(repository:, cursor: after_cursor)
            .limit(effective_limit + 1)
            .to_a

          has_more_in_db = annotations_with_extra.size > effective_limit
          annotations = has_more_in_db ? annotations_with_extra.take(effective_limit) : annotations_with_extra

          total_loaded_after = previously_loaded + annotations.size
          has_next_page = !!(has_more_in_db && total_loaded_after < total_limit)

          PaginatedResult.new(
            items: map_annotations(annotations),
            page_info: PageInfo.new(
              has_next_page: has_next_page,
              cursor: annotations.last&.id&.to_s,
              page: page
            )
          )
        end
      end
    end

    private

    sig { params(repository: Repository, cursor: T.nilable(String)).returns(ActiveRecord::Relation) }
    def build_annotations_query(repository:, cursor: nil)
      return CheckAnnotation.none if @paths.empty?

      # Use annotations_for as the canonical base query, then layer in
      # ordering and cursor support. Callers override the limit via .limit().
      base = repository.annotations_for(
        inline_only: true,
        sha: @end_commit_oid,
        filenames: @paths,
        limit: ::CheckAnnotation::MAX_READ_LIMIT,
      ).reorder(id: :asc)

      if cursor.present?
        base.where("check_annotations.id > ?", cursor.to_i)
      else
        base
      end
    end

    sig { params(annotations: T::Enumerable[::CheckAnnotation]).returns(T::Array[Annotation]) }
    def map_annotations(annotations)
      annotations.map do |annotation|
        path = annotation.path.dup.force_encoding("UTF-8")
        check_run = annotation.check_run
        next unless check_run

        check_suite = check_run.check_suite
        next unless check_suite

        Annotation.new(
          annotation_level: annotation.annotation_level,
          app_avatar_alt_text: app_avatar_alt_text(check_suite: check_suite),
          app_avatar_url: app_avatar_url(check_suite: check_suite),
          check_run: CheckRun.new(
            details_url: "#{check_run.details_url}?pr=#{@pull_request.number}",
            name: annotation.parent_name,
          ),
          check_suite_name: check_suite.name,
          database_id: annotation.id,
          end_line: annotation.end_line,
          id: annotation.global_relay_id,
          message: GitHub::Goomba::ActionsAnnotationPipeline.to_html(annotation.message),
          path: path,
          path_digest: Digest::SHA256.hexdigest(path),
          start_line: annotation.start_line,
          title: annotation.title.dup.force_encoding("UTF-8"),
        )
      end.compact
    end

    sig { params(check_suite: CheckSuite).returns(String) }
    def app_avatar_url(check_suite:)
      avatar_size = 20
      with_database_error_fallback(fallback: ::User.ghost.primary_avatar_url(avatar_size)) do
        integration = check_suite.github_app
        installation_view = InstallationView.new(
          integratable: integration,
          session: @user_session,
          current_user: @current_user
        )
        listing = integration.marketplace_listing
        show_marketplace_logo = listing.try(:publicly_listed?) || installation_view.current_user_has_active_subscription_for_marketplace_listing?

        if show_marketplace_logo
          listing.primary_avatar_url(avatar_size * 2)
        else
          integration.preferred_avatar_url(size: avatar_size)
        end
      end
    end

    sig { params(check_suite: CheckSuite).returns(String) }
    def app_avatar_alt_text(check_suite:)
      with_database_error_fallback(fallback: "#{User.ghost.display_login} avatar image") do
        "#{check_suite.github_app.name} avatar image"
      end
    end
  end
end
