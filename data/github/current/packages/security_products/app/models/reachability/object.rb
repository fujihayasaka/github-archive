# typed: true
# frozen_string_literal: true

module Reachability
  class Object
    extend T::Sig

    sig { returns(T::Array[Project]) }
    attr_accessor :projects

    sig { returns(T::Array[Advisory]) }
    attr_accessor :vulnerabilities

    def self.schema_version
      1
    end

    class Project
      extend T::Sig

      attr_reader :ecosystem

      sig { returns(T::Array[Manifest]) }
      attr_accessor :manifests

      sig { returns(T::Hash[String, DependencyNode]) }
      attr_accessor :graph  # graph is a hash, possibly an object with find feature in future?


      sig { params(ecosystem: String, manifests: T::Array[Manifest], graph: T::Hash[String, DependencyNode]).void }
      def initialize(ecosystem:, manifests: [], graph: {})
        @ecosystem = ecosystem
        @manifests = manifests
        @graph = graph
      end
    end

    class Manifest
      extend T::Sig

      attr_reader :source_location

      sig { returns(T::Array[DependencyEdge]) }
      attr_accessor :dependencies

      sig { params(source_location: String, dependencies: T::Array[DependencyEdge]).void }
      def initialize(source_location:, dependencies: [])
        @source_location = source_location
        @dependencies = dependencies
      end
    end

    # TODO - build find_or_create for edges in memory?
    class DependencyEdge
      extend T::Sig

      attr_reader :node, :dev

      sig { params(node: String, dev: T::Boolean).void }
      def initialize(node:, dev:)
        @node = node
        @dev = dev
      end
    end

    class DependencyNode
      extend T::Sig

      attr_reader :package_name, :version

      sig { returns(T::Array[DependencyEdge]) }
      attr_accessor :dependencies

      sig { params(package_name: String, version: String, dependencies: T::Array[DependencyEdge]).void }
      def initialize(package_name:, version:, dependencies: [])
        @package_name = package_name
        @version = version
        @dependencies = dependencies
      end
    end

    class Advisory
      extend T::Sig

      attr_reader :ghsa_id, :vulnerabilities

      sig { params(ghsa_id: String, ranges: T::Array[VulnerableVersionRange]).void }
      def initialize(ghsa_id:, ranges: [])
        @ghsa_id = ghsa_id

        @vulnerabilities = ranges.map do |range|
          Vulnerability.new(
            ecosystem: range.ecosystem,
            package_name: range.affects,
            vulnerable_version_range: range.requirements,
            first_patched_version: range.fixed_in,
            vulnerable_functions: range.affected_functions
          )
        end
      end
    end

    class Vulnerability
      extend T::Sig

      attr_reader :package, :vulnerable_version_range, :first_patched_version, :vulnerable_functions

      sig { params(ecosystem: T.nilable(String), package_name: String, vulnerable_version_range: String, first_patched_version: T.nilable(String), vulnerable_functions: T::Array[String]).void }
      def initialize(ecosystem:, package_name:, vulnerable_version_range:, first_patched_version: nil, vulnerable_functions: [])
        @package = {
          ecosystem: ecosystem,
          name: package_name
        }
        @vulnerable_version_range = vulnerable_version_range
        @first_patched_version = first_patched_version
        @vulnerable_functions = vulnerable_functions
      end
    end
  end
end
