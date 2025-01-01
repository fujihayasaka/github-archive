# typed: true
# frozen_string_literal: true

module Files
  class OverviewPageTitle
    include ActionView::Helpers::CaptureHelper
    include ResilienceHelper

    BRAND = "GitHub"
    EMOJI = /\s+:[A-Za-z_]+:\s+/

    def initialize(repository:, ref:, logged_in:)
      @repository = repository
      @ref        = ref || default_ref_name
      @logged_in  = logged_in
    end

    def to_s
      show_branding? ? branded_title : title
    end

    private

    attr_reader :ref, :repository, :format

    def show_branding?
      !logged_in?
    end

    def branded_title
      "#{BRAND} - #{title}"
    end

    def title
      include_ref? ? name_and_ref : name_and_description
    end

    def name_and_ref
      "#{name} at #{ref}".dup.force_encoding("UTF-8").scrub!
    end

    def name_and_description
      [name, description].reject(&:blank?).join(": ")
    end

    def name
      repository.name_with_display_owner
    end

    def description
      repository.description.to_s.gsub(EMOJI, " ").strip
    end

    def include_ref?
      !on_default_branch?
    end

    def on_default_branch?
      ref == default_ref_name
    end

    def logged_in?
      @logged_in
    end

    def default_ref_name
      with_database_error_fallback(fallback: "master") do
        repository.default_branch_ref&.name || "master"
      end
    end
  end
end
