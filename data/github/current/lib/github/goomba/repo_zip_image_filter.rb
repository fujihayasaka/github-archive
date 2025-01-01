# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Strips the source of images linking to repo ZIP archives
  #
  #   Example: <img src="https://github.com/owner/repo/archive/refs/heads/main.zip">
  #   Becomes: <img src="">
  #
  # Addresses security bounty: https://github.com/github/repos/issues/12370
  class RepoZipImageFilter < NodeFilter
    ARCHIVE_URL = %r{
      (#{GitHub.url})? # Absolute GitHub URL, optional
      (\/(\.\.\/)*)?   # Relative path, optional
      /([^/]+)         # user
      /([^/]+)         # repo
      /archive         # string literal "archive"
      /refs            # string literal "refs"
      /heads|tags      # string literals "heads" or "tags"
      /(.*)            # ref-ish
    }x

    SELECTOR = Goomba::Selector.new("img, picture")
    PICTURE_CHILD_SELECTOR = Goomba::Selector.new("img, source")

    def initialize(*args)
      super
    end

    def selector
      SELECTOR
    end

    URL_ATTRIBUTES = {
      img: "src",
      source: "srcset",
    }.freeze

    def call(element)
      if URL_ATTRIBUTES[element.tag]
        process(element)
      elsif element.tag.nil? # goomba doesn't recognize <picture> and sets element.tag to nil
        element.select(PICTURE_CHILD_SELECTOR).each do |child|
          process(child) if URL_ATTRIBUTES[child.try(:tag)]
        end
      end
    end

    def self.feature_flags
      [:strip_repo_zip_images]
    end

    def self.enabled?(context)
      GitHub.flipper[:strip_repo_zip_images].enabled?
    end

    private

    def process(element)
      attribute = URL_ATTRIBUTES[element.tag]
      original_url = element[attribute]

      if ARCHIVE_URL.match(original_url)
        element[attribute] = ""
      end

      element
    end
  end
end
