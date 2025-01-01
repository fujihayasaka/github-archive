# typed: strict
# frozen_string_literal: true

module Orca
  class PipelineFormValidator
    include ActiveModel::Validations
    include GitHub::Memoizer

    sig { returns(Organization) }
    attr_accessor :organization
    sig { returns(User) }
    attr_accessor :user
    sig { returns(T::Array[String]) }
    attr_accessor :repository_nwos
    sig { returns(T::Array[Linguist::Language]) }
    attr_accessor :languages
    sig { returns(T::Boolean) }
    attr_accessor :use_private_telemetry

    validates :organization, :user,  presence: true
    validate :ensure_all_nwos_are_valid
    validate :validate_repository_owned_by_org
    validate :validate_within_rate_limit
    # This does not support custom repo defined languages, we may change
    # this some day.
    validate :validate_languages_available

    sig { params(organization: Organization, user: User, use_private_telemetry: T::Boolean, repository_nwos: T.anything, languages: T.anything).void }
    def initialize(organization:, user:, use_private_telemetry:, repository_nwos: [], languages: [])
      @organization = organization
      @user = user
      @repository_nwos = T.let(normalize_params_to_array(repository_nwos, :repository_nwos), T::Array[T.untyped])
      @langs_string = T.let(normalize_params_to_array(languages, :languages).map(&:to_s).reject(&:empty?), T::Array[String])
      @languages = T.let(find_languages(@langs_string), T::Array[Linguist::Language])
      @repositories = T.let(nil, T.nilable(T::Array[Repository]))
      @use_private_telemetry = use_private_telemetry
    end

    sig { params(repositories: T::Array[Repository]).returns(T::Array[Repository]) }
    def repositories=(repositories)
      @repositories = repositories
    end

    sig { params(untyped_params: T.anything, checking_name: Symbol).returns(T::Array[T.untyped]) }
    def normalize_params_to_array(untyped_params, checking_name)
      case untyped_params
      when NilClass
        array_of_params = []
      when String
        array_of_params = [untyped_params]
      when Array
        array_of_params = untyped_params
      else
        array_of_params = [untyped_params]
        errors.add(checking_name, "#{checking_name} are not valid")
      end
      array_of_params
    end

    sig { returns(T::Array[Repository]) }
    memoize def repositories
      return @repositories if @repositories

      if repository_nwos.kind_of?(Array) && repository_nwos.empty?
        return organization.
          repositories.
          not_archived_scope.
          not_forks.
          to_a
      end

      Repository.with_names_with_owners(repository_nwos).to_a
    end

    sig { returns([T::Boolean, T.nilable(String)]) }
    def enqueue_pipeline
      begin
        pipeline = Orca.client.start_customization(
          actor: user,
          organization: organization,
          languages: languages,
          use_private_telemetry: use_private_telemetry,
          repositories: repositories.to_a,
        )
        [true, pipeline]
      rescue Orca::Client::Error, Faraday::Error => err
        Failbot.report_user_error(err)
        GitHub.dogstats.increment("orca.connection.error.create_pipeline")
        [false, nil]
      end
    end

    private

    sig { params(languages: T::Array[String]).returns(T::Array[Linguist::Language]) }
    def find_languages(languages)
      languages.filter_map do |language_name|
        language = safe_find_linguist_language(language_name)
        if language.nil?
          next
        end
        language
      end.flatten.uniq
    end

    sig { void }
    def validate_languages_available
      @langs_string.each do |lang_name|
        unless safe_find_linguist_language(lang_name.to_s)
          errors.add(:languages, "Language #{lang_name} not available")
        end
      end
    end

    sig { params(language_name: String).returns(T.nilable(Linguist::Language)) }
    def safe_find_linguist_language(language_name)
      deparameterized_language_name = language_name.split("-").join(" ")

      Linguist::Language.find_by_name(deparameterized_language_name) ||
        Linguist::Language.find_by_name(language_name) ||
        Linguist::Language.find_by_alias(language_name)
    end

    sig { void }
    def ensure_all_nwos_are_valid
      unless repository_nwos.kind_of?(Array)
        errors.add(:repository_nwos, "must be an array of names or repos with owners")
        return
      end
      all_strings = repository_nwos.all? { |i| i.is_a?(String) }
      unless all_strings
        errors.add(:repository_nwos, "repository_nwos are not valid strings")
        return
      end
      all_have_slashes = repository_nwos.all? { |i| i.include?("/") }
      unless all_have_slashes
        errors.add(:repository_nwos, "repository_nwos do not include the org")
      end
    end

    sig { void }
    def validate_repository_owned_by_org
      unless all_requested_repos_exist?
        errors.add(:repository_nwos, "One of the repositories is not owned by the org")
        return
      end

      unless all_requested_repos_owned_by_org?
        errors.add(:repository_nwos, "One of the repositories is not owned by the org")
      end
    end

    sig { returns(T::Boolean) }
    def all_requested_repos_owned_by_org?
      owned_repos = organization.repositories.pluck(:id)
      repositories.pluck(:id).all? { |id| owned_repos.include?(id) }
    end

    sig { returns(T::Boolean) }
    def all_requested_repos_exist?
      # An empty array means all org repos.
      return true if repository_nwos.empty?
      # Check the request repos against the repos we could fetch to ensure
      # they actually exist in the system
      repository_nwos.length == repositories.length
    end

    sig { returns(T::Boolean) }
    def validate_within_rate_limit
      # TO DO hook up rate limit logic
      true
    end
  end
end
