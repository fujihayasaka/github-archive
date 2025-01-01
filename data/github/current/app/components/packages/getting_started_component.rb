# typed: true
# frozen_string_literal: true

module Packages
  class GettingStartedComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    include SvgHelper

    DOCUMENTATION_BASE_URL = "https://docs.github.com/packages"

    attr_reader :owner, :ecosystems

    def initialize(owner:)
      @owner = owner.instance_of?(Repository) ? owner.owner : owner

      @ecosystems = {
        docker: {
          display_name: "Docker",
          name: "docker",
          description: "A software platform used for building applications based on containers — small and lightweight execution environments.",
          enterprise_key: "DOCKER_PROTO_ENABLED",
          documentation_path: "/working-with-a-github-packages-registry/working-with-the-docker-registry",
          beta: false
        },
        maven: {
          display_name: "Apache Maven",
          name: "maven",
          description: "A default package manager used for the Java programming language and the Java runtime environment.",
          enterprise_key: "MAVEN_PROTO_ENABLED",
          documentation_path: "/working-with-a-github-packages-registry/working-with-the-apache-maven-registry",
          beta: false
        },
        nuget: {
          display_name: "NuGet",
          name: "nuget",
          description: "A free and open source package manager used for the Microsoft development platforms including .NET.",
          enterprise_key: "NUGET_PROTO_ENABLED",
          documentation_path: "/working-with-a-github-packages-registry/working-with-the-nuget-registry",
          beta: false
        },
        rubygems: {
          display_name: "RubyGems",
          name: "rubygems",
          description: "A standard format for distributing Ruby programs and libraries used for the Ruby programming language.",
          enterprise_key: "RUBYGEMS_PROTO_ENABLED",
          documentation_path: "/working-with-a-github-packages-registry/working-with-the-rubygems-registry",
          beta: false
        },
        npm: {
          display_name: "npm",
          name: "npm",
          description: "A package manager for JavaScript, included with Node.js. npm makes it easy for developers to share and reuse code.",
          enterprise_key: "NPM_PROTO_ENABLED",
          documentation_path: "/working-with-a-github-packages-registry/working-with-the-npm-registry",
          beta: false
        },
        containers: {
          display_name: "Containers",
          name: "container",
          description: "A single place for your team to manage Docker images and decide who can see and access your images.",
          enterprise_key: "CONTAINERS_PROTO_ENABLED",
          documentation_path: "/working-with-a-github-packages-registry/working-with-the-container-registry",
          beta: false
        },
      }
    end
  end
end
