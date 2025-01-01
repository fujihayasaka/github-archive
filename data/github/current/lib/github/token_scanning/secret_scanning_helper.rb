# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

module GitHub
  module TokenScanning
    module SecretScanningHelper
      include SecretScanning::Errors

      GITHUB_ACCESS_TOKEN_TYPES_REVOKABLE = T.let(%w(GITHUB GITHUB_PERSONAL_ACCESS_TOKEN GITHUB_OAUTH_ACCESS_TOKEN GITHUB_USER_TO_SERVER_TOKEN GITHUB_REFRESH_TOKEN GITHUB_SERVER_TO_SERVER_TOKEN GITHUB_APP_TOKEN).freeze, T::Array[String])
      PUBLIC_KEY_TYPES_REVOKABLE = T.let(%w(ARMORED_PEM_PRIVATE_KEY GITHUB_SSH_PRIVATE_KEY).freeze, T::Array[String])
      GITHUB_TOKEN_V2_TOKEN_TYPES_REVOKABLE = T.let(%w(GITHUB_TOKEN_V2).freeze, T::Array[String])

      sig { params(alert: GitHub::TokenScanning::Service::Token).returns(T::Boolean) }
      def is_revokable_type?(alert)
        is_oauth_revokable_type?(alert) || is_public_key_revokable_type?(alert) || is_patv2_revokable_type?(alert)
      end

      sig { params(alert: GitHub::TokenScanning::Service::Token).returns(T::Boolean) }
      def is_oauth_revokable_type?(alert)
        GITHUB_ACCESS_TOKEN_TYPES_REVOKABLE.include?(alert.token_type)
      end

      sig { params(alert: GitHub::TokenScanning::Service::Token).returns(T::Boolean) }
      def is_public_key_revokable_type?(alert)
        PUBLIC_KEY_TYPES_REVOKABLE.include?(alert.token_type)
      end

      sig { params(alert: GitHub::TokenScanning::Service::Token).returns(T::Boolean) }
      def is_patv2_revokable_type?(alert)
        GITHUB_TOKEN_V2_TOKEN_TYPES_REVOKABLE.include?(alert.token_type)
      end

      sig { params(repository: Repository, user: User, numbers: T::Array[Integer], resolution: String, dismissal_comment: T.nilable(String)).returns(T.nilable(StandardError)) }
      def resolve_token(repository:, user:, numbers:, resolution:, dismissal_comment: nil)
        resolution = resolution.to_s.to_sym
        service_resolution = GitHub::TokenScanning::Service::Client.to_resolution(resolution)
        return UnprocessableEntity.new unless service_resolution.present?

        # send request to API
        error = resolve_from_service(repository: repository, user: user, numbers: numbers, resolution: service_resolution, dismissal_comment: dismissal_comment)

        if error != nil
          return error
        end

        numbers.each do |numbers|
          log_audit_entry_for_resolution(user, repository, numbers.to_i, resolution, "") # Note, currently unused. Should we delete the method?
        end

        nil
      end

      sig { params(comment: T.nilable(String)).returns(T.nilable(String)) }
      def normalize_dismissal_comment(comment)
        if comment.nil? || comment.empty?
          return nil
        end
        comment.encode("UTF-8", universal_newline: true)
      end

      sig { params(repository: Repository, user: User, numbers: T::Array[Integer], resolution: Integer, dismissal_comment: T.nilable(String)).returns(T.nilable(StandardError)) }
      def resolve_from_service(repository:, user:, numbers:, resolution:, dismissal_comment: nil)
        feature_flags = []
        response = GitHub::TokenScanning::Service::Client.new(user).resolve_tokens(
          repository_id: repository.id,
          token_numbers: numbers,
          resolver_id: user.id,
          resolution: resolution,
          default_branch_name: repository.default_branch,
          feature_flags: feature_flags,
          resolution_comment: dismissal_comment,
        )

        if response.nil?
          return StandardError.new("timeout when resolving token")
        end

        if response.error.present?
          return StandardError.new(response.error.msg)
        end

        nil
      end

      sig { params(user: User, repo: Repository, id: Integer, resolution: Symbol, slug: String).void }
      def log_audit_entry_for_resolution(user, repo, id, resolution, slug)
        payload = {
            user: user,
            repo: repo,
            number: id,
            secret_type: slug,
        }
        if repo.in_organization?
          payload[:org] = repo.organization
        end

        if repo.emu_user_owned?
          payload[:emu_owner] = repo.owner
        end

        if resolution == :reopened
          GitHub.instrument("secret_scanning_alert.reopen", payload)
        else
          payload[:resolution] = resolution.to_s
          GitHub.instrument("secret_scanning_alert.resolve", payload)
        end
      end

      ALL_PROTO_REPO_VISIBILITIES = T.let([
        GitHub::Proto::SecretScanning::Api::V2::RepositoryVisibility::REPOSITORY_VISIBILITY_PUBLIC,
        GitHub::Proto::SecretScanning::Api::V2::RepositoryVisibility::REPOSITORY_VISIBILITY_PRIVATE,
        GitHub::Proto::SecretScanning::Api::V2::RepositoryVisibility::REPOSITORY_VISIBILITY_INTERNAL
      ], T::Array[Integer])

      API_RESOLUTION_OPTIONS = T.let([
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED,
          slug: "revoked"
        },
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE,
          slug: "false_positive"
        },
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::USED_IN_TESTS,
          slug: "used_in_tests"
        },
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::WONT_FIX,
          slug: "wont_fix"
        },
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::PATTERN_EDITED,
          slug: "pattern_edited"
        },
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::PATTERN_DELETED,
          slug: "pattern_deleted"
        },
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::HIDDEN_BY_CONFIG,
          slug: "hidden_by_config"
        }
      ], T::Array[T::Hash[Symbol, T.untyped]])

      API_VALIDITY_OPTIONS = T.let([
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_ACTIVE,
          slug: "active"
        },
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_INACTIVE,
          slug: "inactive"
        },
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_UNKNOWN,
          slug: "unknown"
        },
      ], T::Array[T::Hash[Symbol, T.untyped]])

      API_SORT_ORDER_OPTIONS = T.let([
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_ASCENDING,
          sort_slug: "created",
          direction_slug: "asc"
        },
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_DESCENDING,
          sort_slug: "created",
          direction_slug: "desc"
        },
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::SortOrder::UPDATED_ASCENDING,
          sort_slug: "updated",
          direction_slug: "asc"
        },
        {
          service_enum: GitHub::Proto::SecretScanning::Api::V2::SortOrder::UPDATED_DESCENDING,
          sort_slug: "updated",
          direction_slug: "desc"
        }
      ], T::Array[T::Hash[Symbol, T.untyped]])

      sig { params(sort: T.nilable(String), direction: T.nilable(String)).returns(Integer) }
      def get_service_enum_from_sort_order(sort, direction)
        sort = "created" if sort.blank?
        direction = "desc" if direction.blank?
        service_enum = T.let(GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_DESCENDING, Integer)
        API_SORT_ORDER_OPTIONS.each do |option|
          next unless sort == option[:sort_slug] && direction == option[:direction_slug]
          service_enum = option[:service_enum]
        end
        service_enum
      end

      sig { params(resolution: String).returns(T.nilable(String)) }
      def resolution_description(resolution)
        case resolution
        when "revoked" then "revoked"
        when "false_positive" then "false positive"
        when "used_in_tests" then "used in tests"
        when "wont_fix" then "won't fix"
        when "pattern_deleted" then "pattern deleted"
        when "pattern_edited" then "pattern edited"
        when "hidden_by_config" then "ignored by configuration"
        end
      end

      sig { params(resolution: String).returns(T.nilable(Integer)) }
      def get_service_enum_from_alert_resolution(resolution)
        service_num = T.let(nil, T.nilable(Integer))
        API_RESOLUTION_OPTIONS.each do |option|
          next unless resolution == option[:slug]
          service_num = option[:service_enum]
        end
        service_num
      end

      sig do
        params(
          validity_param: T.nilable(String)
        ).returns(
          {
            error: T.nilable(String),
            validities: T::Array[T.nilable(Integer)]
          }
        )
      end
      def get_service_enums_from_validity_param(validity_param)
        if validity_param.blank?
          return { error: nil, validities: [] }
        end
        validities = []
        validity_param.split(",").each do |validity|
          service_enum = get_service_enum_from_alert_validity(validity)
          if service_enum.nil?
            return { error: "validity is invalid: it must be one of 'active', 'inactive', or 'unknown'", validities: [] }
          end
          validities << service_enum
          # since `revoked` is consolidated into `inactive`, add `revoked`` when the user has requested `inactive``
          if service_enum == GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_INACTIVE
            validities << GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_REVOKED
          end
          # since `unverifiable` is consolidated into `unknown`, add `unverifiable`` when the user has requested `unknown``
          if service_enum == GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_UNKNOWN
            validities << GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_UNVERIFIABLE
          end
        end
        { error: nil, validities: validities }
      end

      sig { params(resolution: String).returns(T.nilable(String)) }
      def get_slug_value_from_alert_resolution(resolution)
        slug_value = nil

        service_num = get_service_enum_from_alert_resolution(resolution)
        option = Search::Queries::SecurityCenter::SecretScanningQuery::RESOLUTION_OPTIONS
          .find { |option| option[:service_enum] == service_num }
        slug_value = option[:slug] if option.present?

        slug_value
      end

      ## Retrieves blobs using blob ids from a given list of locations
      sig { params(repository: Repository, locations: T::Array[SecretScanning::Models::Location]).returns(T.nilable(T::Hash[String, T.untyped])) }
      def fetch_blobs(repository, locations)
        non_archive_locations = locations.reject { |location| location.start_line.zero? && location.end_line.zero? }
        blob_oids = non_archive_locations.map(&:blob_oid)
        return {} unless blob_oids.present?

        repo_blobs_by_oid = {}

        begin
          repo_blobs_by_oid = repository.read_objects(blob_oids, "blob", true, feature_flag: :secret_scanning_helper_read_objects_spokes_api).index_by { |blob| blob["oid"] }
        rescue NoMethodError, GitRPC::InvalidObject, GitRPC::ObjectMissing => e
          GitHub.logger.error(
            "Encountered exception while fetching blobs for repo locations",
            "code.namespace": "GitHub::TokenScanning::SecretScanningHelper",
            "code.function": "fetch_blobs",
            "repo.id": repository.id,
            "exception.message": e.message,
            "blob_oids": blob_oids.join(","),
          )
        end

        wiki_blobs_by_oid = {}

        if repository.unsullied_wiki.exist?
          begin
            wiki_blobs_by_oid = repository.unsullied_wiki.read_objects(blob_oids, "blob", true, feature_flag: :secret_scanning_helper_read_objects_spokes_api).index_by { |blob| blob["oid"] }
          rescue NoMethodError, GitRPC::InvalidObject, GitRPC::ObjectMissing => e
            GitHub.logger.error(
              "Encountered exception while fetching blobs for repo locations",
              "code.namespace": "GitHub::TokenScanning::SecretScanningHelper",
              "code.function": "fetch_blobs",
              "repo.id": repository.id,
              "exception.message": e.message,
              "blob_oids": blob_oids.join(","),
            )
          end
        end

        repo_blobs_by_oid.merge(wiki_blobs_by_oid)
      end

      sig { params(visibilities: T::Array[String]).returns(T::Array[Integer]) }
      def from_repo_visibilities_to_proto_enums(visibilities)
        visibilities.map { |visibility| from_repo_visibility_to_proto_enum(visibility) }.compact
      end

      sig { params(visibility: String).returns(T.nilable(Integer)) }
      def from_repo_visibility_to_proto_enum(visibility)
        case visibility
        when Repository::PUBLIC_VISIBILITY
          GitHub::Proto::SecretScanning::Api::V2::RepositoryVisibility::REPOSITORY_VISIBILITY_PUBLIC
        when Repository::PRIVATE_VISIBILITY
          GitHub::Proto::SecretScanning::Api::V2::RepositoryVisibility::REPOSITORY_VISIBILITY_PRIVATE
        when Repository::INTERNAL_VISIBILITY
          GitHub::Proto::SecretScanning::Api::V2::RepositoryVisibility::REPOSITORY_VISIBILITY_INTERNAL
        end
      end

      # private
      sig { params(validity: String).returns(T.nilable(Integer)) }
      def get_service_enum_from_alert_validity(validity)
        service_enum = T.let(nil, T.nilable(Integer))
        API_VALIDITY_OPTIONS.each do |option|
          next unless validity == option[:slug]
          service_enum = option[:service_enum]
        end
        service_enum
      end
    end
  end
end
