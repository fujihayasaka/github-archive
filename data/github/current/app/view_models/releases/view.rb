# typed: true
# frozen_string_literal: true

module Releases
  class View
    class Label
      attr_accessor :name, :text

      def initialize(name = nil, text = nil)
        @name = name
        @text = text
      end

      def css_class
        "label-#{name}"
      end

      def css_label_name
        latest? ? "success" : name
      end

      def display?
        !!name
      end

      def latest?
        name == :latest
      end
    end

    LABELS = {
      draft: Label.new(:draft, "Draft"),
      latest: Label.new(:latest, "Latest release"),
      prerelease: Label.new(:prerelease, "Pre-release"),
      default: Label.new,
    }.freeze

    def initialize(repository, current_user)
      setup_repository_and_user(repository, current_user)
    end

    # Public
    def pushable_by_current_user?
      @pushable
    end

    def release_label_for(release)
      if release.draft?
        LABELS[:draft]
      elsif release_is_latest?(release)
        LABELS[:latest]
      elsif release.prerelease?
        LABELS[:prerelease]
      else
        LABELS[:default]
      end
    end

    # Public
    # bob [tagged | released] this...
    def author_action(release)
      if release.new_record?
        release.tagged? ? :tagged : :drafted
      else
        release.draft? ? :drafted : :released
      end
    end

    # Public
    # When the author took author_action, if we know
    def author_action_at(release)
      if release.published_at
        release.published_at
      elsif release.created_at
        release.created_at
      end
    end

    def release_object_name(release)
      if release.new_record?
        release.tagged? ? :tag : :draft
      else
        release.draft? ? :draft : :release
      end
    end

    def release_is_latest?(release)
      return false if release.prerelease?
      release == latest_release
    end

    def latest_release
      if @latest_release.nil?
        release = Releases::Public.latest_for_repository(@repository, @current_user)
        @latest_release = release || false
      end

      @latest_release || nil
    end

    def setup_repository_and_user(repository, user)
      @repository = repository
      @current_user = user
      @pushable = repository.pushable_by?(user)
    end
  end
end
