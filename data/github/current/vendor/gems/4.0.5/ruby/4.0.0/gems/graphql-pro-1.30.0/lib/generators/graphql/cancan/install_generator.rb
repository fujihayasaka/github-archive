# frozen_string_literal: true
module Graphql
  module Generators
    module Cancan
      class InstallGenerator < Rails::Generators::Base
        desc "Add setup code for GraphQL::Pro::CancanIntegration"

        def add_cancan_setup
          inject_into_class "app/graphql/types/base_object.rb", "BaseObject", "    include GraphQL::Pro::CanCanIntegration::ObjectIntegration\n    # Add a default ability here, or `nil` to require nothing by default:\n    # can_can_action :read\n"
          inject_into_file "app/graphql/types/base_interface.rb", "    include GraphQL::Pro::CanCanIntegration::InterfaceIntegration\n", after: "include GraphQL::Schema::Interface\n"
          inject_into_class "app/graphql/types/base_union.rb", "BaseUnion", "    include GraphQL::Pro::CanCanIntegration::UnionIntegration\n"
          inject_into_class "app/graphql/types/base_field.rb", "BaseField", "    include GraphQL::Pro::CanCanIntegration::FieldIntegration\n    # Add a default ability here, or `nil` to require nothing by default:\n    # can_can_action :read\n"
          inject_into_class "app/graphql/types/base_argument.rb", "BaseArgument", "    include GraphQL::Pro::CanCanIntegration::ArgumentIntegration\n    # Add a default ability here, or `nil` to require nothing by default:\n    # can_can_action :read\n"
          inject_into_class "app/graphql/resolvers/base_resolver.rb", "BaseResolver", "    include GraphQL::Pro::CanCanIntegration::ResolverIntegration\n    # Add a default ability here, or `nil` to require nothing by default:\n    # can_can_action :read\n"
          inject_into_class "app/graphql/mutations/base_mutation.rb", "BaseMutation", "    include GraphQL::Pro::CanCanIntegration::MutationIntegration\n    # Add a default ability here, or `nil` to require nothing by default:\n    # can_can_action :modify\n"
        end
      end
    end
  end
end
