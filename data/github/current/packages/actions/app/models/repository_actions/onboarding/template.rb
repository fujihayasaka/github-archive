# typed: true
# frozen_string_literal: true
require "scout/tech_stack"

module RepositoryActions::Onboarding
  class Template
    include LanguageHelper
    attr_reader(
      :categories,
      :creator,
      :data,
      :description,
      :file_patterns,
      :icon_name,
      :icon_raw_url,
      :id,
      :labels,
      :name,
      :partner,
      :show_filter,
      :source,
      :template_url
    )
    attr_accessor :weight

    def initialize(args)
      @categories = (args["categories"] if args["categories"].is_a?(Array)) || []
      @creator = args["creator"]
      @data = args["data"]
      @description = args["description"]
      @file_patterns = args["filePatterns"] if args["filePatterns"].is_a?(Array)
      @icon_name = "#{args["iconName"] || "octicon workflow"}.svg"
      @icon_raw_url = args["iconRawUrl"]
      @id = args["id"]
      @labels = (args["labels"] if args["labels"].is_a?(Array)) || []
      @name = args["name"]
      @partner = args["partner"]
      @show_filter = args["show_filter"]
      @source = args["source"]
      @source_repository = args["sourceRepository"]
      @template_url = args["templateUrl"]
      @weight = 0
    end

    def add_weight(to_add)
      self.weight += to_add
    end

    def matches_paths?(paths)
      return false if paths.blank? || file_patterns.blank?

      file_patterns.any? do |pattern|
        paths.any? { |path| path && path.match(pattern) }
      end

    rescue RegexpError
      false
    end

    def matches_language?(language)
      language && categories && categories.any? { |category| category.casecmp?(language) }
    end

    def ==(other)
      id == other.id
    end
    alias_method :eql?, :==

    def language
      return nil unless !categories.empty?
      return categories.first if categories.first.casecmp?("Automation") || categories.first.casecmp?("Deployment")
      return "Code scanning" if  categories.first.casecmp?("Code Scanning")
      return "Dependency review" if  categories.first.casecmp?("Dependency Review")

      categories.find { |category| Linguist::Language[category] != nil }
    end

    def lang
      Linguist::Language[language]
    end

    def lang_color
      lang_color = "#3695e3"
      if language&.casecmp?("Automation")
        lang_color = "#f97583"
      elsif lang
        lang_color = language_color(lang)
      end

      lang_color
    end

    def show_code?
      !(language&.casecmp?("Automation"))
    end

    def dark_footer?
      !(language&.casecmp?("Automation"))
    end

    def yaml
      Base64.decode64(data)
    end

    def source_file_name
      template_url.split("/").last(2).join("/")
    end

    def source_repository
      @source_repository || "actions/starter-workflows"
    end
    attr_writer :source_repository

    def default_file_name
      ".github/workflows/#{id.split('/').last}.yml".downcase
    end

    # Returns the "run" commands to show in the UI. They help give a preview of what
    # the template does. Always returns 3 lines.
    def highlighted_template_lines
      template = YAML.safe_load(yaml)
      (find_run_lines(template) + ["", "", ""]).first(3)
    rescue Psych::SyntaxError
      []
    end

    def from_owner?
      source == "owner"
    end

    def creator_name
      return creator if creator.present?
      return "GitHub Actions" unless from_owner?
    end

    def matched_languages(languages)
      template_tech_stack = tech_stack
      return [] unless languages && template_tech_stack

      languages.select { |lang| template_tech_stack.detect { |tts| tts.casecmp?(lang) } }
    end

    def matches_any_language?(languages)
      template_tech_stack = tech_stack
      languages && template_tech_stack && !(languages.map(&:downcase) & template_tech_stack.map(&:downcase)).empty?
    end

    # to find matched tech
    # This assumes RepositoryTechProjectStackContract object will be passed not only tech stack name.
    def matched_tech_stack(repo_tech_stack)
      template_tech_stack = tech_stack
      return [] unless repo_tech_stack && template_tech_stack && !template_tech_stack.empty?

      repo_tech_stack.select { |rts| template_tech_stack.detect { |tts| tts.casecmp?(rts.name) } }
    end

    def matches_any_tech_stack_names?(repo_tech_stack_names)
      !matched_tech_stack_names(repo_tech_stack_names).empty?
    end

    def matched_tech_stack_names(repo_tech_stack_names)
      template_tech_stack = tech_stack
      return [] unless repo_tech_stack_names && template_tech_stack

      repo_tech_stack_names.select { |rts| template_tech_stack.detect { |tts| tts.casecmp?(rts) } }
    end

    # returns the tech_stack in template categories
    def tech_stack
      return [] unless categories
      @tech_stack ||= categories.filter_map do |category|
        if stack = WorkflowTemplateHelper.category_to_tech_stack(category)
          stack.name
        end
      end
    end

    # returns the tech_stack which are not currenlty detected by scout/linguist
    def undetected_tech_stack
      return [] unless categories
      @undetected_tech_stack ||= categories.reject do |category|
        stack = WorkflowTemplateHelper.category_to_tech_stack(category)
        if stack || WorkflowTemplateHelper.filter_category?(category)
          true
        end
      end
    end

    def category
      categories.any? ? categories.first : ""
    end

    private

    # Goes through a nested hash/arrays to find all "run" commands
    def find_run_lines(h)
      lines = []

      h&.keys && h&.keys.each do |key|
        if key == "run" && h[key].is_a?(String)
          lines << h[key].split("\n")
        elsif h[key].is_a?(Hash)
          lines << find_run_lines(h[key])
        elsif h[key].is_a?(Array)
          lines << h[key].map do |v|
            if v.is_a? Hash
              find_run_lines(v)
            end
          end
        end
      end

      lines.flatten.compact
    end
  end
end
