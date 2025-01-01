# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class Template
    include Enumerable
    include ActiveModel::Model
    include ActiveModel::Attributes

    PROMOTED_TEMPLATES = [:blank, :react, :jupyter, :dotnet]

    FIRST_PARTY_TEMPLATES = {
      blank: {
        name: "Blank",
        language: "",
        description: "Start with a blank canvas or import any packages you need.",
        author: "github",
        icon: "file-added",
        repository_nwo: "github/codespaces-blank",
        active: true,
        slug: :blank,
        default_branch: "main",
      },
      react: {
        name: "React",
        language: "Javascript",
        description: "A popular JavaScript library for building user interfaces based on UI components.",
        author: "github",
        icon_path: ".devcontainer/icon.svg",
        repository_nwo: "github/codespaces-react",
        active: true,
        slug: :react,
        default_branch: "main",
      },
      dotnet: {
        name: ".NET",
        language: "C#",
        description: "A full-stack web application template written in C# leveraging the power of .NET 8.",
        author: "github",
        icon_path: ".devcontainer/icon.svg",
        repository_nwo: "github/dotnet-codespaces",
        active: true,
        slug: :dotnet,
        default_branch: "main",
      },
      rails: {
        name: "Ruby on Rails",
        language: "Ruby",
        description: "A full-stack web framework for building dynamic websites that deliver a rich user experience.",
        author: "github",
        icon_path: ".devcontainer/icon.svg",
        repository_nwo: "github/codespaces-rails",
        active: true,
        slug: :rails,
        default_branch: "main",
      },
      jupyter: {
        name: "Jupyter Notebook",
        language: "Python",
        description: "JupyterLab is the latest web-based interactive development environment for notebooks, code, and data.",
        author: "github",
        icon_path: ".devcontainer/icon.svg",
        repository_nwo: "github/codespaces-jupyter",
        active: true,
        slug: :jupyter,
        default_branch: "main",
      },
      express: {
        name: "Express",
        language: "JavaScript",
        description: "Express is a minimal and flexible Node.js web application framework.",
        author: "github",
        icon_path: ".devcontainer/icon.svg",
        repository_nwo: "github/codespaces-express",
        active: true,
        slug: :express,
        default_branch: "main",
      },
      nextjs: {
        name: "Next.js",
        language: "JavaScript",
        description: "Next.js is a React framework that gives you building blocks to create web applications.",
        author: "github",
        icon_path: ".devcontainer/icon.svg",
        repository_nwo: "github/codespaces-nextjs",
        active: true,
        slug: :nextjs,
        default_branch: "main",
      },
      django: {
        name: "Django",
        language: "Python",
        description: "Django is a high-level Python web framework that encourages rapid development and clean, pragmatic design.",
        author: "github",
        icon_path: ".devcontainer/icon.svg",
        repository_nwo: "github/codespaces-django",
        active: true,
        slug: :django,
        default_branch: "main",
      },
      flask: {
        name: "Flask",
        language: "Python",
        description: "Flask is a lightweight web application framework.",
        author: "github",
        icon_path: ".devcontainer/icon.svg",
        repository_nwo: "github/codespaces-flask",
        active: true,
        slug: :flask,
        default_branch: "main",
      },
      preact: {
        name: "Preact",
        language: "Javascript",
        description: "A fast 3kB alternative to React with the same modern API.",
        author: "github",
        icon_path: ".devcontainer/icon.svg",
        repository_nwo: "github/codespaces-preact",
        active: true,
        slug: :preact,
        default_branch: "main",
      },
    }

    COPILOT = {
      name: "GitHub Copilot",
      language: "Python",
      description: "Try GitHub Copilot in Codespaces.",
      author: "github",
      icon_path: ".devcontainer/icon.png",
      repository_nwo: "github/copilot-codespaces-demo",
      active: true,
      slug: :copilot,
      default_branch: "main",
    }

    PACTOCAT = {
        name: "Pac-tocat",
        language: "Javascript",
        description: "PacMan game starring the lovable GitHub octocat mascot.",
        author: "github",
        icon_path: ".devcontainer/icon.svg",
        repository_nwo: "github/Pac-tocat",
        active: true,
        slug: :"pactocat",
        default_branch: "master",
    }

    attr_reader :data

    attribute :name, :string
    attribute :language, :string
    attribute :description, :string
    attribute :author, :string
    attribute :icon, :string
    attribute :icon_path, :string
    attribute :repository_nwo, :string
    attribute :active, :boolean
    attribute :slug, :string
    attribute :default_branch, :string
    attribute :repository

    delegate :each, to: :data

    def assign_attributes(new_attributes)
      unless new_attributes.respond_to?(:each_pair)
        raise ArgumentError, "When assigning attributes, you must pass a hash as an argument, #{new_attributes.class} passed."
      end

      # Freeze it to prevent direct modification of the data within the Hash.
      @data = new_attributes.with_indifferent_access.freeze
      super
    end

    def [](key)
      if key == :repository || key == "repository"
        repository
      else
        data[key]
      end
    end

    def repository
      return @repository if defined?(@repository)

      @repository = self.class.first_party_repositories_cache[repository_nwo] || Repository.with_name_with_owner(repository_nwo)
    end

    def repository=(repo)
      @repository = repo
    end

    def active?
      !!active && repository.present?
    end

    def verified?
      author == "github"
    end

    def self.all
      @all ||= FIRST_PARTY_TEMPLATES.transform_values { |template| new(template) }
    end

    def self.active
      all.select { |_, template| template.active? }
    end

    def self.promoted_templates
      active.slice(*PROMOTED_TEMPLATES)
    end

    def self.for_repository(repository)
      # First look for a first-party template definition
      return nil unless repository
      template = all.values.find { |template| template.repository_nwo == repository.nwo } # rubocop:disable GitHub/DoNotAllowNameWithOwner used for look up
      return template if template
      return nil unless repository.template?

      # We have a NON-first-party repository template... we can work with this...
      new(
        name: repository.name,
        language: "",
        description: repository.description,
        author: repository.owner.display_login,
        icon: nil,
        repository: repository,
        repository_nwo: repository.full_name,
        active: true,
        slug: nil,
        default_branch: repository.default_branch,
      )
    end

    def self.first_party_repositories_cache
      @first_party_repositories_cache = begin
        first_party_template_nwos = FIRST_PARTY_TEMPLATES.values.map { |template| template[:repository_nwo] }
        repositories_map = Repository.with_names_with_owners(first_party_template_nwos).index_by(&:nwo) # rubocop:disable GitHub/DoNotAllowNameWithOwner
      end
    end

    def self.with_slug(slug)
      return unless slug
      return pactocat if slug.delete("-").downcase == pactocat.slug

      active.values.find { |template| template.slug == slug.to_s }
    end

    def self.pactocat
      new(PACTOCAT)
    end

    def self.copilot
      @copilot ||= new(COPILOT)
    end
  end
end
