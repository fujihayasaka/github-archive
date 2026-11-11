# Extracts dependencies from setup.py files by parsing with tree-sitter
# and then traversing the AST.
#
# setup.py files have the following basic format:
#
#   from setuptools import setup
#
#   setup(
#       name="package-name",
#       version="0.4.0",
#       install_requires=[
#           "numpy",
#           "scipy==4.5.0",
#       ])
#
# Parsing setup.py manifests is challenging since they are executable python
# code. `setup` arguments can be defined in variables or expressions, and
# `setup` itself might be called from within a conditional. We do our best to
# cover common constructs.
module ManifestAdapters
  module Pip
    module Parsers
      class SetupPy < ManifestAdapters::Parsers::Base
        def initialize(content)
          @content = content
          @setup_args_hsh = {}
        end

        def name
          return @name if defined?(@name)

          argument = setup_arg("name")

          @name = clean_string(argument&.text) if argument&.node_type == "string"
        end

        def version
          return @version if defined?(@version)

          argument = setup_arg("version")

          @version = clean_string(argument&.text) if argument.node_type == "string"
        end

        def dependencies
          @dependencies ||= runtime_dependencies + development_dependencies
        rescue Pip::DependencyString::ParseError
          @malformed = true
          @dependencies = []
        end

        def malformed?
          dependencies
          !!@malformed
        end

        private

        attr_accessor :setup_args_hsh

        def content
          @sanitized ||= @content.gsub("\u0000", "")
        end

        def ast
          @ast ||= Ast.new(content, language: Ast::Languages::PYTHON)
        end

        def runtime_dependencies
          Array(runtime_packages.compact).map do |dependency|
            parse_dependency(dependency, scope: Types::Scope[:runtime])
          end
        end

        def development_dependencies
          Array(development_packages.compact).map do |dependency|
            parse_dependency(dependency, scope: Types::Scope[:development])
          end
        end

        def parse_dependency(dependency, scope:)
          package_name, requirements = Pip::DependencyString.parse(dependency).values_at(:package_name, :requirements)

          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            requirements: requirements.to_s,
            raw_requirements: requirements.to_s,
            scope: scope,
          )
        end

        def runtime_packages
          packages setup_arg("install_requires")
        end

        def development_packages
          packages setup_arg("tests_require")
        end

        def packages(requires)
          # `install_requires`/`test_requires` can be a multiline string or an
          # iterable containing strings.
          case requires.node_type
          when "list", "tuple"
            requires.named_children
              .filter("string")
              .map { |string| clean_string(string.text) }
              .reject(&:blank?)
          when "string"
            requires.text
              .split("\n")
              .map { |line| clean_string(line).strip }
              .reject(&:blank?)
          else
            []
          end
        end

        def find_assignment(identifier)
          ast.find(node_type: "assignment", text: identifier.text)
        end

        def dict_get(node, key)
          # A dictionary can be defined with a dictionary literal or as arguments
          # passed to the `dict()` function.
          if function_call?(node, "dict")
            args = node.named_children[1].named_children
            get_function_arg(args, key)
          elsif node.node_type == "dictionary"
            node.named_children.filter("pair").inject do |acc, pair|
              if clean_string(pair.named_children[0].text) == key
                break pair.named_children[1]
              end
            end
          end
        end

        def function_call?(node, function_name)
          node.node_type == "call" &&
            node.named_children[0].text == function_name
        end

        def clean_string(string)
          string&.gsub(/'|"/, "")
        end

        def setup_arg(name)
          return setup_args_hsh[name] if setup_args_hsh.has_key?(name)
          # Oh cool, setup.py has called `setup(**kwargs)` with a variable
          # rather than passing args to the setup function directly. We attempt
          # to find the variable assignment.
          argument = if setup_args[0].node_type == "dictionary_splat"
            value = find_assignment(setup_args[0].named_children[0])
              .named_children[1]
              .named_children[0]

            dict_get(value, name) || ast.null_node
          else
            get_function_arg(setup_args, name)
          end

          # If the argument is an identifier rather than a value, we need to
          # find where the identifier was assigned.
          if argument.node_type == "identifier"
            assignment = find_assignment(argument)
            argument = assignment.named_children[1].named_children[0]
          end

          setup_args_hsh[name] = argument
          argument
        end

        def setup_args
          @setup_args ||= compute_setup_args
        end

        def compute_setup_args
          walker = ast.walker

          # Walk the AST looking for a qualified or unqualified `setup()` call.
          while node = walker.next do
            if function_call?(node, "setup") || function_call?(node, "setuptools.setup")
              return node.named_children[1].named_children
            end
          end
        rescue StopIteration
          ast.null_children
        end

        def get_function_arg(args, name)
          args.each do |child|
            next unless child.node_type == "keyword_argument"

            if child.named_children[0].text == name
              return child.named_children[1]
            end
          end

          ast.null_node
        end
      end
    end
  end
end
