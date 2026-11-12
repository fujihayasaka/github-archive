# frozen_string_literal: true
module Graphql
  module Generators
    module Pundit
      class InstallGenerator < Rails::Generators::Base
        desc "Add setup code for GraphQL::Pro::PunditIntegration"

        def add_pundit_setup
          inject_into_class "app/graphql/types/base_object.rb", "BaseObject", "    include GraphQL::Pro::PunditIntegration::ObjectIntegration\n    # Add a default role here, or `nil` to disable authorization by default:\n    # pundit_role :viewer\n"
          inject_into_file "app/graphql/types/base_interface.rb", "    include GraphQL::Pro::PunditIntegration::InterfaceIntegration\n", after: "include GraphQL::Schema::Interface\n"
          inject_into_class "app/graphql/types/base_union.rb", "BaseUnion", "    include GraphQL::Pro::PunditIntegration::UnionIntegration\n"
          inject_into_class "app/graphql/types/base_field.rb", "BaseField", "    include GraphQL::Pro::PunditIntegration::FieldIntegration\n    # Add a default role here, or `nil` to disable authorization by default:\n    # pundit_role :viewer\n"
          inject_into_class "app/graphql/types/base_argument.rb", "BaseArgument", "    include GraphQL::Pro::PunditIntegration::ArgumentIntegration\n    # Add a default role here, or `nil` to disable authorization by default:\n    # pundit_role :viewer\n"
          inject_into_class "app/graphql/resolvers/base_resolver.rb", "BaseResolver", "    include GraphQL::Pro::PunditIntegration::ResolverIntegration\n    # Add a default role here, or `nil` to disable authorization by default:\n    # pundit_role :viewer\n"
          inject_into_class "app/graphql/mutations/base_mutation.rb", "BaseMutation", "    include GraphQL::Pro::PunditIntegration::MutationIntegration\n    # Add a default role here, or `nil` to disable authorization by default:\n    # pundit_role :viewer\n"
        end
      end
    end
  end
end
