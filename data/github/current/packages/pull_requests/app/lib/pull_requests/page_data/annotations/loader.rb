# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Annotations
  class Loader
    include GitHub::Memoizer
    include GitHub::ResilienceMixin

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

      annotations.map do |annotation|
        path = annotation.path.dup.force_encoding("UTF-8")

        Annotation.new(
          annotation_level: annotation.annotation_level,
          app_avatar_alt_text: app_avatar_alt_text(check_suite: annotation.check_run.check_suite),
          app_avatar_url: app_avatar_url(check_suite: annotation.check_run.check_suite),
          check_run: CheckRun.new(
            details_url: "#{annotation.check_run.details_url}?pr=#{@pull_request.number}",
            name: annotation.parent_name,
          ),
          check_suite_name: annotation.check_run.check_suite.name,
          database_id: annotation.id,
          end_line: annotation.end_line,
          id: annotation.global_relay_id,
          message: GitHub::Goomba::ActionsAnnotationPipeline.to_html(annotation.message),
          path: path,
          path_digest: Digest::SHA256.hexdigest(path),
          start_line: annotation.start_line,
          title: annotation.title.dup.force_encoding("UTF-8"),
        )
      end
    end

    private

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
