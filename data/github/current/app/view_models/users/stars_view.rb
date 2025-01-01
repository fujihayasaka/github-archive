# typed: true
# frozen_string_literal: true

module Users
  class StarsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    sig { returns(User) }
    attr_reader :user

    sig { returns(T.nilable(User)) }
    attr_reader :viewer

    sig { returns(T.nilable(String)) }
    attr_reader :language

    sig { returns(T.nilable(String)) }
    attr_reader :phrase

    sig { returns(T.nilable(String)) }
    attr_reader :type

    def initialize(**args)
      super(args)
    end

    sig { returns(T::Boolean) }
    def filtering_by_type?
      type.present?
    end

    # Public: Returns true if the user is searching or filtering starred
    # repositories.
    sig { returns(T::Boolean) }
    def filtering?
      return true if filtering_by_type?
      language.present? || phrase.present?
    end

    sig { returns(T.nilable(T.any(Symbol, String))) }
    def selected_language
      language_names = user_languages
      index = language_names.map(&:downcase).index(language)
      index ? language_names[index] : "All languages"
    end

    private

    # Returns alphabetized list of languages for the user's starred repositories.
    sig { returns(T::Array[Symbol]) }
    def user_languages
      user_languages_and_counts.keys.sort
    end

    # The cached counts of the languages in a user's starred repos.
    #
    # Returns a hash of form {:language_name => count}.
    sig { returns(T::Hash[Symbol, Integer]) }
    def user_languages_and_counts
      @user_languages_and_counts ||= user.cached_starred_repository_count_by_language_name(viewer: viewer)
    end
  end
end
