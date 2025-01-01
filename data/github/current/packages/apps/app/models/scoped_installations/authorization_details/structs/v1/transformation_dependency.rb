# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V1::TransformationDependency
        extend T::Helpers

        requires_ancestor { V1 }

        sig { params(version: Integer).returns(PublicMethods) }
        def transform(version: 2)
          case version
          when 2
            transform_to_v2
          else
            raise ArgumentError, "Unsupported authorization details version: #{version}"
          end
        end

        sig { returns(PublicMethods) }
        def transform_to_v2
          T.bind(self, V1)

          GitHub.tracer.in_span("ScopedInstallations::AuthorizationDetails::Structs::V1::TransformationDependency.transform_to_v2", kind: :internal) do |_span|
            struct = Builder.build(version: 2)

            if self.selections.present?
              T.must(self.selections).each do |resource_type, selection|
                new_selection =
                  case selection
                  when Selection::Subset
                    subject_ids_for(resource_type)
                  else
                    selection
                  end

                permissions = subject_types_and_actions_for(resource_type).transform_values(&:to_sym)
                struct.add_permissions_selection(resource_type:, permissions:, selection: new_selection)
              end
            end

            if self.asymmetric.present?
              T.must(self.asymmetric).each do |resource_type, asymmetric_access_for_resource_type|
                asymmetric_access_for_resource_type.each do |name, actions_and_subject_ids|
                  actions_and_subject_ids.each do |action, subject_ids|
                    struct.add_permissions_selection(resource_type:, permissions: { name => action.to_sym }, selection: subject_ids)
                  end
                end
              end
            end

            struct
          end
        end
      end
    end
  end
end
